-- ============================================================================
--  patch_271 — readable titles for the uploaded music tracks
--  STATUS: APPLIED to the live database 28 Oct 2026.
-- ============================================================================
--
--  Seen on the founder's phone, 28 Oct 2026: the Music shelf shows raw file
--  names ("Love_at_Home_-_SDA_Hymn_#_652(0)"). Bulk upload used the file
--  name as the title; the uploader now cleans it (lib/utils/upload_title.dart),
--  but the 11 rows already uploaded need fixing by hand.
--
--  Ids and current titles read from the live DB (read-only) on 28 Oct 2026.
--  Each UPDATE matches on id AND the current title, so a row someone has
--  already renamed is left alone.
--
--  Not decided here (owner): id 102 and id 108 are the same hymn
--  ("Joy By and By", #430). Unpublish one with the commented line below.
-- ============================================================================

BEGIN;

UPDATE public.library_items SET title = 'Love at Home (SDA Hymnal 652)'
 WHERE id = 110 AND title = 'Love_at_Home_-_SDA_Hymn_#_652(0)';
UPDATE public.library_items SET title = 'Live Out Thy Life Within Me (SDA Hymnal 316)'
 WHERE id = 109 AND title = 'Live_Out_Thy_Life_Within_Me_-_SDA_Hymn_#_316(0)(1)';
UPDATE public.library_items SET title = 'Joy By and By (SDA Hymnal 430) — Breath of Praise'
 WHERE id = 108 AND title = 'Joy_By_and_By____SDA_HYMN_#430____Breath_of_Praise(256k)';
UPDATE public.library_items SET title = 'In a Little While We''re Going Home (SDA Hymnal 626)'
 WHERE id = 107 AND title = 'In_a_Little_While_We_re_Going_Home___SDA_hymn_#_626(0)';
UPDATE public.library_items SET title = 'I Will Sing of Jesus'' Love (SDA Hymnal 183)'
 WHERE id = 106 AND title = 'I_will_sing_of_Jesus_Love_SDA_Hymn_#_183(0)';
UPDATE public.library_items SET title = 'Holy, Holy, Holy (SDA Hymnal 73)'
 WHERE id = 105 AND title = 'Holy,_Holy,_Holy_-_SDA_Hymn_#_73(0)';
UPDATE public.library_items SET title = 'All the Way (SDA Hymnal 516)'
 WHERE id = 104 AND title = 'All_the_way_SDA_Hymn_#_516(0)';
UPDATE public.library_items SET title = 'A Shelter in the Time of Storm (SDA Hymnal 528)'
 WHERE id = 103 AND title = 'A_Shelter_in_the_Time_of_Storm___SDA_Hymn_#_528(0)';
UPDATE public.library_items SET title = 'Joy By and By (SDA Hymnal 430)'
 WHERE id = 102 AND title = 'Joy_By_and_By____SDA_HYMN_#430';
UPDATE public.library_items SET title = 'Come, Thou Fount'
 WHERE id = 101 AND title = 'Come_Thou_Fount Song';
UPDATE public.library_items SET title = 'Jesus, Keep Me Near the Cross'
 WHERE id = 99 AND title = 'Jesus Keep Me Near The Cross Song';

-- Duplicate (owner's choice — uncomment to hide the plain copy):
-- UPDATE public.library_items SET is_published = false WHERE id = 102;

COMMIT;

-- Check:
--   SELECT id, title FROM public.library_items WHERE kind = 'music' ORDER BY id;
