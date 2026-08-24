/// The iPhone fundraiser, as the server describes it.
///
/// Mirrors one row of `public.fundraiser_status()` (patch_253). Every
/// number here is produced server-side from CONFIRMED contributions only —
/// nothing in this file is client-authored, and nothing in the app is
/// allowed to write back to it. See the patch header for why.
library;

/// Where the campaign is. The server decides this, including flipping to
/// [completed] on its own once the goal is met.
enum FundraiserState {
  /// Asking for support.
  active,

  /// Deliberately switched off by the founder. The card hides entirely —
  /// this is not a state members should have to reason about.
  paused,

  /// Funded, or closed by hand. The card stops asking and says thank you.
  completed,
}

class FundraiserCampaign {
  const FundraiserCampaign({
    required this.campaignKey,
    required this.state,
    required this.goalCents,
    required this.raisedCents,
    required this.remainingCents,
    required this.currency,
    required this.amountsCents,
    required this.supporters,
    required this.dismissed,
    required this.myPending,
    required this.title,
    required this.body,
  });

  /// Version token for the campaign. Dismissals and contributions are
  /// keyed by it, so starting a new campaign does not inherit the last
  /// one's opt-outs.
  final String campaignKey;

  final FundraiserState state;

  /// The goal, in cents. Configurable in `app_config.fundraiser_goal_cents`
  /// — deliberately NOT a constant anywhere in the Flutter code, so a new
  /// target is a dashboard edit rather than a release.
  final int goalCents;

  /// Confirmed contributions only.
  final int raisedCents;
  final int remainingCents;

  /// ISO currency code, e.g. `USD`.
  final String currency;

  /// The suggested chips on the contribution screen, in cents.
  final List<int> amountsCents;

  /// How many people have given so far.
  final int supporters;

  /// Whether THIS member closed the card. Stored against the account, so
  /// it follows them to a new phone.
  final bool dismissed;

  /// How many of this member's own pledges are still awaiting confirmation.
  /// Used only to reassure them that their note was received.
  final int myPending;

  /// The card's heading, from `fundraiser_campaigns.title` (patch_255).
  ///
  /// Server-side rather than a Dart literal because the campaign is data:
  /// the second campaign is a form in the console, not a release. Falls
  /// back to the iPhone wording if the row or the column is missing, so an
  /// app talking to a pre-255 database still renders the right card.
  final String title;

  /// The card's sentence. The server has already substituted the goal into
  /// it, so `{goal}` never reaches the UI and the client is not assembling
  /// a sentence out of a number and a currency it might format differently
  /// from the way the campaign was written.
  final String body;

  /// 0.0 – 1.0. Clamped, because a campaign that overshoots its goal must
  /// not paint a bar past the end of its track.
  double get progress {
    if (goalCents <= 0) return 0;
    return (raisedCents / goalCents).clamp(0.0, 1.0);
  }

  /// Whole percent, for the label next to the bar.
  int get percent => (progress * 100).round();

  bool get isActive => state == FundraiserState.active;
  bool get isCompleted => state == FundraiserState.completed;

  /// Whether the card may appear on the home feed at all.
  ///
  /// Paused hides it. Dismissed hides it. A completed campaign still shows
  /// once — the thank-you — because the people who gave deserve to see it
  /// land, and it is the only state that never asks for anything.
  bool get canShowCard {
    if (dismissed) return false;
    switch (state) {
      case FundraiserState.paused:
        return false;
      case FundraiserState.active:
      case FundraiserState.completed:
        return true;
    }
  }

  static FundraiserState _stateFrom(Object? raw) {
    switch ((raw ?? '').toString()) {
      case 'completed':
        return FundraiserState.completed;
      case 'paused':
        return FundraiserState.paused;
      default:
        // Anything unrecognised reads as active rather than throwing. A
        // typo in one config row must never be able to break the home
        // screen.
        return FundraiserState.active;
    }
  }

  /// Parse the comma-separated cents list from config, defensively: a
  /// stray space, a trailing comma or a non-number must not produce an
  /// empty chip row on the contribution screen.
  static List<int> _amountsFrom(Object? raw) {
    final parsed = <int>[];
    for (final part in (raw ?? '').toString().split(',')) {
      final n = int.tryParse(part.trim());
      if (n != null && n > 0) parsed.add(n);
    }
    if (parsed.isEmpty) return const [100, 300, 500, 1000];
    parsed.sort();
    return parsed;
  }

  /// Turn a typed dollar amount into cents.
  ///
  /// Accepts "5", "5.50", " 5,50 " — a comma is a decimal separator in
  /// plenty of the places this app runs, and someone typing it should not
  /// be told their money is invalid. Returns null for anything that is not
  /// a positive number, because this feeds a real database write and a
  /// permissive parse here is a data problem later.
  static int? parseAmountToCents(String raw) {
    final text =
        raw.trim().replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    if (text.isEmpty) return null;
    // Two dots is a typo, not a number. double.tryParse would return null
    // anyway; this is here so the intent is on the page.
    final value = double.tryParse(text);
    if (value == null || value <= 0 || !value.isFinite) return null;
    return (value * 100).round();
  }

  /// What the card said before patch_255 made the copy data. Kept as the
  /// fallback, so a build newer than the database — or a campaign row that
  /// somehow lost its text — still shows a complete, correct card rather
  /// than an empty heading.
  static const String fallbackTitle = 'Help us reach iPhone';

  static String _fallbackBody(String goalLabel) =>
      'Adventist Super App is on Android today. We are raising $goalLabel '
      'for the Apple Developer fee so we can publish it for iPhone users '
      'too.';

  static String _textFrom(Object? raw, String fallback) {
    final text = (raw ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static int _intFrom(Object? raw, {int fallback = 0}) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse((raw ?? '').toString()) ?? fallback;
  }

  factory FundraiserCampaign.fromJson(Map<String, dynamic> json) {
    final goal = _intFrom(json['goal_cents'], fallback: 9900);
    final raised = _intFrom(json['raised_cents']);
    return FundraiserCampaign(
      campaignKey: (json['campaign_key'] ?? '').toString(),
      state: _stateFrom(json['status']),
      goalCents: goal <= 0 ? 9900 : goal,
      raisedCents: raised < 0 ? 0 : raised,
      remainingCents: _intFrom(
        json['remaining_cents'],
        fallback: (goal - raised).clamp(0, goal),
      ),
      currency: (json['currency'] ?? 'USD').toString(),
      amountsCents: _amountsFrom(json['amounts_cents']),
      supporters: _intFrom(json['supporters']),
      dismissed: json['dismissed'] == true,
      myPending: _intFrom(json['my_pending']),
      title: _textFrom(json['title'], fallbackTitle),
      // The fallback needs the goal formatted, which needs the currency,
      // which is only known here — hence building it inline rather than as
      // a const.
      body: _textFrom(
        json['body'],
        _fallbackBody(FundraiserCampaign(
          campaignKey: '',
          state: FundraiserState.active,
          goalCents: goal <= 0 ? 9900 : goal,
          raisedCents: 0,
          remainingCents: 0,
          currency: (json['currency'] ?? 'USD').toString(),
          amountsCents: const [],
          supporters: 0,
          dismissed: false,
          myPending: 0,
          title: '',
          body: '',
        ).goalLabel),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'campaign_key': campaignKey,
        'status': state.name,
        'goal_cents': goalCents,
        'raised_cents': raisedCents,
        'remaining_cents': remainingCents,
        'currency': currency,
        'amounts_cents': amountsCents.join(','),
        'supporters': supporters,
        'dismissed': dismissed,
        'my_pending': myPending,
        'title': title,
        'body': body,
      };

  FundraiserCampaign copyWith({bool? dismissed, int? myPending}) =>
      FundraiserCampaign(
        campaignKey: campaignKey,
        state: state,
        goalCents: goalCents,
        raisedCents: raisedCents,
        remainingCents: remainingCents,
        currency: currency,
        amountsCents: amountsCents,
        supporters: supporters,
        dismissed: dismissed ?? this.dismissed,
        myPending: myPending ?? this.myPending,
        title: title,
        body: body,
      );

  /// Money, the way a member would write it: `$99`, `$1`, `$2.50`.
  ///
  /// Whole amounts drop the `.00` deliberately — "$42 of $99" reads as a
  /// sentence, "$42.00 of $99.00" reads as an invoice, and this card is
  /// meant to be the former.
  String formatCents(int cents) {
    final symbol = currencySymbol;
    final whole = cents ~/ 100;
    final fraction = cents % 100;
    if (fraction == 0) return '$symbol$whole';
    return '$symbol$whole.${fraction.toString().padLeft(2, '0')}';
  }

  String get currencySymbol {
    switch (currency.toUpperCase()) {
      case 'USD':
        return r'$';
      case 'ZAR':
        return 'R';
      case 'GBP':
        return '£';
      case 'EUR':
        return '€';
      default:
        // An unknown code is shown as the code itself with a space, which
        // is wrong-looking but never misleading — far better than picking
        // the wrong symbol for someone's money.
        return '${currency.toUpperCase()} ';
    }
  }

  String get raisedLabel => formatCents(raisedCents);
  String get goalLabel => formatCents(goalCents);
  String get remainingLabel => formatCents(remainingCents);
}
