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

\- \*\*App bar:\*\* Dark Navy #0D1B3E with gradient

\- \*\*All uploaded images:\*\* Square via AspectRatio(1.0)

\- \*\*SafeArea:\*\* Every scaffold must wrap content in SafeArea (iOS notch)



\## CRITICAL TECHNICAL RULES

\- \*\*Auth tokens:\*\* ALWAYS use flutter\_secure\_storage — NEVER SharedPreferences

\- \*\*Supabase region:\*\* Africa (Cape Town) — already set, never change

\- \*\*Dependency versions:\*\* Use EXACT versions from pubspec.yaml — NEVER "latest"

\- \*\*firebase\_auth:\*\* PERMANENTLY EXCLUDED — Supabase handles all auth

\- \*\*Platform checks:\*\* flutter\_windowmanager is Android-only — wrap in Platform.isAndroid



\## FILE STRUCTURE

