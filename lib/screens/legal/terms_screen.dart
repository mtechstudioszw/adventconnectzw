import 'package:flutter/material.dart';
import 'widgets/legal_layout.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalLayout(
      kicker: 'LEGAL',
      title: 'Terms of Service',
      subtitle: 'The agreement that keeps our community safe and respectful.',
      lastUpdated: '20 June 2026',
      intro:
          'Welcome to Advent Connect ZW. By creating an account or using our app you agree to these terms. Please take a moment to read them — they explain your rights, our responsibilities and the rules that keep this community a safe place for everyone.',
      sections: const [
        LegalSection(
          title: 'Acceptance of Terms',
          body:
              'By signing up or continuing to use Advent Connect ZW you confirm that you have read, understood and accepted these Terms of Service in full. If you do not agree with any part of them, please discontinue use of the app.',
        ),
        LegalSection(
          title: 'User Accounts & Eligibility',
          body:
              'You must be at least 16 years old to create an account. You are responsible for keeping your sign-in details safe and for all activity that happens through your account. Provide accurate information when you sign up — false details may lead to suspension.',
        ),
        LegalSection(
          title: 'Community Guidelines',
          body:
              'Treat every member with kindness and respect. Hate speech, harassment, threats, sexual content, and discrimination of any kind are not allowed. Our full Community Guidelines explain what we expect in more detail.',
        ),
        LegalSection(
          title: 'Content & Intellectual Property',
          body:
              'You keep ownership of the content you post — prayers, listings, messages and photos. By posting, you grant us a non-exclusive licence to display that content within the app so other members can see it. Do not post content that you do not have the right to share.',
        ),
        LegalSection(
          title: 'Marketplace & Jobs Disclaimer',
          body:
              'Advent Connect ZW does not process payments and is not a party to any sale, hire or job arrangement made through the app. You connect with other members at your own risk.',
          bullets: [
            'Always meet in a safe, public place when buying or selling.',
            'Verify items in person before paying.',
            'Be cautious of offers that seem too good to be true.',
            'Never share banking PINs or one-time passwords.',
          ],
        ),
        LegalSection(
          title: 'Prayer Requests',
          body:
              'Prayer requests are personal. Do not screenshot, copy or share another member\'s prayer outside the app. Treat what is shared in this space with the confidentiality and care it deserves.',
        ),
        LegalSection(
          title: 'Messaging',
          body:
              'Direct messages must remain respectful. Unsolicited sales pitches, romantic harassment, threats and spam will result in account action. Block and report any member behaving inappropriately.',
        ),
        LegalSection(
          title: 'Prohibited Activities',
          body:
              'You agree not to do any of the following while using the app:',
          bullets: [
            'Impersonate another person, church or organisation.',
            'Attempt to access another member\'s account.',
            'Post illegal, violent, sexual or discriminatory content.',
            'Use the app to organise scams, pyramid schemes or fraud.',
            'Reverse engineer, scrape or otherwise abuse the platform.',
          ],
        ),
        LegalSection(
          title: 'Termination',
          body:
              'We may suspend or remove an account that violates these terms. You can also delete your own account at any time from Settings. Some content (for example, messages sent to other members) may remain visible to those recipients after deletion.',
        ),
        LegalSection(
          title: 'Limitation of Liability',
          body:
              'Advent Connect ZW is provided "as is". We work hard to keep the app reliable but cannot guarantee uninterrupted service. To the fullest extent allowed by law, we are not liable for losses arising from your use of the app or interactions with other members.',
        ),
        LegalSection(
          title: 'Governing Law',
          body:
              'These Terms are governed by the laws of Zimbabwe. Any dispute arising from your use of Advent Connect ZW falls under the exclusive jurisdiction of the courts of Zimbabwe. If any provision of these Terms is found to be unenforceable, the remaining provisions continue in full effect.',
        ),
        LegalSection(
          title: 'Changes to Terms',
          body:
              'These terms may evolve as the app grows. When we make material changes we will notify you in-app. Continuing to use Advent Connect ZW after changes means you accept the updated terms.',
        ),
        LegalSection(
          title: 'Contact',
          body:
              'Questions about these terms? Reach our team at hello@adventconnect.zw and we\'ll get back to you as soon as we can.',
        ),
      ],
    );
  }
}
