import 'package:flutter/material.dart';
import 'widgets/legal_layout.dart';

/// Community Guidelines, in-app.
///
/// ## This file is a MIRROR, not an author
///
/// Three genuinely different Community Guidelines existed at once — the live
/// site had 8 sections, this screen had 9, and `docs/guidelines.html` had 10,
/// with sections in each that appeared nowhere else. That is not three copies
/// that drifted; it is three documents, and a member could be held to
/// whichever one an admin happened to be reading.
///
/// **Founder decision, 16 Aug 2026: the live site wins.** It is the URL
/// declared in the Play Console
/// (`mtechstudioszw.github.io/adventconnect-legal/guidelines.html`), so it is
/// the version with actual standing — the one a member is deemed to have
/// agreed to. This screen and `docs/guidelines.html` were rewritten to match
/// it section for section.
///
/// The previous in-app text was warmer and more pastoral ("A gentle answer
/// turns away wrath", marketplace safety tips, a graded Consequences list).
/// Some of it was genuinely better writing. It was also **text nobody had
/// agreed to**, which is the one thing a guidelines screen cannot be. If the
/// founder wants that voice back, the way to do it is to change the published
/// document first and re-mirror — not to edit this file.
///
/// `lastUpdated` deliberately carries the PUBLISHED document's date, not the
/// date this file was touched. The in-app copies previously showed later
/// dates than the published ones, which made the weaker text look like the
/// current text. Same date here means same document.
///
/// Source of truth: `legal-site/guidelines.html` (byte-identical mirror of
/// the live repo). Do not edit the wording below without changing that first.
class GuidelinesScreen extends StatelessWidget {
  const GuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalLayout(
      kicker: 'COMMUNITY',
      title: 'Community Guidelines',
      subtitle: 'How we look out for one another in this space.',
      lastUpdated: '10 June 2026',
      intro:
          'Advent Connect ZW is a space for the Seventh-day Adventist '
          'community in Zimbabwe to connect, encourage one another, share '
          'prayer, and support local churches. These Guidelines keep it safe '
          'and respectful. They apply everywhere in the App — the feed, '
          'stories, prayers, the directory, marketplace, jobs, events, and '
          'all chats and church groups.',
      sections: [
        LegalSection(
          title: 'Be respectful',
          body: '',
          bullets: [
            'Treat others with kindness and Christian charity, even in '
                'disagreement.',
            'No harassment, bullying, threats, or hate speech against any '
                'person or group.',
          ],
        ),
        LegalSection(
          title: 'Keep it clean and lawful',
          body: '',
          bullets: [
            'No sexually explicit, violent, or graphic content.',
            'No illegal content or activity, and nothing that promotes harm.',
            'No scams, fraud, or deceptive marketplace/job listings.',
          ],
        ),
        LegalSection(
          title: 'Be honest about who you are',
          body: '',
          bullets: [
            'Don’t impersonate other people, churches, pastors, or the '
                'platform.',
            'Use your real home church; church administrator roles must be '
                'verified.',
          ],
        ),
        LegalSection(
          title: 'Respect privacy',
          body: '',
          bullets: [
            'Don’t share other people’s private information without consent.',
            'Remember that prayer requests can be posted publicly or '
                'anonymously — choose appropriately, and treat others’ '
                'requests with care.',
          ],
        ),
        LegalSection(
          title: 'Don’t spam',
          body: '',
          bullets: [
            'No repetitive posting, mass-messaging, or flooding groups. '
                'Posting is limited to a small number of items per day per '
                'section.',
            'Keep church announcement channels for genuine announcements.',
          ],
        ),
        LegalSection(
          title: 'Marketplace & jobs',
          body: '',
          bullets: [
            'List only items/opportunities you genuinely offer, with accurate '
                'details.',
            'The platform is not a party to your transactions — be cautious '
                'and meet/pay safely.',
          ],
        ),
        LegalSection(
          title: 'Reporting & enforcement',
          body:
              'If you see something that breaks these Guidelines, use the '
              'Report option on the message, group, post, listing, or '
              'profile. Reports go to the platform administrator, who may '
              'remove content, restrict features, or suspend or ban accounts. '
              'Blocking a user stops them from seeing your profile, posts, '
              'stories and prayers, and from delivering messages to you.',
        ),
        LegalSection(
          title: 'A note on messaging',
          body:
              'Chats are not end-to-end encrypted and may be reviewed by '
              'administrators when a report is made or for safety/legal '
              'reasons. Please keep conversations consistent with these '
              'Guidelines.',
        ),
      ],
    );
  }
}
