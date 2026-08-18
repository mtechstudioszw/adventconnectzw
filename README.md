# Adventist Super App

Connecting SDA people around the globe.

An independent, all-in-one community platform for Seventh-day Adventists
worldwide: a social feed and stories, church directory, events, prayer
requests, messaging, a marketplace and job board, a Bible + Sabbath School
+ hymnal + EGW library that works offline, Watch, and a Bible quiz arena.

Not an official Seventh-day Adventist Church product. Not affiliated with,
endorsed by or operated by the General Conference, any division, union or
local conference.

## Naming

The app was launched as **Advent Connect ZW** and rebranded to **Adventist
Super App** in August 2026. The rebrand was deliberately public-facing only —
the following are the app's technical identity and are unchanged:

| Identifier | Value |
|---|---|
| Android application ID | `io.supabase.adventconnectzw.advent_connect_zw` |
| Dart package name | `advent_connect_zw` |
| Deep-link scheme | `io.supabase.adventconnect://` |
| FCM default channel | `advent_connect_zw_default` |
| Share worker | `advent-share.adventconnectzw.workers.dev` |
| Published legal URLs | `mtechstudioszw.github.io/adventconnect-legal/` |

Renaming any of them would break existing installs, Play Billing, push
notifications, or links already shared in the wild. Leave them alone.

## Getting started

```
flutter pub get
flutter run
```

See [CLAUDE.md](CLAUDE.md) for the colour scheme, design rules and the
critical technical rules (Supabase grants, `pref:` keys, secure storage).

Brand artwork lives in [assets/icon/](assets/icon/) — see its README before
replacing anything.

## Built by

Tanatswa Michael Mikuwa — adventconnectzw@gmail.com — +263 778 092 494
