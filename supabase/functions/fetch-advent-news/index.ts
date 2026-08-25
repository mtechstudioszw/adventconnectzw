// =====================================================================
//  Edge Function: fetch-advent-news
//
//  Pulls official SDA news RSS feeds and inserts new items into
//  public.advent_news as APPROVED (auto-published to the News tab).
//
//  Source: adventist.news has no public RSS feed (it's an Astro SPA), so
//  we use the official Adventist Review + Adventist World feeds (same
//  SDA news). Add/remove feeds in FEEDS below.
//
//  Scheduled daily via pg_cron (see patch_145). Idempotent: items are
//  de-duplicated by source_url, so re-running never creates duplicates.
//
//  Optional CRON_SECRET env: when set, callers must pass it as
//  ?secret=... or x-cron-secret header (the cron job does).
// =====================================================================
// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FEEDS = [
  { url: "https://adventistreview.org/feed/", label: "Adventist Review" },

  // REMOVED 16 Aug 2026 — "Adventist World"
  // (https://www.adventistworld.org/feed/).
  //
  // That host now redirects to Adventist Review. The feed still answers 200,
  // but it returns Adventist Review's OWN <link> and <description>, a
  // lastBuildDate frozen at Oct 2024, and ZERO <item> elements. So it has
  // been contributing nothing to every run.
  //
  // It was not merely useless, it was a duplicate-import waiting to happen:
  // the channel it serves is already Adventist Review's, so the moment that
  // redirect starts passing items through, every article would be imported a
  // second time under the label "Adventist World" and the news list would
  // read double. Removing it is safer than leaving a dead entry in place.
  //
  // A replacement second source is still wanted. adventist.news and
  // news.adventist.org (Adventist News Network) both look right but returned
  // 429 to every probe from here, so neither could be verified — check them
  // from another network before adding, and confirm they carry images, which
  // is the other half of the covers problem.
];

const PER_FEED = 8; // newest N items per feed per run

function uncdata(s: string): string {
  return (s || "").replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1").trim();
}

function decodeEntities(s: string): string {
  return (s || "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&nbsp;/g, " ");
}

function stripHtml(s: string): string {
  return decodeEntities((s || "").replace(/<[^>]*>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

function tag(block: string, name: string): string {
  const m = block.match(
    new RegExp(`<${name}\\b[^>]*>([\\s\\S]*?)<\\/${name}>`, "i"),
  );
  return m ? uncdata(m[1]) : "";
}

function parseItems(xml: string, label: string) {
  const out: Array<Record<string, string | null>> = [];
  const items = xml.match(/<item\b[\s\S]*?<\/item>/gi) || [];
  for (const it of items) {
    const title = stripHtml(tag(it, "title"));
    let link = uncdata(tag(it, "link"));
    if (!link) link = it.match(/<link[^>]*href="([^"]+)"/i)?.[1] ?? "";
    const descRaw = tag(it, "description");
    const content = tag(it, "content:encoded");
    const img =
      it.match(/<media:content[^>]*url="([^"]+)"/i)?.[1] ??
      it.match(/<media:thumbnail[^>]*url="([^"]+)"/i)?.[1] ??
      it.match(/<enclosure[^>]*url="([^"]+)"/i)?.[1] ??
      content.match(/<img[^>]*src="([^"]+)"/i)?.[1] ??
      descRaw.match(/<img[^>]*src="([^"]+)"/i)?.[1] ??
      null;
    const pubDate = uncdata(tag(it, "pubDate"));
    const summary = stripHtml(descRaw).slice(0, 400);
    if (title && link) {
      out.push({ title, link, summary, img, pubDate, label });
    }
  }
  return out;
}

/// Constant-time compare, so the secret can't be walked out a byte at a
/// time by timing the response. Same helper as purge-storage.
function cronSecretOk(supplied: string | null): boolean {
  const expected = Deno.env.get("CRON_SECRET") ?? "";
  if (expected.length === 0 || supplied === null) return false;
  const a = new TextEncoder().encode(supplied);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

Deno.serve(async (req) => {
  // FAIL CLOSED, including when the env var is missing.
  //
  // This was `if (secret) { ... }` — authentication was skipped entirely
  // whenever CRON_SECRET was unset, on a function that runs with the
  // SERVICE-ROLE key and has verify_jwt off. "Authenticate only if
  // someone remembered to configure a secret" is the idiom that left
  // play-rtdn wide open; it is not repeated here.
  //
  // The secret now travels in a HEADER only. It used to be accepted as
  // `?secret=`, which writes it into edge logs, the dashboard's request
  // view, and any proxy in between. The pg_cron job sends the header.
  if (!cronSecretOk(req.headers.get("x-cron-secret"))) {
    return new Response("forbidden", { status: 403 });
  }

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let inserted = 0;
  const errors: string[] = [];

  for (const feed of FEEDS) {
    try {
      const res = await fetch(feed.url, {
        headers: { "User-Agent": "Mozilla/5.0 (AdventConnectBot)" },
      });
      if (!res.ok) {
        errors.push(`${feed.label}: HTTP ${res.status}`);
        continue;
      }
      const xml = await res.text();
      const items = parseItems(xml, feed.label).slice(0, PER_FEED);
      for (const item of items) {
        const { data: existing } = await sb
          .from("advent_news")
          .select("id")
          .eq("source_url", item.link)
          .maybeSingle();
        if (existing) continue;

        let publishedAt = new Date().toISOString();
        if (item.pubDate) {
          const d = new Date(item.pubDate as string);
          if (!isNaN(d.getTime())) publishedAt = d.toISOString();
        }

        const { error } = await sb.from("advent_news").insert({
          title: (item.title as string).slice(0, 200),
          summary: (item.summary as string) || (item.title as string),
          source_url: item.link,
          source_label: item.label,
          cover_photo_url: item.img,
          category: "general",
          status: "approved", // auto-publish
          published_at: publishedAt,
        });
        if (!error) inserted++;
        else errors.push(`${feed.label}: ${error.message}`);
      }
    } catch (e) {
      errors.push(`${feed.label}: ${(e as Error).message}`);
    }
  }

  return new Response(JSON.stringify({ inserted, errors }), {
    headers: { "Content-Type": "application/json" },
  });
});
