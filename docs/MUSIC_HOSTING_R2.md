# Moving Library audio to Cloudflare R2

Status: **planned, not executed.** Nothing in the app points at R2 yet.

## Why

Storage is cheap everywhere; **egress** is what costs money on a music app.

A 4-minute track at 128 kbps is ~3.8 MB.

| Users | Plays/user/month | Monthly egress | Supabase Pro (250 GB incl., then $0.09/GB) | R2 |
|---|---|---|---|---|
| 1,000 | 20 | ~76 GB | included | $0 |
| 5,000 | 20 | ~380 GB | ~$12/mo over | $0 |
| 20,000 | 20 | ~1.5 TB | ~$115/mo over | $0 |

Cloudflare R2 charges **$0.015/GB stored and zero egress**. A 500-track
catalogue is ~2 GB, so about **$0.03/month, flat, regardless of listeners.**

The catalogue is also the one thing that scales with success rather than with
users — the more music is worth using, the worse the Supabase bill gets.

## What stays where

- **Supabase** keeps `library_items` (metadata, `cover_url`, `sort_order`,
  `is_published`) and all auth/RLS. No schema change.
- **R2** holds only the audio blobs.
- `library_items.file_url` is already a plain public URL, so the app needs
  **no code change** — it just gets different URLs.

Covers can stay in Supabase Storage; they're small and cached hard.

## Steps

1. **Create the bucket.** Cloudflare dashboard → R2 → create bucket
   `advent-music`. Enable a public r2.dev URL, or better, bind a custom
   domain (`media.adventconnect.co.zw`) so URLs survive a provider change.

2. **Copy the existing objects.** Only 10 tracks today, so this is quick.
   With `rclone`:
   ```
   rclone copy supabase:library/music r2:advent-music/music --progress
   ```
   Or download and re-upload by hand at this size.

3. **Rewrite the URLs.** One SQL statement against Supabase:
   ```sql
   update public.library_items
   set file_url = replace(
     file_url,
     'https://eqbyvasteolqyktbqbem.supabase.co/storage/v1/object/public/library/',
     'https://media.adventconnect.co.zw/'
   )
   where kind = 'music';
   ```
   Run a `select` with the same `replace()` first and eyeball the output.

4. **Point new uploads at R2.** `LibraryAdminService.uploadAndAddItem`
   currently does `_client.storage.from('library').uploadBinary(...)` then
   `getPublicUrl(...)`. R2 speaks the S3 API, so either:
   - upload from the admin app with an S3 client (needs R2 keys shipped in
     the app — **don't**, they'd be extractable), or
   - **preferred:** a small Supabase Edge Function that holds the R2
     credentials server-side, takes the file, puts it in R2, and returns the
     public URL. The app calls the function instead of Supabase Storage.

5. **Verify offline downloads still work.** `MusicDownloadService` fetches
   `item.fileUrl` over plain HTTP and caches to disk — provider-agnostic, so
   it should be unaffected. Confirm on a device anyway: R2 must serve
   `Accept-Ranges` for seeking, which it does by default.

## Gotchas

- **CORS** only matters for Flutter Web. If a web build ever happens, set an
  R2 CORS policy allowing the origin.
- **Cache headers.** The current Supabase upload sets `cacheControl: '3600'`
  (1 hour). Audio files never change once uploaded — set R2 objects to
  `public, max-age=31536000, immutable` so repeat plays hit the CDN edge and
  cost nothing.
- **Don't delete the Supabase copies** until the app has shipped with R2 URLs
  and older installs have aged out — clients cache `file_url` in
  `library_items` responses.

## Licensing (unrelated to hosting, but blocking at scale)

Ellen G. White's writings are public domain (d. 1915). **Music is not.** A
worldwide SDA catalogue is largely commercially released and copyrighted;
"it's Adventist music" is not a licence. Per-track provenance — an artist
agreement, a CC licence, or a public-domain recording — is what protects the
Play Store listing. Cheap hosting makes it easier to host a lot of music,
which makes this more urgent, not less.
