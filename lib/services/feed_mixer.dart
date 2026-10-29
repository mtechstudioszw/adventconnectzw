/// What kind of block a feed position holds.
enum FeedBlockKind {
  post,

  /// A one-off module (events, prayers, Market, invite…) from Home's
  /// existing discovery list — each shown once.
  discovery,

  // Recurring modules — each comes back with NEW items until its source
  // runs dry.
  people,

  /// Members who turned followers on (patch_287), offered with Follow.
  leaders,
  news,
  video,
  verse,
  quiz,
  hymn,
  belief,
  church,
  music,

  ad,

  /// "You're up to date on your people" — between the last post and the
  /// endless "more to explore" part.
  caughtUp,
}

/// One position in the feed: a kind and the index of the item within that
/// kind's own source (post 3, people group 2, news story 5…).
class FeedBlock {
  const FeedBlock(this.kind, this.index);
  final FeedBlockKind kind;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is FeedBlock && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);

  @override
  String toString() => '${kind.name}#$index';
}

/// Lays out Home's feed (owner, 29 Oct 2026: "things shouldn't only show
/// once or twice … it should become endless").
///
/// Posts lead, in their ranked order. After every few posts the next
/// recurring module joins from [rotation] — a people group, a news story,
/// a sermon, a verse, a quiz question… — and each module draws only items
/// it has not shown yet, so nothing repeats. One-off discovery modules are
/// woven in between. When the posts run out the feed says so once, then
/// keeps going with [extraModules] more blocks; Home raises that number as
/// the member nears the bottom, so the feed only ends when every source is
/// genuinely empty.
///
/// Pure and deterministic: the same inputs always give the same layout,
/// so a rebuild never reshuffles what is already on screen.
class FeedMixer {
  FeedMixer._();

  /// The order recurring modules take turns in. People come round most
  /// often — there are hundreds of members to meet and they are the point
  /// of a church network; Scripture keeps the feed devotional.
  static const rotation = <FeedBlockKind>[
    FeedBlockKind.people,
    FeedBlockKind.news,
    FeedBlockKind.video,
    FeedBlockKind.leaders,
    FeedBlockKind.verse,
    FeedBlockKind.people,
    FeedBlockKind.quiz,
    FeedBlockKind.news,
    FeedBlockKind.hymn,
    FeedBlockKind.video,
    FeedBlockKind.church,
    FeedBlockKind.people,
    FeedBlockKind.belief,
    FeedBlockKind.music,
  ];

  /// [posts]: how many posts are loaded. [discovery]: how many one-off
  /// modules exist. [available]: how many items each recurring kind can
  /// still give (people = groups, not people). [postsExhausted]: the server
  /// has no older posts. [extraModules]: blocks to add after the posts.
  /// [adAfterPost]: where the single ad slot goes (null = none).
  static List<FeedBlock> mix({
    required int posts,
    int discovery = 0,
    Map<FeedBlockKind, int> available = const {},
    bool postsExhausted = false,
    int extraModules = 0,
    int postsBetween = 3,
    int? adAfterPost,
  }) {
    final out = <FeedBlock>[];
    final used = <FeedBlockKind, int>{};
    var turn = 0;
    var discoveryUsed = 0;
    var moduleCount = 0;

    FeedBlock? nextRecurring() {
      for (var tries = 0; tries < rotation.length; tries++) {
        final kind = rotation[turn % rotation.length];
        turn++;
        final have = available[kind] ?? 0;
        final n = used[kind] ?? 0;
        if (n < have) {
          used[kind] = n + 1;
          return FeedBlock(kind, n);
        }
      }
      return null;
    }

    // Alternate: recurring, one-off, recurring, one-off… so the one-off
    // modules spread through the first screens instead of bunching.
    FeedBlock? nextModule() {
      final wantDiscovery = moduleCount.isOdd && discoveryUsed < discovery;
      moduleCount++;
      if (wantDiscovery) {
        return FeedBlock(FeedBlockKind.discovery, discoveryUsed++);
      }
      final r = nextRecurring();
      if (r != null) return r;
      if (discoveryUsed < discovery) {
        return FeedBlock(FeedBlockKind.discovery, discoveryUsed++);
      }
      return null;
    }

    for (var i = 0; i < posts; i++) {
      out.add(FeedBlock(FeedBlockKind.post, i));
      if (adAfterPost != null && i + 1 == adAfterPost) {
        out.add(const FeedBlock(FeedBlockKind.ad, 0));
      }
      if ((i + 1) % postsBetween == 0) {
        final m = nextModule();
        if (m != null) out.add(m);
      }
    }

    if (!postsExhausted) return out;

    if (posts > 0) out.add(const FeedBlock(FeedBlockKind.caughtUp, 0));
    for (var k = 0; k < extraModules; k++) {
      final m = nextModule();
      if (m == null) break;
      out.add(m);
    }
    return out;
  }

  /// True when [mix] could still add another block after [extraModules] —
  /// i.e. scrolling further is worth it.
  static bool hasMore({
    required int posts,
    int discovery = 0,
    Map<FeedBlockKind, int> available = const {},
    int extraModules = 0,
    int postsBetween = 3,
  }) {
    final now = mix(
      posts: posts,
      discovery: discovery,
      available: available,
      postsExhausted: true,
      extraModules: extraModules,
      postsBetween: postsBetween,
    );
    final next = mix(
      posts: posts,
      discovery: discovery,
      available: available,
      postsExhausted: true,
      extraModules: extraModules + 1,
      postsBetween: postsBetween,
    );
    return next.length > now.length;
  }
}
