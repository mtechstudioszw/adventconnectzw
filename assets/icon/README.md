# Launcher icon source files

Drop two PNGs here before running `dart run flutter_launcher_icons`:

- `app_icon.png` — 1024×1024 transparent (or solid) source. Used for
  iOS and the non-adaptive Android icon. **Required.**
- `app_icon_foreground.png` — 1024×1024 transparent foreground. The
  inner logo gets placed on top of the navy adaptive background
  (`#0D1B3E`) per CLAUDE.md. Keep ~30% safe-zone padding so it isn't
  clipped on round masks. **Required for Android 8+ adaptive icons.**

After dropping both files:

```
flutter pub get
dart run flutter_launcher_icons
```

Re-run any time you swap the artwork.
