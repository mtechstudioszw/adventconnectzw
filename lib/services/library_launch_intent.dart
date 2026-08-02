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
/// Set the field immediately before navigating. The receiving tab calls the
/// matching `take…` once its catalogue has loaded, which also clears it — so
/// returning to the Library later never re-triggers the jump.
///
/// Music was the only target for a while. The founder reported (2 Aug 2026)
/// that the other Today cards had the same fault: the card names a hymn, a
/// lesson or a book, and tapping it opened the shelf rather than the thing.
/// Each card now carries its target's id here.
class LibraryLaunchIntent {
  LibraryLaunchIntent._();

  /// `library_items.id` of a track to start playing on arrival.
  static String? musicItemId;

  /// `library_items.id` of an EGW book to open on arrival.
  static String? egwItemId;

  /// `Hymn.id` of a hymn to open in the reader on arrival.
  ///
  /// The id rather than the hymnal number: `Hymn.number` is nullable, so
  /// matching on it would silently miss for any hymn without one.
  static String? hymnId;

  /// `Quarterly.id` whose lesson list to open on arrival.
  ///
  /// The card shows a quarterly, so the exact thing behind it is that
  /// quarterly's lessons — not the Sabbath School shelf, and not a
  /// specific week the member never chose.
  static String? quarterlyId;

  /// Reads and clears the pending music target.
  static String? takeMusic() {
    final id = musicItemId;
    musicItemId = null;
    return id;
  }

  /// Reads and clears the pending EGW target.
  static String? takeEgw() {
    final id = egwItemId;
    egwItemId = null;
    return id;
  }

  /// Reads and clears the pending hymn target.
  static String? takeHymn() {
    final id = hymnId;
    hymnId = null;
    return id;
  }

  /// Reads and clears the pending Sabbath School target.
  static String? takeQuarterly() {
    final id = quarterlyId;
    quarterlyId = null;
    return id;
  }

  static void clear() {
    musicItemId = null;
    egwItemId = null;
    hymnId = null;
    quarterlyId = null;
  }
}
