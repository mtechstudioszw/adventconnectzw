# App Store resubmission — 29 Oct 2026

## Before you upload: App Store Connect checklist

These are settings in App Store Connect, not code. The last rejection
(2.3.6) was one of them.

1. **Age Rating (fixes Guideline 2.3.6).** App Information → Age Rating →
   Edit. Set **In-App Controls → Parental Controls: None** and
   **Age Assurance: None**. The app has neither.
2. **App Review Information → Notes.** Paste the message below. Delete any
   old note that mentions background audio or a screen recording.
3. **Sign-in information.** Keep the demo account ("Apple Dev Teter"). It
   is active and not banned; Apple last signed in on 28 Oct 2026. Make sure
   the email and password there are the current ones.
4. **App Privacy.** Should already match. Data linked to the user: Contact
   info (email, name), User content (photos, messages, posts), Identifiers
   (user ID), and Diagnostics. **No tracking, and no advertising data on
   iOS** — the iPhone build starts no ad SDK.
4b. **Description, keywords and screenshots must not mention Advent AI,
   ads or Premium** — none of them are in the iPhone build (Guideline
   2.3.1). Remove any screenshot that shows the AI chat.
5. **Privacy Policy URL.** Opens the published policy. Update the
   published page with `docs/privacy.html` (changed today: storage region
   Frankfurt, Advent AI/Gemini, ads Android-only, verification, purchases).
6. **Build.** Upload a new build (a build number higher than 97). Version
   2.0.2 can stay — it was never released.
7. **Encryption.** Answer as before (standard HTTPS only — exempt).

## Voice calls (added 1 Nov 2026) — read before the next upload

This build turns on **voice calls**, which brings back the `audio`
background mode Apple rejected on 29 Oct (Guideline 2.5.4), plus `voip`.
This time they have a real use. Add this paragraph to the Notes below and
**attach a screen recording** (App Store Connect → App Review Information →
Attachment) showing:
1. Account A calls account B from a chat (call button, top right).
2. B's iPhone is LOCKED and rings with the native call screen.
3. B answers; both talk; B presses the side button to lock — audio
   continues.
4. Hang up.

Paragraph to paste:

> Voice calling: members can make 1:1 and small-group voice calls to
> friends. We use the `voip` background mode with PushKit/CallKit so an
> incoming call rings on a locked iPhone, and the `audio` background mode
> so a call in progress keeps its audio when the screen locks. Calls are
> peer-to-peer (WebRTC); no audio is recorded or stored. A screen
> recording is attached. To test: sign in to the demo account on two
> devices is not required — call the second review account "Apple Dev
> Teter 2" (or ask us and we will call you during review).

**You need a second demo account** that is friends with the review demo
account, so the reviewer has someone to call. Create it, make the two
friends, and put its email/password in the Notes.

## The message for App Review (paste into Notes)

> Hello App Review team,
>
> Thank you for the review of build 97. This build fixes both issues:
>
> **Guideline 2.5.4 – background audio:** The app no longer declares any
> audio background mode. "audio" has been removed from UIBackgroundModes
> (the only remaining mode is remote-notification, for push
> notifications), and the music player is not included in the iOS
> version, so no audio plays in the background.
>
> **Guideline 2.3.6 – Age Rating:** The app has no parental controls or
> age assurance features, so we updated the Age Rating: In-App Controls
> and Age Assurance are now set to "None".
>
> **Other notes for the review:**
> - The iOS version contains no in-app purchases, subscriptions,
>   donations, paid features or advertising. Every payment entry point is
>   removed from the iOS build.
> - User-generated content: users must accept the Terms of Use, Privacy
>   Policy and Community Guidelines when signing up. Every post, comment,
>   profile, message, listing, event, job and Page has a Report option,
>   users can block other users, objectionable words are filtered
>   automatically, and we review reports within 48 hours and remove
>   content or ban accounts that break the rules.
> - Users can delete their account in the app: Settings → Delete account.
> - Location is used only when the user asks for it (churches near you,
>   Sabbath sunset times). Notifications use push and local reminders.
> - Demo account: please use the sign-in information provided in App
>   Review Information.
>
> Thank you for your time.

## What changed in the code for this build (for your own records)

- Ads: no ad SDK starts on iPhone (`kHideAds`). The Appodeal key is
  registered for Android, and iOS ads would need an App Tracking
  Transparency prompt and SKAdNetwork ids first.
- Store links: every "update" prompt and share link on iPhone now opens
  the App Store (`apps.apple.com/app/id6819068736`), never Google Play
  (Guideline 2.3.10).
- Help Center: the Premium section (which named Google Play) is hidden on
  iPhone.
- Permission prompts now name every use: camera (posts, listings, chats,
  friend QR codes), photos, and location (churches near you and Sabbath
  times) — Guideline 5.1.1.
- In-app privacy policy updated (location, photos/voice notes, ads
  Android-only, Gemini, verification, purchases).
- All new Premium features (gold tick ID check, Business, boosts) are
  hidden on iPhone: `kHidePayments` on every entry point, and the
  `/premium`, `/get-verified` routes redirect to Home on iOS.
- **Advent AI is hidden on iPhone** (`kHideAdventAi`): the Chat inbox
  button, the onboarding film's AI scene and the `/advent-ai` route. Google
  denied the Gemini project on 26 Sep 2026, so it can't answer; a reviewer
  finding a broken feature is a 2.1 rejection.
- Earlier fixes still in place: `audio` removed from UIBackgroundModes and
  music hidden on iOS (`kHideMusic`), iOS 15.0 target, location usage
  strings, Sign in with Apple, AI consent sheet.

## Honest risks that remain

- **Content licensing (5.2.1).** The hymnals' lyrics and the EGW books
  must be ones you have the right to publish. If anyone complains, Apple
  can pull the app. Keep the permission letters you have.
- **1.1.1 was never explained.** Build 85's objectionable-content
  rejection had no specific item. Before submitting, open the app as the
  demo account and scroll the Home feed, Prayer, Marketplace and Watch for
  anything a reviewer could find offensive, and remove it.
- **Notifications.** The review device was a Mac. Push works there, but
  if the reviewer can't get a notification, the reply should explain that
  they arrive for messages, prayers and events from other members.
