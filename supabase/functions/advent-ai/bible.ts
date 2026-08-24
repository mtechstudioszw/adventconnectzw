// =====================================================================
//  Advent AI — scripture grounding.
//
//  Finds the passages a question is actually about and fetches the REAL
//  text from `bible_verses` (patches 241-251) before the model answers.
//  The model then quotes what it was handed instead of what it
//  remembers, which is the difference between a Bible app and a
//  plausible-sounding guess.
//
//  ## Why retrieval happens here and not as a model tool
//
//  A tool call costs a second round trip to the provider — roughly
//  doubling latency and cost for the commonest question type in the
//  app. Reference detection is a solved problem with a regex, so the
//  common case is served by looking the passage up BEFORE the first
//  call and passing it in. Tools remain the right answer for open-ended
//  retrieval; they are not the right answer for "John 3:16".
//
//  ## The retrieved text is DATA
//
//  Everything returned here is wrapped by `wrapRetrieved` before it
//  reaches the prompt. Scripture is not attacker-controlled, but the
//  boundary is kept uniform on purpose: the day someone adds a
//  user-submitted note to this pipeline, the wrapping is already there.
// =====================================================================
// @ts-nocheck

/// A scripture reference parsed out of free text.
export interface ParsedRef {
  book: string;
  chapter: number;
  verse?: number;
  endVerse?: number;
}

/// Matches the shapes people actually type:
///   John 3:16 · john 3:16-18 · 1 Cor 13 · I Corinthians 13:4-7 · Ps 23
///
/// The leading number group is what makes "1 John" work without also
/// swallowing the "3" in "John 3". Book names are matched loosely and
/// resolved authoritatively by `bible_book_number` in Postgres — this
/// regex decides *where a reference is*, never *which book it is*.
const REF_RE =
  /\b((?:[123]|i{1,3})\s*)?([a-z]{2,}(?:\s+of\s+[a-z]+)?)\.?\s+(\d{1,3})(?:\s*[:.]\s*(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?)?/gi;

/// Words that look like a book name followed by a number but are not.
/// Without this, "psalm 1 verse 2" and "genesis 1 and 2" produce junk
/// lookups, and — worse — "top 10" style phrases in app questions do too.
const NOT_A_BOOK = new Set([
  "chapter", "verse", "verses", "page", "part", "number", "no", "question",
  "step", "point", "day", "week", "year", "version", "top", "level",
]);

export function parseRefs(text: string, limit = 3): ParsedRef[] {
  const out: ParsedRef[] = [];
  const seen = new Set<string>();

  for (const m of text.matchAll(REF_RE)) {
    const prefix = (m[1] ?? "").trim().replace(/\s+/g, "");
    const name = (m[2] ?? "").trim();
    if (NOT_A_BOOK.has(name.toLowerCase())) continue;

    const book = (prefix ? `${prefix} ${name}` : name).trim();
    const chapter = Number.parseInt(m[3], 10);
    const verse = m[4] ? Number.parseInt(m[4], 10) : undefined;
    const endVerse = m[5] ? Number.parseInt(m[5], 10) : undefined;
    if (!Number.isFinite(chapter) || chapter < 1) continue;

    const key = `${book}|${chapter}|${verse ?? ""}|${endVerse ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);

    out.push({ book, chapter, verse, endVerse });
    if (out.length >= limit) break;
  }
  return out;
}

/// True when the question is asking what scripture says about a topic
/// rather than naming a passage. Cheap heuristic — a false positive
/// costs one indexed query, a false negative costs grounding.
export function wantsTopicalSearch(text: string): boolean {
  return /\b(what|where|which|does|verses?|passages?|scripture)\b/i.test(text) &&
    /\b(bible|scripture|verse|passage|say|says|teach|about)\b/i.test(text);
}

/// True when the question plausibly concerns using the app.
///
/// A gate on the app-knowledge lookup. Postgres' websearch_to_tsquery
/// matches loosely by design, so an unrelated question ("what phone
/// should I buy") can still rank an entry — and once app knowledge is in
/// the prompt the model tends to answer it, which is how an off-topic
/// redirect ended up with a paragraph about messaging attached to it.
///
/// Deliberately generous: a missed app question just gets the honest
/// "I'm not sure" the prompt asks for, while a false positive puts words
/// in front of a member who did not ask for them.
const APP_NOUNS =
  /\b(app|profile|posts?|posting|feed|chats?|messages?|groups?|marketplace|seller|sell|buy|orders?|cart|church(?:es)?|events?|prayer|library|hymnal|quiz|watch|settings?|notifications?|account|premium|subscribe|password|report|block)\b/;

const ASKING_HOW =
  /\b(how|where|which|can|cannot|unable|do|does|find|change|create|make|start|open|delete|remove|turn|set|use|add|edit|join|leave)\b/;

export function wantsAppHelp(text: string): boolean {
  const t = text.toLowerCase();
  // Word boundaries matter, and were briefly lost to an escaping bug
  // that wrote literal backspace characters instead: without them
  // "app" matches inside "happen" and "post" inside "postpone", so a
  // question about waiting patiently would pull the marketplace into
  // the prompt.
  return APP_NOUNS.test(t) && ASKING_HOW.test(t);
}

interface VerseRow {
  reference: string;
  text: string;
}

function render(rows: VerseRow[]): string {
  return rows.map((r) => `${r.reference} — ${r.text}`).join("\n");
}

/// Look up app-help entries for a question.
///
/// Same contract as [groundScripture]: never throws, returns null when
/// nothing matched. A miss is meaningful — the prompt then tells the
/// model to admit it is unsure rather than invent a screen.
export async function groundAppHelp(
  admin: { rpc: (fn: string, args: unknown) => Promise<{ data: unknown }> },
  question: string,
): Promise<string | null> {
  try {
    if (!wantsAppHelp(question)) return null;

    const { data } = await admin.rpc("ai_app_help", {
      p_query: question,
      p_limit: 3,
    });
    const rows = (data ?? []) as
      { question: string; answer: string; route?: string }[];
    if (!rows.length) return null;

    return rows
      .map((r) => {
        const where = r.route ? `\n(in the app at: ${r.route})` : "";
        return `Q: ${r.question}\nA: ${r.answer}${where}`;
      })
      .join("\n\n");
  } catch (e) {
    console.error("app-help grounding failed:", e);
    return null;
  }
}

/// Fetch everything worth grounding this question on.
///
/// Returns null when nothing was found, which is a meaningful answer:
/// the prompt's standing rule then applies and the model refers to the
/// passage without pretending to quote it.
///
/// Never throws. Grounding is an improvement to an answer, not a
/// precondition for one — a failed lookup must not cost the member their
/// question. The failure is logged and the model answers unaided, under
/// the no-fabrication rule it already carries.
export async function groundScripture(
  admin: { rpc: (fn: string, args: unknown) => Promise<{ data: unknown }> },
  question: string,
): Promise<string | null> {
  const blocks: string[] = [];

  try {
    for (const ref of parseRefs(question)) {
      const { data } = await admin.rpc("bible_passage", {
        p_book: ref.book,
        p_chapter: ref.chapter,
        p_verse: ref.verse ?? null,
        p_end_verse: ref.endVerse ?? null,
      });
      const rows = (data ?? []) as VerseRow[];
      if (rows.length) blocks.push(render(rows));
    }

    // Only if no explicit reference resolved — a question that names a
    // passage has already been answered better than a keyword search
    // would, and running both wastes context on near-duplicates.
    if (!blocks.length && wantsTopicalSearch(question)) {
      const { data } = await admin.rpc("bible_search", {
        p_query: question,
        p_limit: 6,
      });
      const rows = (data ?? []) as VerseRow[];
      if (rows.length) blocks.push(render(rows));
    }
  } catch (e) {
    console.error("scripture grounding failed:", e);
    return null;
  }

  return blocks.length ? blocks.join("\n\n") : null;
}
