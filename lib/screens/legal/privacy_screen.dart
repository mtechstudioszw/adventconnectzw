import 'package:flutter/material.dart';
import 'widgets/legal_layout.dart';

/// Privacy Policy, in-app. A MIRROR of the published page
/// (`legal-site/privacy.html`, live at mtechstudioszw.github.io/adventconnect-legal),
/// generated from it on 2 Nov 2026 so the wording cannot drift. Change the
/// published page first, then re-mirror; `lastUpdated` carries its date.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalLayout(
      kicker: 'LEGAL',
      title: 'Privacy Policy',
      subtitle: 'What we collect, why we collect it, and how we look after it.',
      lastUpdated: '2 November 2026',
      intro:
          'Plain answers to what the App collects, who can see it, and what you can do about it.',
      sections: [
        LegalSection(
          title: 'Who we are',
          body:
              'Adventist Super App (the "App") is operated by Tanatswa Michael Mikuwa, an independent developer based in Zimbabwe. Contact: tanatswamichaelmikuwa@gmail.com. This policy explains what the App collects, why, who can see it, and what you can do about it. We have tried to write it plainly, including the limits of what we promise.',
        ),
        LegalSection(
          title: 'What we collect',
          body: '',
          bullets: [
            'Account data: email, full name, username, date of birth, profile and cover photo, bio, country and home church.',
            'Content you create: posts, comments, prayer requests, stories, events, marketplace listings and orders, job posts and applications, Pages you run, and your messages, photos and voice notes in chats.',
            'Encryption keys: to make end-to-end encryption work, your phone uploads its public keys. Your private keys never leave your phone.',
            'Call records: who called whom, when, how long it lasted and how it ended (see section 6). Never the audio.',
            'Device data: a push-notification token (Firebase Cloud Messaging on Android; Apple Push Notification service on iPhone, including a separate token for incoming calls).',
            'Location: only when you ask for it ("Near me" churches, or working out Sabbath times). It is used on your phone and not stored on our servers. We never track you in the background.',
            'Gold tick verification (Android): if you apply, your legal name, a photo of your ID and a selfie, kept in private storage only our review team can open, and deleted as soon as a decision is made.',
            'Purchases (Android): if you buy Premium or a boost, Google Play takes the payment; we receive only a purchase token to confirm it.',
            'Diagnostics: crash reports (Firebase Crashlytics) and basic in-app usage events so we can find bugs and see which features are used.',
          ],
        ),
        LegalSection(
          title: 'What we don\'t collect',
          body: '',
          bullets: [
            'Your contacts list.',
            'Photos or files other than the ones you choose to send or upload.',
            'Background location.',
            'Microphone input, except while you record a voice note or are on a call. Camera input, except when you take a photo.',
            'Card or wallet details. Payments are handled by Google Play or, for donations, by the payment provider you choose; we never see them.',
            'What you say to the reading voice: "Listen" for Ellen G. White books uses your phone\'s own text-to-speech, on the phone.',
          ],
        ),
        LegalSection(
          title: 'How we use it',
          body: '',
          bullets: [
            'To sign you in and keep your account secure.',
            'To show your content to the people you chose (section 5).',
            'To deliver messages, calls and the notifications you turned on.',
            'To find churches and events near you, and to show your church\'s announcements.',
            'To enforce limits (for example daily call minutes and posting limits), prevent spam and investigate reports.',
            'To fix crashes and improve the App.',
          ],
        ),
        LegalSection(
          title: 'Ads',
          body:
              'We do not sell your data. The Android version shows ads, through Appodeal and its advertising partners, which may use your device\'s advertising ID; Premium members see no ads. The iPhone app shows no ads.',
        ),
        LegalSection(
          title: 'Who can see what',
          body: '',
          bullets: [
            'Public posts, events, prayers, listings, job posts and Pages are visible to signed-in members, and some (events, listings, jobs) can be opened from a share link.',
            'Friends-only posts and stories are visible only to your accepted friends.',
            'Church-only prayers are visible to members whose home church is the same as yours.',
            'Anonymous prayers hide your name from everyone.',
            'Private profile: you can limit who sees your profile, who can follow you (off by default) and who can message you, in Settings → Privacy.',
            'Chats are visible only to the people in them. Church admins cannot read private chats.',
            'Church admins can see the list of members whose home church is their church (name and photo), so they can serve their congregation.',
          ],
        ),
        LegalSection(
          title: 'Encryption, calls and backups',
          body:
              'Chats. Private and group chats — messages, photos and voice notes — are end-to-end encrypted on current versions of the App: they are sealed on your phone and can only be opened on the phones of the people in the chat. Our servers store them only in a form we cannot read. Encryption is being switched on for all members during November 2026. Honest exceptions:',
          bullets: [
            'Church announcement channels are not encrypted — they are broadcasts.',
            'Messages sent before encryption was on for both of you, or to or from an older version of the App, are stored readably.',
            'If you report a message, your phone sends us a readable copy of that one message so it can be reviewed.',
            'We still see who you chat with and when (but not what you say), because we have to deliver the messages.',
            'Notifications for encrypted messages say only "New message", "Photo" or "Voice note" — never the text.',
          ],
        ),
        LegalSection(
          title: 'Stories',
          body:
              'Friends-only stories are end-to-end encrypted in the same way. Public stories are meant for everyone and are not. Stories disappear after 24 hours.',
        ),
        LegalSection(
          title: 'Voice calls',
          body:
              'Your microphone is used only while a call is in progress. Call audio travels directly between the phones and is encrypted from one phone to the other; on current versions the two phones also check each other\'s keys over the encrypted chat, so not even our server can step into the middle. When a network blocks a direct connection, the encrypted audio passes through a relay run by Cloudflare, which cannot listen to it. We never record calls. An incoming call may appear on your lock screen through your phone\'s calling screen.',
        ),
        LegalSection(
          title: 'Chat backup',
          body:
              'If you turn on Settings → Chat backup, your phone seals your chat history with a password you choose and stores the sealed file in a private folder on our servers. We never see the password and cannot open the backup. If you forget the password, the backup cannot be recovered — by you or by us.',
        ),
        LegalSection(
          title: 'Everything else',
          body:
              'Everything else — profiles, posts, prayers, listings — is protected by access rules but is not end-to-end encrypted, and can be accessed by authorised administrators when needed, for example to act on a report.',
        ),
        LegalSection(
          title: 'Other services we use',
          body: '',
          bullets: [
            'Supabase — database, sign-in, file storage and server functions, hosted in the EU (Frankfurt, Germany).',
            'Google Firebase — push notifications (Android) and crash reports.',
            'Apple — push notifications and incoming-call alerts on iPhone; Sign in with Apple if you use it.',
            'Cloudflare — call relay when a direct connection fails (encrypted audio only).',
            'Google Play — payments for Premium and boosts (Android).',
            'Appodeal and its partners — ads on Android for members without Premium.',
            'Google Gemini — only if you choose to use Advent AI and agree first. What you type to it is sent to Google to produce the answer; please don\'t include personal or sensitive details.',
            'bible.helloao.org — the narrated English Bible is streamed or downloaded from this free Bible service, which therefore sees your device\'s network address, as any website does. Downloaded chapters are kept on your phone.',
            'YouTube — videos in Watch are played from YouTube under Google\'s terms.',
          ],
        ),
        LegalSection(
          title: 'How long we keep it',
          body: '',
          bullets: [
            'Your account and content: until you delete them or your account.',
            'Stories: 24 hours.',
            'Messages: until you or the other person deletes them, or the account is deleted.',
            'Detailed call logs: 30 days. Your call history list stays until your account is deleted.',
            'Encrypted copies kept so a message can be re-sent to a new phone: at most 30 days.',
            'Usage events: 120 days. Crash reports: 90 days.',
            'Old notifications are cleared automatically.',
            'Verification documents: deleted when a decision is made.',
          ],
        ),
        LegalSection(
          title: 'Deleting your account',
          body:
              'Settings → Delete account removes your profile, your content, your uploaded photos and voice notes, your chat backup and your sign-in. Messages you sent stay encrypted on the other person\'s phone, as with any messaging app. Some data may remain in our service providers\' backups until they age out, typically within 30 days.',
        ),
        LegalSection(
          title: 'Age',
          body:
              'You must be at least 16 to use the App, and sign-up checks your date of birth. We do not knowingly collect information from anyone younger. If you believe someone under 16 has an account, contact us and we will remove it. Members aged 16–17 are encouraged to use the App with a parent or guardian\'s involvement.',
        ),
        LegalSection(
          title: 'Security',
          body:
              'Sign-in tokens are kept in encrypted storage on your phone (Android Keystore / iOS Keychain). Everything travels over HTTPS. Database rules check every request so you can only read and change what you\'re allowed to. No system is perfectly secure; if we learn of a breach that affects you, we will tell you.',
        ),
        LegalSection(
          title: 'Your rights',
          body: '',
          bullets: [
            'Edit or delete your posts, prayers, messages, listings and events.',
            'Change who can see your profile, follow you and message you.',
            'Turn any kind of notification off in Settings.',
            'Delete your account.',
            'Ask for a copy of your data, or for a correction, by emailing tanatswamichaelmikuwa@gmail.com. We can\'t give you encrypted messages, because we can\'t read them.',
          ],
        ),
        LegalSection(
          title: 'Data-protection law',
          body:
              'We handle personal information in line with Zimbabwe\'s Cyber and Data Protection Act [Chapter 12:07]. Wherever you live you may ask to access, correct, export or delete your data, object to how we use it, or withdraw consent. If you are covered by another data-protection law, such as the GDPR in the EU/EEA and UK, those rights also apply, and you may complain to your local data-protection authority.',
        ),
        LegalSection(
          title: 'Changes',
          body:
              'We will update this page and its date when our practices change, and tell you inside the App about important changes.',
        ),
        LegalSection(
          title: 'Contact',
          body:
              'Privacy questions: tanatswamichaelmikuwa@gmail.com or WhatsApp +263 778 092 494.',
        ),
      ],
    );
  }
}
