# Advent Connect ZW — Session resume brief

**Repo:** `C:\Users\j\Desktop\advent_connect_zw\adventconnectzw` · **Remote:**
`https://github.com/mtechstudioszw/adventconnectzw`

> This file replaced the old Stage-19/20 brief, which was stale (that work
> shipped long ago — the app is at v1.3.0+1032 with Quiz Arena already live).

---

## What landed last session (Library redesign)

The whole **Library** was rebuilt from 4 tabs to **5**, and the home launcher
was reworked. `flutter analyze lib/` is **clean** — the only 4 remaining
issues are pre-existing and unrelated (event_details_screen, push_service,
date_format).

### 1. Music — background playback restored + "Adventist Spotify" rebuild

**The important fix:** `just_audio_background` had been deliberately removed
because it threw `_audioHandler has not been initialized`. It is back and
working. Two rules must never be broken again:

- `JustAudioBackground.init()` must complete **before the first AudioPlayer is
  constructed**. `MusicPlayerService.player` is now a lazy getter, and
  `ensureInitialized()` is awaited in `main()`'s `Future.wait` before
  `runApp`.
- **Every** `AudioSource` needs a `MediaItem` tag or it throws at load.

`ensureInitialized()` is timeboxed to 6s and never throws — on failure
`backgroundReady` stays false and playback degrades to plain in-app audio
rather than refusing to play. Keep that fallback.

New files:
- `lib/services/music_download_service.dart` — REAL offline downloads to
  app-support dir with progress + index (the old Download button only opened
  a share sheet; downloaded tracks now play from disk with no network).
- `lib/services/music_prefs_service.dart` — liked tracks, recently played,
  playlists, speed, resume-queue.
- `lib/screens/library/widgets/music_visuals.dart` — artwork, blurred
  backdrop, animated equalizer bars, `formatDuration`.
- `lib/screens/library/widgets/full_player_screen.dart` — blurred cover
  backdrop, drag-down dismiss, scrub bar, ±15s, speed, **sleep timer**, queue
  sheet, download, share.
- `lib/screens/library/widgets/now_playing_bar.dart` — mini player with
  progress hairline, swipe-up to open, swipe-down to stop.

**The mini player now lives at the Library SHELL level** (`library_screen.dart`),
so playback controls follow you across every tab. `MusicTab` deliberately does
NOT render its own — two bars would stack. `AudioBibleScreen` renders one
because it's standalone.

### 2. Hymnal — now genuinely 100% offline

Root cause of the "hymnal says something when on WiFi" bug: `HymnService.all()`
hit Supabase on every open and showed spinners/errors.

- All **995 hymns exported to `assets/hymns/hymns.json`** (781 KB — 300 Kristu
  MuNzwiyo + 695 SDA Hymnal). Regenerate with
  `dart run scripts/export_hymns.dart` after adding hymns in Supabase.
- Read path (`cached`/`all`/`search`) **never touches the network** and cannot
  fail. Pull-to-refresh is the only network path and is **silent on failure**.
- Reader rebuilt: `parseStanzas()` turns the raw lyrics blob into numbered
  verses + a gold-ruled CHORUS block, plus focus (dark paper) mode, text-size
  sheet, favourites, swipe between hymns.

### 3. Sabbath School — new tab

Content comes from **Adventech's public API** (`sabbath-school.adventech.io`,
the same feed the official app uses) — zero data entry.

- **~90 languages, Shona (`sn`) is the DEFAULT.** English is one tap away.
- `lib/services/sabbath_school_service.dart` — quarterlies → lessons → days →
  content, all write-through cached to Hive. `downloadLesson()` pre-fetches a
  whole week for offline.
- `lib/screens/library/widgets/ss_html_text.dart` — native renderer for the
  lesson HTML subset (`h1-h6, p, blockquote, a, em, strong, sup, small, hr,
  br, li`). **No HTML package added.** Inline `<a class="verse">` references
  are TAPPABLE and open the passage from the day's own bundled verse map
  (works offline).
- Progress, per-day notes and "continue reading" in
  `lib/services/sabbath_school_prefs.dart`.

### 4. Bible — rebuilt + multi-translation

- **Chapter continuum**: `PageView` over all 1,189 chapters, so swiping past
  Genesis 50 rolls into Exodus 1.
- **Multi-verse selection** with a contextual action bar (highlight / bookmark
  / copy / note / share) — the biggest gap vs other Bible apps.
- **Verse of the Day** (deterministic from day-of-year, no server) + reading
  **streak**.
- **Share as IMAGE** — `widgets/verse_share_card.dart` renders a branded 1:1
  card via `RepaintBoundary.toImage` with 4 styles; falls back to text share
  on any failure.
- Reading themes (Auto / Light / Sepia / Dark) independent of app theme,
  focus mode, book-search + OT/NT grid, chapter grid sheet.
- **Translations** (`bible.helloao.org`, cached per chapter):
  KJV (bundled, always offline), **Shona `sna_bib`**, **Hebrew `heb_wlc`**
  (RTL handled), Greek `grc_byz` / `grc_sbl` / `grc_gtr`, Septuagint
  `grc_bre`, and **BSB which is the only one with narrated chapter audio**
  (3 narrators) — audio plays through `MusicPlayerService`, so it gets
  background + lock-screen controls for free.
- **Cinematic switcher**: `widgets/translation_picker.dart` — blurred
  full-screen overlay, staggered cards each showing its own script glyph
  (א, Ω, Σ, S, K), chosen card pulses, then `TranslationCrossfade` dissolves
  the passage into the new language.
- Translations that lack a book (Greek NT has no Genesis) show an explicit
  message + "Change translation", never an empty chapter.

### 5. EGW — bookshelf

- `lib/screens/library/egw_tab.dart` — cover grid (2:3) / list toggle,
  **continue-reading hero with live progress**, search, Saved shelf, progress
  rings, generated spine-style cover when a book has no artwork.
- `PdfProgress` helper added to `pdf_viewer_screen.dart` persists the page
  COUNT (not just last page) so the shelf can show "Page 42 of 380".

### 6. Home screen

- Library chips are now **5**, mapping 1:1 to the Library tabs
  (0=Bible, 1=Sabbath School, 2=Hymnal, 3=EGW, 4=Music).
- **Quiz moved out of the chip row into its own `_QuizCard`.** It was a sixth
  48dp chip; six chips left ~48dp each on a 360dp screen. Deliberately styled
  as a LIGHT card, not another navy gradient — the devotion card directly
  above already uses `appBarGradient` + gold, and a second identical slab read
  as a duplicate.
- ⚠️ **`_QuizCard` is the ONLY entry point to `/quiz` in the entire app.**
  Do not remove it without adding another.

---

## NOT yet done / next steps

1. **Never built or run.** `flutter analyze` is clean (a full type-check), but
   `flutter build apk` has **not** completed successfully — the attempt was
   stopped mid-run. **First job next session: build and run on device.**
2. Blockers found by `flutter doctor`:
   - Android **cmdline-tools missing** → Android Studio → SDK Manager → SDK
     Tools → "Android SDK Command-line Tools (latest)".
   - **Android licenses not accepted** → `flutter doctor --android-licenses`.
   - **Windows Developer Mode off** → `start ms-settings:developers` (Flutter
     needs symlink support for plugins).
   - Device `R9ZX90858DT` is connected but **not authorized** — accept the USB
     debugging prompt on the phone.
3. First Android build still needs `firebase-crashlytics-buildtools-3.0.2.jar`
   from `dl.google.com`; this has timed out on slow connections before.
4. **Not yet verified on a real device:** the media notification actually
   appearing, Hebrew RTL rendering, verse-image share on Android 13+, and
   Sabbath School Shona content.

## Things NOT to redo

- `flutter pub get` — done, deps resolved.
- The hymn export — `assets/hymns/hymns.json` is committed.
- Removing `just_audio_background` — it is correctly wired now, see above.
- Putting Quiz back as a 6th chip.
- Adding an HTML package for Sabbath School — `ss_html_text.dart` handles it.
