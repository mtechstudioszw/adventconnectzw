/// One-shot handoff for opening the Library *at a specific item* rather than
/// just at a tab.
///
/// The `/library` route only carries an int tab index, so "Music of the day"
/// on Home could do no better than drop the member into the whole Music
/// catalogue and leave them to find the track themselves. Threading an id
/// through go_router would mean reshaping the route (and the boot gate that
/// wraps it) for one caller; this mirrors the `ChatLaunchIntent` pattern the
/// app already uses for the same problem in messaging.
///
/// Set it immediately before navigating. The receiving tab calls [takeMusic]
/// once its catalogue has loaded, which also clears it — so returning to the
/// Library later never re-triggers playback.
class LibraryLaunchIntent {
  LibraryLaunchIntent._();

  /// `library_items.id` of a track to start playing on arrival.
  static String? musicItemId;

  /// Reads and clears the pending music target.
  static String? takeMusic() {
    final id = musicItemId;
    musicItemId = null;
    return id;
  }

  static void clear() => musicItemId = null;
}
