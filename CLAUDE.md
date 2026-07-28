\# ADVENT CONNECT ZW — CLAUDE CODE CONTEXT



\## COLOR SCHEME — NON-NEGOTIABLE

```dart

Primary Blue:   #1565C0  // Buttons, active states, highlights

Dark Navy:      #0D1B3E  // Headers, app bar, dark sections

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

\- \*\*Uploaded images:\*\* Square via AspectRatio(1.0) — avatars, church logos,

  product and event covers. \*\*EXCEPTION (2026-07-27, founder-approved):\*\*

  home-feed POST media is full-bleed at its natural aspect ratio, clamped to

  4:5..1.91:1. Forcing 1:1 centre-cropped portrait photos through people's

  heads, and the inset frame read as a card inside a card. See

  lib/widgets/home/post\_card.dart — do not "fix" it back to square.

\- \*\*SafeArea:\*\* Every scaffold must wrap content in SafeArea (iOS notch)



\## CRITICAL TECHNICAL RULES

\- \*\*Auth tokens:\*\* ALWAYS use flutter\_secure\_storage — NEVER SharedPreferences

\- \*\*Supabase region:\*\* Africa (Cape Town) — already set, never change

\- \*\*Dependency versions:\*\* Use EXACT versions from pubspec.yaml — NEVER "latest"

\- \*\*firebase\_auth:\*\* PERMANENTLY EXCLUDED — Supabase handles all auth

\- \*\*Platform checks:\*\* flutter\_windowmanager is Android-only — wrap in Platform.isAndroid



\## FILE STRUCTURE

