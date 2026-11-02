import 'package:flutter/material.dart';
import 'widgets/legal_layout.dart';

/// Terms of Service, in-app. A MIRROR of the published page
/// (`legal-site/terms.html`, live at mtechstudioszw.github.io/adventconnect-legal),
/// generated from it on 2 Nov 2026 so the wording cannot drift. Change the
/// published page first, then re-mirror; `lastUpdated` carries its date.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalLayout(
      kicker: 'LEGAL',
      title: 'Terms of Service',
      subtitle: 'The agreement that keeps our community safe and respectful.',
      lastUpdated: '2 November 2026',
      intro:
          'By using Adventist Super App you agree to these terms. They explain your rights, our responsibilities and the rules that keep this community safe.',
      sections: [
        LegalSection(
          title: 'Agreeing to these Terms',
          body:
              'By creating an account or using Adventist Super App (the "App") you agree to these Terms, our Privacy Policy and our Community Guidelines. If you don\'t agree, please don\'t use the App. The App is provided by Tanatswa Michael Mikuwa ("we", "us"), operating from Zimbabwe, for the worldwide Seventh-day Adventist community. It is an independent app and is not an official service of the Seventh-day Adventist Church.',
        ),
        LegalSection(
          title: 'Who can use the App',
          body:
              'You must be at least 16 years old. By signing up you confirm that you are, and that the details you give are true.',
        ),
        LegalSection(
          title: 'Your account',
          body: '',
          bullets: [
            'Keep your password safe; you are responsible for what happens on your account.',
            'One account per person. Fake names, impersonation and false church affiliations are not allowed.',
            'Your home church is the church you actually attend. Church admin roles are verified before they are granted.',
            'We may limit, suspend or close accounts that break these Terms or the Guidelines.',
          ],
        ),
        LegalSection(
          title: 'Your content',
          body:
              'You own what you post — posts, prayers, photos, voice notes, stories, listings, job posts and Page content. You give us a non-exclusive, free licence to store and show it within the App, and on its share links (for example a shared event or listing), to the people you chose. The licence ends when you delete the content, except where others have already shared or saved it. You are responsible for having the right to post what you post.',
        ),
        LegalSection(
          title: 'Messages and calls',
          body: '',
          bullets: [
            'Chats and calls are end-to-end encrypted on current versions of the App (see the Privacy Policy for the exceptions). Because we can\'t read encrypted messages, we act on what is reported to us: reporting a message sends us a readable copy of it.',
            'Voice calls can be made between friends, or with someone who has replied to you. Free accounts have daily and monthly call minutes; Premium plans have more. Calls use mobile data or Wi-Fi.',
            'The App is not a phone service and cannot be used to call emergency services.',
            'Group admins can add and remove members, make other admins, and choose to let only admins send messages.',
            'If you lose your phone and have no chat backup, encrypted chat history cannot be recovered. If you forget your backup password, the backup cannot be opened — by you or by us.',
          ],
        ),
        LegalSection(
          title: 'Acceptable use',
          body: 'You agree not to use the App to:',
          bullets: [
            'break the law where you or the people you reach are;',
            'harass, threaten or spread hate against any person or group;',
            'post sexually explicit, gratuitously violent or harmful content;',
            'spam, scam, phish, or impersonate a person, church, ministry or the App;',
            'present yourself or a Page as an official church body without verification;',
            'interfere with the App, other members\' accounts, or our systems.',
          ],
        ),
        LegalSection(
          title: 'Pages',
          body:
              'Members can create Pages for ministries, businesses and organisations. Your account must be at least 14 days old with a confirmed email. Official names (for example the Seventh-day Adventist Church, its divisions and unions, ADRA, Hope Channel, the Ellen G. White Estate) and the word "official" are reserved for verified Pages. You may run up to 3 Pages, create at most one a week, and add up to 10 admins or editors to each.',
        ),
        LegalSection(
          title: 'Marketplace and jobs',
          body: '',
          bullets: [
            'Sellers accept the Marketplace Code of Conduct before opening a store. Listings must be accurate and lawful.',
            'Job posts are checked before they appear and expire after 30 days unless renewed.',
            'We do not take payments for goods or services or hold money for anyone. Deals are between the buyer and seller, or employer and applicant. Meet and pay safely.',
            'Moderators can hide a single listing or post; you will be told why and can appeal from the notification.',
          ],
        ),
        LegalSection(
          title: 'Premium, boosts and donations',
          body: '',
          bullets: [
            'Premium (Plus, Pro and Business) and boosts are sold through Google Play on Android. Prices are shown before you pay. Subscriptions renew until you cancel them in Google Play, and refunds follow Google Play\'s policies.',
            'Premium removes ads on Android and raises limits such as call minutes and Advent AI questions. Features can change; we will not take away something you have already paid for during the period you paid for.',
            'The gold tick is given after identity verification. It confirms who you are, not that we endorse what you post.',
            'Donations to support the App are voluntary and are made outside the App through the provider shown (such as EcoCash). They are not refundable and are not tax-deductible; we are not a registered charity.',
          ],
        ),
        LegalSection(
          title: 'Bible, books and other content',
          body:
              'Scripture translations and audio are provided under their own licences: the Shona Bible is Bhaibheri Dzvene Rakasununguka MuChiShona Chanhasi 2017 © Biblica, Inc. (Creative Commons BY-SA 4.0), and English audio is the Berean Standard Bible, narrated, from bible.helloao.org. Ellen G. White books, hymns, news and videos belong to their owners. Advent AI can make mistakes — check its answers against Scripture and trusted sources.',
        ),
        LegalSection(
          title: 'Third-party services',
          body:
              'The App relies on Supabase, Google (Firebase, Play, Gemini, YouTube), Apple, Cloudflare and Appodeal. Their terms also apply to the parts of the App they provide.',
        ),
        LegalSection(
          title: 'No warranty',
          body:
              'The App is provided "as is". We work hard to keep it running, but we don\'t guarantee that it will always be available, error-free, or that every feature will stay. Content posted by members is theirs, not ours, and we don\'t guarantee it is accurate.',
        ),
        LegalSection(
          title: 'Limitation of liability',
          body:
              'As far as the law allows, we are not liable for indirect or consequential losses from using the App, including disputes between members over sales, jobs or donations, or for lost data, including encrypted messages that can\'t be recovered.',
        ),
        LegalSection(
          title: 'Ending your use',
          body:
              'You can stop using the App and delete your account at any time from Settings. We may suspend or close an account that seriously or repeatedly breaks these Terms; where we can, we will tell you why.',
        ),
        LegalSection(
          title: 'Changes',
          body:
              'We may update these Terms and will change the date above when we do. Important changes will be shown in the App. Using the App after a change means you accept it.',
        ),
        LegalSection(
          title: 'Contact',
          body:
              'Questions about these Terms? Email tanatswamichaelmikuwa@gmail.com or WhatsApp +263 778 092 494.',
        ),
      ],
    );
  }
}
