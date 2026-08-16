import 'package:flutter/material.dart';
import 'widgets/legal_layout.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalLayout(
      kicker: 'LEGAL',
      title: 'Privacy Policy',
      subtitle: 'What we collect, why we collect it, and how we look after it.',
      lastUpdated: '16 August 2026',
      intro:
          'Your privacy matters to us. This policy explains the personal information Advent Connect ZW collects when you use the app, how we use it, and the choices you have. We aim to keep this clear and honest — if anything is unclear please reach out and we\'ll explain.',
      sections: const [
        LegalSection(
          title: 'Information We Collect',
          body:
              'We collect the minimum information needed to give you a useful, safe community experience. This includes:',
          bullets: [
            'Account details: email address, full name and date of birth.',
            'Profile data you choose to add: bio, home church and photo.',
            'Content you create: prayers, listings, messages, RSVPs.',
            'Usage data: which screens you visit and how the app is performing.',
            'Device data: operating system and app version, used for diagnostics.',
            'A push-notification token, so we can deliver the alerts you opt into.',
          ],
        ),
        LegalSection(
          title: 'How We Use Your Information',
          body:
              'We use your information to operate the app and improve your experience.',
          bullets: [
            'Provide core features such as sign-in, messaging and prayer requests.',
            'Send notifications you have opted into (events, prayers, messages).',
            'Detect abuse, spam and security threats.',
            'Improve the app based on aggregated, non-personal usage trends.',
          ],
        ),
        LegalSection(
          title: 'Data Sharing',
          body:
              'We do not sell your personal information — ever. We share data only with the trusted infrastructure providers we need to run the app:',
          bullets: [
            'Supabase (Africa, Cape Town region) hosts our database and authentication.',
            'Crash and analytics tools that receive anonymised diagnostic data.',
            'Authorities, only when required by law and with proper legal process.',
          ],
        ),
        LegalSection(
          title: 'Data Security',
          body:
              'We protect your data with industry-standard safeguards. Auth tokens are kept in your device\'s secure storage (Keychain on iOS, encrypted shared preferences on Android). All traffic between the app and our servers is encrypted in transit. Sensitive operations are protected at the database level with row-level security.',
        ),
        // SYNCED FROM THE PUBLISHED POLICY, NOT NEWLY DRAFTED.
        //
        // The live policy at mtechstudioszw.github.io/adventconnect-legal —
        // the URL Google Play links to from the store listing — already
        // discloses this in its "Who can access your data" and "Encryption
        // model" sections. This in-app screen did NOT: it listed messages
        // under content we collect and stopped there, with zero mention of
        // administrator access or the absence of end-to-end encryption.
        //
        // So the copy most members will actually read was materially weaker
        // than the one Play links to, while carrying a LATER "last updated"
        // date — which made the weaker text look like the current one. The
        // wording below is lifted from the published policy rather than
        // paraphrased, so the two cannot drift apart in meaning.
        LegalSection(
          title: 'Who Can Access Your Data',
          body:
              'It is important to us that you know exactly who can see what:',
          bullets: [
            'You — your own data, and content shared with you. This is enforced at the database level with row-level security, not just in the app.',
            'Other members — only what you make visible under the app\'s visibility rules, such as public versus friends-only posts, or public versus anonymous prayers.',
            'Church admins — cannot read your private chats.',
            'Our servers and administrators — backend functions use a privileged database credential that can read stored data. This means authorised administrators can technically access stored content, including messages. Messaging is not end-to-end encrypted, and messages are stored on our servers in readable form.',
          ],
        ),
        LegalSection(
          title: 'Your Rights',
          body:
              'You are in control of your data. From Settings you can:',
          bullets: [
            'Edit or update your profile information at any time.',
            'Request a copy of your data by emailing privacy@adventconnect.zw.',
            'Delete your account, which removes your profile and posts.',
            'Adjust or revoke notification preferences at any time.',
          ],
        ),
        LegalSection(
          title: 'Children\'s Privacy',
          body:
              'Advent Connect ZW is for members aged 16 and older. We do not knowingly collect personal information from anyone under 16. If you believe a younger person has registered, please contact us so we can remove the account. Members aged 16–17 are encouraged to use the app with the involvement of a parent or guardian.',
        ),
        LegalSection(
          title: 'Zimbabwe Data Protection Act Compliance',
          body:
              'We process personal information in accordance with the Cyber and Data Protection Act [Chapter 12:07] of Zimbabwe. You have the right to access, correct or object to the processing of your personal information, and to lodge a complaint with the relevant data protection authority.',
        ),
        LegalSection(
          title: 'Data Retention',
          body:
              'We keep your personal information only for as long as your account is active or as long as we need it to run the app. When you delete your account, your profile and posts are removed promptly. A small amount of data may be retained briefly where the law, security or fraud-prevention requires it, and is then deleted. Messages you have already sent to other members may remain visible to those recipients.',
        ),
        LegalSection(
          title: 'Changes to this Policy',
          body:
              'We may update this Privacy Policy from time to time. Material changes will be highlighted in the app and the "Last updated" date above will reflect the most recent revision.',
        ),
        LegalSection(
          title: 'Contact Us',
          body:
              'For privacy questions or to exercise your rights, email privacy@adventconnect.zw. We aim to respond within seven working days.',
        ),
      ],
    );
  }
}
