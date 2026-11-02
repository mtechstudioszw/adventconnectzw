import 'package:flutter/material.dart';
import 'widgets/legal_layout.dart';

/// Community Guidelines, in-app. A MIRROR of the published page
/// (`legal-site/guidelines.html`, live at mtechstudioszw.github.io/adventconnect-legal),
/// generated from it so the wording cannot drift. Change the published page
/// first, then re-mirror; `lastUpdated` carries its date.
class GuidelinesScreen extends StatelessWidget {
  const GuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalLayout(
      kicker: 'COMMUNITY',
      title: 'Community Guidelines',
      subtitle: 'How we look out for one another in this space.',
      lastUpdated: '2 November 2026',
      intro:
          'Adventist Super App is a place for the Seventh-day Adventist community worldwide to connect, encourage one another, pray together and support local churches. These Guidelines keep it safe and kind. They apply everywhere in the App — the feed, stories, prayers, Pages, the marketplace, jobs, events, chats, groups and calls.',
      sections: [
        LegalSection(
          title: 'Be kind',
          body: '',
          bullets: [
            'Treat others with Christian courtesy, even when you disagree.',
            'No harassment, bullying, threats or hate against any person or group.',
            'Disagree about ideas, not people. Doctrinal discussion is welcome; mocking others\' faith is not.',
          ],
        ),
        LegalSection(
          title: 'Keep it clean and lawful',
          body: '',
          bullets: [
            'No sexual, violent or graphic content.',
            'Nothing illegal, and nothing that encourages self-harm or harm to others.',
            'No scams, fake fundraisers or misleading listings and job posts.',
            'Some words are filtered automatically; trying to get around the filter counts as breaking the rule.',
          ],
        ),
        LegalSection(
          title: 'Be honest about who you are',
          body: '',
          bullets: [
            'Use your real name. Don\'t pretend to be another person, a pastor, a church, a ministry or the App.',
            'Set your home church to the church you actually attend.',
            'Pages that look official must be verified. Don\'t use official church names, or the word "official", on an unverified Page.',
            'The gold tick means a person\'s identity was checked. Don\'t imitate it in names or photos.',
          ],
        ),
        LegalSection(
          title: 'Respect privacy',
          body: '',
          bullets: [
            'Don\'t share someone\'s private messages, photos, phone number or address without their permission. End-to-end encryption protects a chat on the way; it can\'t stop a screenshot, so be trustworthy with what people tell you.',
            'Treat prayer requests with care. If someone posted anonymously, don\'t try to work out who it is.',
            'Don\'t record calls or share call audio without everyone\'s agreement.',
          ],
        ),
        LegalSection(
          title: 'Chats, groups and calls',
          body: '',
          bullets: [
            'Don\'t send messages or calls to people who have made clear they don\'t want them. Respect blocks and privacy settings.',
            'Group admins: use your tools fairly. Remove people for breaking the rules, not to settle arguments. Use "only admins can send" for announcements, not to silence disagreement.',
            'Don\'t add people to groups to spam them, and don\'t share group invite links where they will be abused.',
            'Church announcement channels are for genuine church announcements.',
          ],
        ),
        LegalSection(
          title: 'Pages, marketplace and jobs',
          body: '',
          bullets: [
            'Pages must represent a real ministry, business or organisation, and post content that matches it.',
            'List only what you genuinely offer, at the price and condition you state. No prohibited or Sabbath-dishonouring promotions.',
            'Job posts must be real, lawful and describe the actual pay and conditions. Never ask applicants for money.',
            'The App doesn\'t take part in payments. Meet in safe places and be careful with anyone who asks you to pay first.',
          ],
        ),
        LegalSection(
          title: 'Don\'t spam',
          body: '',
          bullets: [
            'No repeated posting, mass messages or flooding groups. Each section has a small daily limit.',
            'Boosts and Featured spots are for honest promotion, not for content that breaks these rules.',
          ],
        ),
        LegalSection(
          title: 'Reporting and what happens next',
          body:
              'If something breaks these Guidelines, tap Report on the message, post, story, prayer, listing, job, Page, group or profile. Chats are end-to-end encrypted, so we can only see a message if someone reports it: reporting sends us a readable copy of that one message, nothing else from the chat.',
        ),
        LegalSection(
          title: 'Hidden posts, appeals and blocking',
          body:
              'Moderators may hide a post or listing, limit features, or suspend or ban an account. If something of yours is hidden, you\'ll get a notification explaining why, with a way to appeal. Block stops someone from seeing your profile, posts, stories and prayers, and from messaging or calling you.',
        ),
        LegalSection(
          title: 'Your agreement',
          body:
              'Using Adventist Super App means you agree to these Guidelines, our Terms of Service and our Privacy Policy.',
        ),
      ],
    );
  }
}
