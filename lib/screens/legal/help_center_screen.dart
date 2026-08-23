import 'package:flutter/material.dart';
import 'widgets/legal_layout.dart';

/// Settings → Help center.
///
/// **This route did not exist.** `settings_screen.dart` has been calling
/// `context.pushNamed('help_center')` with no matching route registered, so
/// tapping Help center threw instead of opening anything. The guide it was
/// meant to show had been written (`docs/user-guide.md`) and never wired up.
///
/// Rendered through [LegalLayout] rather than a WebView, deliberately: the
/// legal screens' pattern already works with no connection, matches the app's
/// typography, and needs no network permission or loading state. A help page
/// is exactly the thing someone opens when the app is misbehaving, which is
/// often when their connection is the problem.
///
/// Kept in step with `docs/user-guide.md` by hand. That file is the version
/// the support site serves; this is the same content shaped into sections.
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalLayout(
      kicker: 'HELP',
      title: 'How to use the app',
      subtitle: 'A plain guide to everything in Adventist Super App.',
      lastUpdated: '16 August 2026',
      intro:
          'Written for members rather than developers. If you only read one '
          'section, read Getting started — setting your home church is the '
          'single most useful thing you can do.',
      sections: [
        LegalSection(
          title: 'Getting started',
          body:
              'Create an account with your email address, name and date of '
              'birth. You must be 16 or older. Your sign-in details are stored '
              'securely on your device, so you stay signed in between visits.',
          bullets: [
            'Set your home church — it shapes which churches, events and '
                'people the app shows you',
            'Add a photo and a short bio — people are far more likely to '
                'accept a friend request from a profile that looks like a '
                'real person',
          ],
        ),
        LegalSection(
          title: 'The five tabs',
          body: 'Along the bottom of the screen:',
          bullets: [
            'Home — your feed, plus quick access to everything else',
            'Watch — live TV, sermons and video',
            'Chat — messages, friends and groups',
            'Marketplace — buying and selling within the community',
            'Profile — you: your posts, friends and settings',
          ],
        ),
        LegalSection(
          title: 'Home',
          body:
              'The feed shows posts from people and churches you follow, '
              'newest and most relevant first. Tap the composer at the top to '
              'post, choosing Public or Friends only. Stories run along the '
              'top and disappear after 24 hours. The Today card carries a '
              'daily devotional, the day’s Sabbath School lesson, a hymn '
              'and a suggested book — the hymn alternates between Shona and '
              'English day by day. From Friday sundown to Saturday sundown the '
              'header changes to a warm sundown wash and the greeting '
              'Happy Sabbath.',
          bullets: [
            'Library shortcuts — the pills under the Today card: Bible, '
                'Sabbath, Hymnal, Quiz, Music and EGW',
            'The Sabbath countdown can be turned on or off in Settings',
          ],
        ),
        LegalSection(
          title: 'Watch',
          body:
              'Live TV channels, sermons and recorded events. Tap any video to '
              'play it; it continues in a small player while you browse. Some '
              'channels are live and labelled as such.',
        ),
        LegalSection(
          title: 'Chat',
          body:
              'Chat is private messaging between members. The field at '
              'the top searches people, groups and message text. Press and '
              'hold any message to report it. Blocking someone stops them '
              'messaging you and hides their posts, stories and prayers from '
              'you — in both directions.',
          bullets: [
            'Find people — in the ⋮ menu, for members you aren’t '
                'friends with yet',
            'Notes to self — a private space for your own notes',
            'Starred messages — messages you’ve saved',
            'Chat privacy — control who is allowed to message you',
            'Messages are NOT end-to-end encrypted. They are stored on our '
                'servers and can be accessed by administrators when a report '
                'is made, or where safety or the law requires it. Church '
                'admins cannot read your private chats.',
          ],
        ),
        LegalSection(
          title: 'Marketplace',
          body:
              'Browse items listed by other members, or sell your own. Your '
              'cart is on your device, and checkout sends your order directly '
              'to each seller on WhatsApp — one message per seller. The app '
              'does not process payments and is not part of the sale. To sell, '
              'open Seller mode from the Marketplace and add a product.',
          bullets: [
            'Meet in a public place, during the day',
            'Inspect the item before paying',
            'Never pay in advance for something you haven’t seen',
            'Never share a banking PIN or one-time password',
          ],
        ),
        LegalSection(
          title: 'Library',
          body:
              'Reached from the pills on Home, or the Library screen itself. '
              'To read offline, open a book’s ⋮ menu and choose Read '
              'offline — the book is kept on your phone so you can read it '
              'with no data. That is different from Save a copy, which hands a '
              'copy to your phone’s files or share sheet.',
          bullets: [
            'Bible — multiple translations including Shona, plus Hebrew and '
                'Greek. One translation has narrated audio, and your place is '
                'remembered',
            'Sabbath School — the current quarter day by day, with a Continue '
                'reading card. Defaults to English; around 90 languages are '
                'available and your choice is remembered',
            'Hymnal — 995 hymns in Shona and English, bundled with the app, '
                'working with no connection at all',
            'EGW — 61 Ellen G. White books, including the full Conflict of the '
                'Ages series, all nine Testimonies for the Church and three '
                'Selected Messages',
            'Music — worship music and hymn recordings. Playback continues '
                'while you use other parts of the app',
          ],
        ),
        LegalSection(
          title: 'Quiz',
          body:
              'A Bible quiz, reached from the Quiz pill on Home or from the '
              'Library. Sound effects and background music are separate '
              'switches — turning off the effects leaves the music playing, '
              'and vice versa.',
          bullets: [
            'Daily Challenge — the same questions for everyone that day',
            'Quick Play, Survival, Speed Round and Fix Your Mistakes',
            'Challenge a friend, and live matches against other members',
            'A weekly leaderboard that resets on Sunday',
          ],
        ),
        LegalSection(
          title: 'Prayer',
          body:
              'Share a prayer request, or pray for someone else’s. '
              'Requests can be public, church-only or anonymous, where your '
              'name is hidden from everyone. When you pray for a request the '
              'person is told how many have prayed — never who. Please treat '
              'prayer requests as confidential: don’t screenshot them or '
              'repost them outside the app.',
        ),
        LegalSection(
          title: 'Churches',
          body:
              'A directory of Seventh-day Adventist congregations — around '
              '2,600 listed so far, with Zimbabwe mapped in full and more '
              'countries being added over time. Search by name or city, or '
              'sort by nearest if you allow location access. Following a '
              'church puts its announcements and events in your feed. If you '
              'lead a congregation, open it and tap the claim link — claims '
              'are reviewed before approval, and a church can only be claimed '
              'by one person.',
        ),
        LegalSection(
          title: 'Events, Jobs and News',
          body: 'Three smaller sections, reachable from Home:',
          bullets: [
            'Events — church events and camp meetings; RSVP so the organiser '
                'knows',
            'Jobs — job listings posted by members',
            'Advent News — editorial coverage from the wider Adventist '
                'community',
          ],
        ),
        LegalSection(
          title: 'Profile and Settings',
          body:
              'Your profile holds your posts, photos, friends, ministry and '
              'spiritual gifts. Settings covers:',
          bullets: [
            'Notifications — pick exactly which alerts you receive',
            'Sound and haptics, including the quiz’s separate music and '
                'effects switches',
            'Theme',
            'Chat privacy — who may message you',
            'Blocked members — review and unblock',
            'Sabbath countdown — on or off',
            'Delete account — permanent. You will be asked to choose a reason '
                'first.',
          ],
        ),
        LegalSection(
          title: 'Premium',
          body:
              'An optional subscription that removes ads and unlocks extra '
              'features. Manage or cancel it any time through Google Play — '
              'the app never handles your card.',
        ),
        LegalSection(
          title: 'Getting help',
          body: 'If something here did not answer your question:',
          bullets: [
            'In-app — the report option on any post, profile or message',
            'Email — hello@adventconnect.zw',
            'Safety concerns — safety@adventconnect.zw',
          ],
        ),
      ],
    );
  }
}
