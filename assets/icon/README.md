# Brand artwork — where to drop the new Adventist Super App logo

## The one file that matters

### `assets/icon/logo.png` — TRANSPARENT / BACKGROUNDLESS. 1024×1024 PNG.

This is the **only** file you have to replace. It is the backgroundless
mark, and it feeds BOTH the launcher icon and every in-app screen.

It **must have a transparent background**, because every screen paints
its own backdrop behind it and a baked-in white or navy square would
show up as an ugly block on all of them:

| Screen | What it paints behind the logo |
|---|---|
| `splash_screen.dart` | navy disc + animated gold ring + glow |
| `auth_screen.dart` / `auth_hero.dart` | AuthShell ambient canvas |
| `onboarding_flow_screen.dart` | blue gradient tile, gold 2px border |
| `onboarding/widgets/film_scenes.dart` | intro film ambient scene |
| `settings/about_screen.dart` | About card |
| `widgets/friend_qr_sheet.dart` | navy centre disc of the QR code |
| `widgets/verse_share_card.dart` | shared verse image |

Because the launcher icon is generated from this same file, the splash →
app hand-off stays continuous. Keep roughly **20–30% empty padding**
around the mark so Android's round/squircle masks don't clip it.

Please export it **under ~300 KB** — the current file is 2 MB, which is
pure install size for an image that never renders larger than 148 px.

## Optional second file

### `assets/icon/app_icon.png` — square store icon WITH background.

Only needed if you want the Play Store / iOS icon to look different from
the transparent mark on navy `#0D1B3E`. If you don't provide it, the
navy-plus-logo version is generated automatically and looks right.
To switch to it, point `image_path` in pubspec.yaml at this file.

## After dropping the file(s)

```
flutter pub get
dart run flutter_launcher_icons
```

That regenerates the Android launcher icon, the Android adaptive icon
(logo on `#0D1B3E`), and the iOS icon set. Every in-app screen picks the
new artwork up automatically — no code change needed.

Re-run any time you swap the artwork.

## Do NOT replace these

- `sda_logo.png` — the generic Seventh-day Adventist mark used as the
  **placeholder avatar for churches that haven't uploaded a logo**
  (`widgets/church_group_avatar.dart`). It is not our brand.
- `google.png` — the Google logo on the "Sign in with Google" button.
