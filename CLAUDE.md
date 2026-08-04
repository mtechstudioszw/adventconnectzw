\# ADVENT CONNECT ZW — CLAUDE CODE CONTEXT



\## COLOR SCHEME — NON-NEGOTIABLE

```dart

Primary Blue:   #1565C0  // Buttons, active states, highlights

Dark Navy:      #0D1B3E  // Body text, icons, dark sections. NOT headers.

White:          #FFFFFF  // Card backgrounds

Light Grey:     #F5F7FA  // Screen backgrounds

Text Dark:      #1A1A2E  // Body text

Gold Accent:    #C8A951  // Verified badge, one highlight per screen MAX

Red:            #D32F2F  // Errors and urgent content ONLY

Success Green:  #2E7D32  // Status badges ONLY

```



\*\*NEVER:\*\*

\- Use green as background

\- Use pink in any shade

\- Use any color outside this scheme



\## DESIGN RULES

\- \*\*Font:\*\* Poppins everywhere. Never substitute.

\- \*\*Buttons:\*\* Gradient primary blue, BorderRadius.circular(14)

\- \*\*Cards:\*\* White with shadow, BorderRadius.circular(16-20)

\- \*\*Screen backgrounds:\*\* Light Grey #F5F7FA

\- \*\*Headers / app bars: FLAT — never navy.\*\* (Founder rule, 2026-07-28.)

  A header shares `palette.scaffoldBg` with the page and sets its title in

  `palette.text`. Use the \*\*ScreenHero / FlatStatusBar\*\* pattern in

  `lib/widgets/screen_shell.dart` — `FlatStatusBar` flips the status-bar

  icons dark so they stay visible on the light background.

  \- `AppColors.appBarGradient` is \*\*not\*\* for headers. It survives only

    as a fill behind missing imagery (church logos, product tiles, event

    covers); converting those is a separate, deliberate call.

  \- A missing cover photo is \*\*not\*\* a reason to paint a navy slab — the

    header stays flat and the content moves up. See

    lib/screens/profile/profile\_screen.dart.

  \- \*\*Trap:\*\* a childless `DecoratedBox` in `flexibleSpace` collapses to

    zero height and paints nothing. That is how the Watch header's

    gradient vanished and left white text invisible on light grey. Use

    `Container`.

  \- Dark Navy #0D1B3E is still valid for body text, icons and dark

    sections. It is the \*header\* use that is retired.

  \- \*\*Auth flow (2026-07-29):\*\* the `AuthHero` navy slab with the curved

    bottom edge is retired. Every account screen — forgot password, reset,

    email verification, profile setup, biometric unlock — uses

    \*\*`AuthShell`\*\* (lib/screens/auth/widgets/auth\_shell.dart), which

    paints the onboarding film's own `AmbientPainter` on `scaffoldBg` so

    intro → auth is continuous, and owns the shared staggered entrance.

    Screens must NOT add their own entrance controller.

  \- \*\*Sabbath on Home (2026-07-29):\*\* also flat. The day is marked by a

    faint sundown wash, a gold horizon line on the header's bottom edge

    that stays lit all day, gold status/avatar accents and the "Happy

    Sabbath" greeting — \*\*not\*\* by a navy→gold gradient with white text.

    When flattening any navy surface, re-check every foreground that

    assumed a dark backdrop: status-bar icon brightness, white-on-frosted

    buttons and badge borders all broke silently when this one changed.

\- \*\*Uploaded images:\*\* Square via AspectRatio(1.0) — avatars, church logos,

  product and event covers. \*\*EXCEPTION (2026-07-27, founder-approved):\*\*

  home-feed POST media is full-bleed at its natural aspect ratio, clamped to

  4:5..1.91:1. Forcing 1:1 centre-cropped portrait photos through people's

  heads, and the inset frame read as a card inside a card. See

  lib/widgets/home/post\_card.dart — do not "fix" it back to square.

\- \*\*SafeArea:\*\* Every scaffold must wrap content in SafeArea (iOS notch)



\## CRITICAL TECHNICAL RULES

\- \*\*Adding a column to `profiles`, or a trigger to a shared guard? RE-READ
  THE GUARD IT DEPENDS ON.\*\* (4 Aug 2026.) Three separate production bugs
  found in one day all came from this single habit:

  \- patch\_134 added `is\_verified\_admin`; patch\_028's privilege trigger was
    never told about it → \*\*any member could grant themselves the gold
    verified tick\*\* (patch\_188).

  \- patch\_187 added a `BEFORE ... DELETE` trigger returning `NEW`; on a
    DELETE `NEW` is NULL, and returning NULL \*\*silently cancels the row\*\* →
    \*\*every delete in the app did nothing\*\* across 26 tables, with no error
    (patch\_189).

  \- whoever added `who\_can\_message` never granted SELECT on it, and
    `authenticated` has NO table-level SELECT on `profiles` — it reads
    entirely through per-column grants → \*\*the chat privacy screen had
    never loaded, for anyone\*\* (patch\_192).

  The checklist, every time you touch `profiles` or a shared trigger:

  1. Does `profiles\_block\_privilege\_self\_grant()` need to snap the new
     column back?
  2. Does the column need an explicit `GRANT SELECT` / `GRANT UPDATE`?
     There is no table-level grant to inherit from. \*\*`fcm\_token` must
     STAY unreadable\*\* — never "fix" a missing grant by granting the table.
  3. A column-level `REVOKE` is \*\*silently ignored\*\* while a table-level
     grant exists. Revoke the table first.
  4. `BEFORE` triggers covering DELETE must `RETURN COALESCE(NEW, OLD)`.

\- \*\*`CacheService.writePref` does NOT add the `pref:` prefix for you.\*\* The
  key must literally start with `pref:`, or `clearUserData()` deletes it on
  every sign-out. This has already broken the quiz sound settings and the
  offline-downloads index. Decide per key: device-level → `pref:`;
  user-scoped → leave unprefixed so sign-out clears it.

\- \*\*Auth tokens:\*\* ALWAYS use flutter\_secure\_storage — NEVER SharedPreferences

\- \*\*Supabase region:\*\* Africa (Cape Town) — already set, never change

\- \*\*Dependency versions:\*\* Use EXACT versions from pubspec.yaml — NEVER "latest"

\- \*\*firebase\_auth:\*\* PERMANENTLY EXCLUDED — Supabase handles all auth

\- \*\*Platform checks:\*\* flutter\_windowmanager is Android-only — wrap in Platform.isAndroid



\## FILE STRUCTURE

