import 'package:flutter/material.dart';
import 'widgets/legal_layout.dart';

class GuidelinesScreen extends StatelessWidget {
  const GuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalLayout(
      kicker: 'COMMUNITY',
      title: 'Community Guidelines',
      subtitle: 'How we look out for one another in this space.',
      lastUpdated: '6 May 2026',
      intro:
          'Advent Connect ZW exists to bring the SDA community in Zimbabwe closer together. These guidelines help keep the app a welcoming, helpful and safe space. Read them, share them, and help us hold each other to them in love.',
      sections: const [
        LegalSection(
          title: 'Be Respectful & Kind',
          body:
              'Treat every member the way you would want to be treated. Disagreement is welcome, but personal attacks, insults and rude comments are not. A gentle answer turns away wrath.',
        ),
        LegalSection(
          title: 'No Hate Speech or Discrimination',
          body:
              'Do not post content that demeans or attacks people because of race, ethnicity, gender, nationality, disability, denomination, language or any other characteristic. We have zero tolerance for hate speech.',
        ),
        LegalSection(
          title: 'Keep It Safe',
          body:
              'Threats, intimidation, descriptions of self-harm or violence directed at people or groups are not allowed. If you are in crisis, please reach out to local emergency services or a trusted pastor.',
        ),
        LegalSection(
          title: 'Respect Privacy',
          body:
              'Do not share another member\'s personal information without their permission. Prayer requests in particular are sacred — never screenshot or repost them outside the app.',
        ),
        LegalSection(
          title: 'No Spam or Scams',
          body:
              'Avoid unsolicited promotions, repetitive posts and chain messages. Pyramid schemes, money-flipping requests and "you have won" messages are scams — report them so our team can act.',
        ),
        LegalSection(
          title: 'Marketplace Safety',
          body:
              'When buying or selling through the app:',
          bullets: [
            'Meet in a safe, public place during the day.',
            'Bring a friend or family member if possible.',
            'Inspect items before paying — never pay in advance for unseen goods.',
            'Use trusted payment methods and request a receipt.',
            'Trust your instincts; walk away if something feels wrong.',
          ],
        ),
        LegalSection(
          title: 'Appropriate Content',
          body:
              'Keep posts, profile photos and messages family-friendly. Sexual content, graphic violence, alcohol promotion and tobacco promotion are not allowed.',
        ),
        LegalSection(
          title: 'Report Violations',
          body:
              'Help us keep the community safe. If you see a post, profile or message that breaks these guidelines, tap the report option or email safety@adventconnect.zw with details. Reports are confidential.',
        ),
        LegalSection(
          title: 'Consequences',
          body:
              'When guidelines are broken we take action depending on severity:',
          bullets: [
            'A warning with guidance on how to do better.',
            'Temporary suspension while a situation is reviewed.',
            'Permanent ban for serious or repeated violations.',
            'Removal of the offending content.',
          ],
        ),
      ],
    );
  }
}
