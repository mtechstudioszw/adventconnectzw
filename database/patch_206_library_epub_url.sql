-- patch_206 — an EPUB alongside the PDF for Library books.
--
-- WHY
-- The EGW shelf is PDFs, and `flutter_pdfview` renders PAGE IMAGES with no
-- text layer. That made "remove the pdf feel" (founder, 17 Aug) impossible
-- rather than merely hard: with no text there is nothing to reflow, nothing
-- to select, nothing to highlight, and no way to share a quote.
--
-- The same books ship as EPUB from the same White Estate server, and those
-- carry clean XHTML, the CANONICAL printed page numbers inline as
--   <span epub:type="pagebreak" title="18">
-- and scripture pre-tagged as
--   <span class="bible-kjv" title="Colossians 2:3">
-- which is what lets a shared quote be cited as "Steps to Christ, p. 18"
-- and lets a reference link into the app's own Bible tab.
--
-- ADDITIVE AND REVERSIBLE. `file_url` is untouched, so every existing
-- reader keeps working; the app falls back to the PDF whenever `epub_url`
-- is null. Dropping this column restores the previous behaviour exactly.

alter table public.library_items
  add column if not exists epub_url text;

comment on column public.library_items.epub_url is
  'Reflowable EPUB in the `library` bucket. NULL means the app falls back '
  'to file_url (the PDF). Only egw_book rows are expected to have one.';

-- Backfill from the PDF path, which is `egw_book/en_<CODE>.pdf` for every
-- book seeded by egw-seed. Guarded on the actual filename rather than
-- assumed: the two originally-uploaded books (The Great Controversy and
-- Steps to Christ) have timestamped filenames instead and are handled
-- separately below.
update public.library_items
   set epub_url = regexp_replace(file_url, '\.pdf$', '.epub')
 where kind = 'egw_book'
   and file_url ~ '/en_[A-Za-z0-9]+\.pdf$'
   and epub_url is null;

-- The two originals, matched on title because their filenames carry an
-- upload timestamp rather than the book code.
update public.library_items
   set epub_url = 'https://eqbyvasteolqyktbqbem.supabase.co/storage/v1/'
                  || 'object/public/library/egw_book/en_GC.epub'
 where kind = 'egw_book' and title = 'The Great Controversy'
   and epub_url is null;

update public.library_items
   set epub_url = 'https://eqbyvasteolqyktbqbem.supabase.co/storage/v1/'
                  || 'object/public/library/egw_book/en_SC.epub'
 where kind = 'egw_book' and title = 'Steps to Christ'
   and epub_url is null;

-- Sanity: every EGW book should now point at an EPUB.
--   select count(*) filter (where epub_url is null) as missing
--     from public.library_items where kind = 'egw_book';
