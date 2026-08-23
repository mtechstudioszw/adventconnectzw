/// Ask an avatar host for the size we are actually going to draw.
///
/// ## The bug this exists for
///
/// Google hands us an avatar URL ending `=s96-c`, and that suffix is not
/// decoration — it is the render size. Every Google-signup member in this
/// database is stored as a **96×96 pixel image**:
///
///     https://lh3.googleusercontent.com/a/ACg8ocL...=s96-c
///
/// Drawn in the profile screen's 118px circle it is already being upscaled;
/// opened in [FullImageViewer] on a 1080p phone it is a 96px image stretched
/// across the screen. That is the "the Google picture is far away and won't
/// zoom, it's different from one I uploaded myself" report (23 Aug 2026) —
/// an uploaded photo is stored at full resolution, so it has detail to give
/// and this one never did.
///
/// Google will serve any size from the same URL, so none of this needs a
/// re-upload or a migration: we simply stop asking for the thumbnail.
///
/// Anything that is not a recognised size-parameterised host is returned
/// untouched, so this is safe to call on every URL in the app.
library;

/// Rewrite [url] to request roughly [px] logical pixels.
///
/// Pass the size you will DRAW at, not the source size. Callers should
/// already have multiplied by the device pixel ratio where it matters —
/// see [CachedImage], which does it for every avatar in the app.
String photoUrlAtSize(String? url, int px) {
  final raw = (url ?? '').trim();
  if (raw.isEmpty) return raw;
  // Clamp: below 96 there is nothing to gain over what Google already sent,
  // and above 1024 we are downloading more than any screen here can show.
  //
  // The clamp also absorbs a nonsense request rather than propagating it.
  // The caller is responsible for not handing us the result of
  // `(double.infinity * dpr).round()` — that throws before it ever reaches
  // this function — but a caller that computes 0, or something absurd from
  // a collapsed layout, gets a usable size instead of a broken URL.
  final size = px.clamp(96, 1024);

  // Google (lh3.googleusercontent.com, plus the lh4/lh5/… shards).
  //
  // Two forms exist in the wild:
  //   .../ACg8ocL...=s96-c        — the modern one, and the only one this
  //                                 database contains
  //   .../s96-c/photo.jpg         — the older path segment form
  if (raw.contains('googleusercontent.com')) {
    // `=s96-c`, `=s96`, `=s96-c-k-no`, … — replace just the sNNN token and
    // keep whatever modifiers follow it (`-c` is the centre-crop we want).
    final eq = RegExp(r'=s\d+(-[a-z0-9-]+)?$');
    if (eq.hasMatch(raw)) {
      return raw.replaceFirstMapped(
        eq,
        (m) => '=s$size${m.group(1) ?? ''}',
      );
    }
    // Path-segment form.
    final seg = RegExp(r'/s\d+(-[a-z0-9-]+)?/');
    if (seg.hasMatch(raw)) {
      return raw.replaceFirstMapped(
        seg,
        (m) => '/s$size${m.group(1) ?? ''}/',
      );
    }
    // A Google URL with no size token at all serves its default. Appending
    // one is still correct and is what the `=s` form expects.
    if (!raw.contains('=')) return '$raw=s$size-c';
    return raw;
  }

  return raw;
}
