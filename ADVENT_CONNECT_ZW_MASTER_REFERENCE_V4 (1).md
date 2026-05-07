# ADVENT CONNECT ZW — MASTER REFERENCE DOCUMENT
# Version 4.1 — Complete Planning Document
# Updated after full app design session — all decisions locked
# Use this file at the start of every new Claude Code session

---

## ⚠️ WHAT CHANGED FROM V4.0 TO V4.1

1. **Platform changed to Android AND iOS simultaneously** — Flutter builds both at once. Configure from Stage 1.
2. **iOS configuration added to Stage 1** — Info.plist, GoogleService-Info.plist, SafeArea on all scaffolds.
3. **Platform checks added** — flutter_windowmanager is Android only. Use Platform.isAndroid check.
4. **Two AdMob App IDs required** — One for Android, one for iOS. Both created in AdMob console.
5. **Two Firebase config files** — google-services.json (Android) + GoogleService-Info.plist (iOS).
6. **Sponsor arrangement documented** — Sponsor covers Google Play $25 + Apple Developer $99 + app icon once-off costs.
7. **Monthly cost responsibility documented** — Developer covers Claude Pro + Supabase Pro when needed.

## ⚠️ WHAT CHANGED FROM V3 TO V4

1. **All app tabs fully designed** — Churches, Events, Marketplace, Home, Profile, Messaging, Prayer, Directory, Notifications, AdMob all have complete specifications.
2. **Churches table expanded** — leader_role, location_status, meeting_venue_note, service times as structured fields, company vs church system, district field, admin roles.
3. **7-tap admin removed from Flutter app** — Admin access is web dashboard ONLY. Never inside the APK.
4. **New tables added** — conference_admins, admin_audit_log, urgent_banners, member_connections, company_registrations.
5. **Security plan complete** — All layers documented. flutter_secure_storage mandatory. Crashlytics added.
6. **Legal documents required** — Terms of Service and Privacy Policy must be hosted before Google Play submission.
7. **Onboarding flow designed** — 5 screens, 3-step profile setup.
8. **Monetisation roadmap added** — 5 stages from AdMob to conference partnerships.
9. **CSV church data cleaned** — 2,600 churches ready for import. 1 non-Zimbabwe record removed.
10. **Beta testing plan added** — 50 testers, 4 weeks, structured task list.

---

## PART 1 — PROJECT IDENTITY

- **App Name:** Advent Connect ZW
- **Developer:** Tanatswa Michael Mikuwa
- **Company:** MTech Studios ZW
- **Email:** mtechstudioszw@gmail.com
- **Phone:** +263 778 092 494
- **Purpose:** Zimbabwe's first dedicated digital platform for Seventh-day Adventists
- **Platform:** Flutter — Android AND iOS simultaneously
- **iOS Build Requirement:** Mac + Xcode required for iOS builds and App Store submission
- **Primary Market:** Android (90%+ Zimbabwe market share) — test Android first
- **Secondary Market:** iOS — diaspora users in UK, USA, South Africa, Australia
- **Backend:** Supabase Africa — Cape Town (free tier → Pro after 300 DAU)
- **Notifications:** Firebase Cloud Messaging (free)
- **Ads:** Google AdMob (banner ads only)
- **Font:** Poppins everywhere, no exceptions
- **Age Restriction:** 13+ minimum — enforced on signup

> ⚠️ SUPABASE REGION: Africa (Cape Town) ONLY.
> Zimbabwe is in Africa. Ireland adds ~10,000km round trip to every query.
> You CANNOT change region after project creation. Do this right on Day 1.

---

## PART 2 — COLOR SCHEME — NON-NEGOTIABLE

```dart
Primary Blue:   #1565C0  // Buttons, active states, highlights
Dark Navy:      #0D1B3E  // Headers, app bar, dark sections
White:          #FFFFFF  // Card backgrounds
Light Grey:     #F5F7FA  // Screen backgrounds
Text Dark:      #1A1A2E  // Body text
Gold Accent:    #C8A951  // Special highlights only — one element per screen MAX
Red:            #D32F2F  // Errors and urgent content ONLY
Success Green:  #2E7D32  // Status badges ONLY
```

**Color Rules — No exceptions:**
- NEVER use green as background color
- NEVER use pink in any shade
- NEVER use any color outside this scheme
- Red is for errors, obituary badges, urgent banners ONLY
- Gold is for verified badge, one highlight per screen maximum
- Green is for: online dot, RSVP going count, verified seller badge, biometric ON badge, approval status

---

## PART 3 — DESIGN RULES — NON-NEGOTIABLE

- Font: Poppins everywhere. Never substitute.
- Style: Minimalist, clean, premium. Think Shopify meets SDA community.
- All uploaded images: square via AspectRatio(1.0)
- Product cards: childAspectRatio 0.72 (portrait rectangle)
- Two-column grid for products (3-column if width > 600dp)
- Buttons: gradient primary blue, BorderRadius.circular(14)
- Cards: white with subtle shadow, BorderRadius.circular(16–20)
- Screen backgrounds: Light Grey #F5F7FA
- App bar: Dark Navy #0D1B3E with gradient
- Never leave the user guessing — always tell them what just happened
- No clutter — every element must earn its space

### PREMIUM UI TEST

Before finishing any screen ask: "Would someone look at this and assume a professional design team built it — or would they think an AI generated it in 5 minutes?" If the answer is AI — redesign it.

**Typography contrast:**
- Bold 700 for headings, Medium 500 for labels, Regular 400 for body
- Size contrast is dramatic — 28sp heading next to 13sp subtitle
- Never use the same font size twice in a row

**Spacing rhythm:**
- Sections breathe — 24px gap between sections
- Elements inside a section are tight — 8–12px between related items
- Padding is always 16 or 24 — never random numbers

**Micro details:**
- Shimmer loading states not spinners where possible
- Empty states always have an icon — never just text
- Success states feel satisfying — color change, checkmark animation
- Error messages are human and kind — never show raw Dart exceptions

**Specific UI patterns:**
- Pill-shaped filter chips not square buttons
- FABs with shadow
- Bottom sheets with drag handles
- Profile photos in circles with border
- Category cards with icon on colored background
- Gold verified badge — custom SDA-inspired
- Gradient app bars
- Status badges with rounded corners and colored background

### EMPTY STATES — MANDATORY ON EVERY LIST SCREEN

Every list screen must have a designed empty state with:
- Relevant icon or illustration
- Human friendly message
- Call to action button

Examples:
- No jobs yet: 💼 "No jobs posted yet. Be the first to post an opportunity." + [Post a Job] button
- No products: 🛍️ "No products listed yet. Know an SDA business owner? Tell them about us." + [Become a Seller] button
- No churches followed: 🏛️ "Follow your home church to see their announcements here." + [Find My Church] button

---

## PART 4 — TECHNICAL STACK

```
Framework:          Flutter Android
Backend:            Supabase Africa Cape Town
Auth:               Supabase Auth — email/password + Google Sign In
Biometric:          local_auth — fingerprint and face unlock
Push Notifications: Firebase Cloud Messaging
Analytics:          Firebase Analytics
Crash Reporting:    Firebase Crashlytics  ← NEW V4
Ads:                Google AdMob — banner ads only
Storage:            Supabase Storage
Local Storage:      SharedPreferences + flutter_secure_storage (tokens)
Navigation:         go_router
Realtime:           Supabase Realtime — messages, conversations, notifications ONLY
Font:               Google Fonts — Poppins
```

**CRITICAL — Token Storage:**
NEVER use SharedPreferences for auth tokens.
Use flutter_secure_storage — stores in Android Keystore (encrypted).
SharedPreferences is plain text and readable by malicious apps.

```dart
// WRONG — never do this
SharedPreferences.setString('token', token);

// RIGHT — always do this
FlutterSecureStorage().write(key: 'token', value: token);
```

---

## PART 5 — PUBSPEC.YAML — PINNED VERSIONS (V4 — AUTHORITATIVE)

```yaml
name: advent_connect_zw
description: Zimbabwe's SDA community app

publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # Backend
  supabase_flutter: ^2.5.0

  # Navigation
  go_router: ^13.2.0

  # UI & Fonts
  google_fonts: ^6.2.1
  shimmer: ^3.0.0
  cached_network_image: ^3.3.1

  # Auth
  google_sign_in: ^6.2.1
  local_auth: ^2.2.0

  # Firebase (NO firebase_auth — Supabase handles auth)
  firebase_core: ^2.30.1
  firebase_messaging: ^14.9.1
  firebase_analytics: ^10.10.5
  firebase_crashlytics: ^3.4.8    ← NEW V4
  flutter_local_notifications: ^17.1.2

  # Ads
  google_mobile_ads: ^5.1.0

  # Storage & Media
  image_picker: ^1.1.2
  image_cropper: ^7.1.0

  # Audio — Voice Notes
  record: ^5.1.2
  just_audio: ^0.9.40

  # Security
  flutter_secure_storage: ^9.0.0  ← NEW V4
  flutter_windowmanager: ^0.2.0   ← NEW V4 (screenshot prevention)

  # Utilities
  shared_preferences: ^2.2.3
  timeago: ^3.6.1
  intl: ^0.19.0
  url_launcher: ^6.3.0
  geolocator: ^12.0.0
  uuid: ^4.4.0
  connectivity_plus: ^6.0.3
  hive_flutter: ^1.1.0            ← NEW V4 (offline cache)

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
```

> NEVER use `latest` on any dependency.
> Do not add any package without checking for version conflicts first.
> firebase_auth is PERMANENTLY EXCLUDED — Supabase handles all auth.

---

## PART 6 — SUPABASE CONFIGURATION

```
Project Name:   adventconnect-zw
Region:         Africa (Cape Town)
Plan:           Free tier during development

Site URL:       io.supabase.adventconnectzw://login-callback/
Redirect URLs:
  io.supabase.adventconnectzw://login-callback/
  io.supabase.adventconnectzw://reset-callback/
```

**FREE TIER PROTECTION — DO THIS TODAY:**
1. Create account at uptimerobot.com
2. Add HTTP monitor pointing to your Supabase URL
3. Set interval to every 5 minutes
4. Set calendar reminder every Sunday to check Supabase dashboard

**Upgrade to Pro ($25/month) when:**
- Approaching 300 DAU
- Storage over 800MB
- API requests over 400,000/month

---

## PART 7 — NAVIGATION — 5 TABS — ALWAYS VISIBLE

| Tab | Icon | Purpose |
|-----|------|---------|
| Home | House | Daily feed, notices, events, marketplace preview |
| Churches | Church | Full church directory and profiles |
| Events | Calendar | SDA events calendar for Zimbabwe |
| Marketplace | Bag | Shop and Jobs combined |
| Profile | Person | Account, settings, conversations |

**Navigation Rules:**
- Bottom nav NEVER disappears on any screen
- Each tab has its own navigation stack via go_router ShellRoute
- All navigation uses go_router named routes — no MaterialPageRoute anywhere
- Deep links from WhatsApp must open the correct screen via go_router

---

## PART 8 — ACCOUNT TYPES

### Type 1 — Basic Member
Default for every new signup.
Can: browse, follow churches, RSVP, post prayers, message sellers, post jobs, report content, send message requests.

### Type 2 — Seller Account
Tap Become a Seller → store form → admin approves → seller dashboard unlocked.

### Type 3 — Church Admin (Two Levels)
**Primary Admin** — Full control. Can add/remove other admins. One per church maximum.
**Standard Admin** — Can post content (announcements, events). Cannot change profile or manage other admins.

Process: In-app form → name, phone, role, appointment letter photo → admin queue → verify via WhatsApp → approve.

**Pastor Transfer Flow:**
When primary admin leaves — primary admin transfers ownership to another approved admin. If no primary admin for 90 days → church profile enters maintenance mode → you are notified.

### Type 4 — App Admin (You Only)
Access ONLY via web dashboard. Never inside the Flutter app.
Admin account marked as `super_admin` in database.
In-app behaviour: posts auto-approved, can post urgent banners. No special screens inside Flutter.

> ⚠️ CRITICAL: The 7-tap secret admin screen has been PERMANENTLY REMOVED from V4.
> Admin access is via web dashboard ONLY. APK contains zero admin functionality.
> Anyone can decompile the APK. The admin panel must never be inside it.

---

## PART 9 — COMPLETE SCREEN LIST — 53 SCREENS

### Auth (9)
```
splash_screen.dart
onboarding_screen.dart          ← 3 slides + account choice
login_screen.dart
signup_screen.dart              ← includes age verification (13+)
email_verification_screen.dart
profile_setup_screen.dart       ← Step 1: name + photo
profile_setup_church_screen.dart ← Step 2: home church selection
forgot_password_screen.dart
reset_password_screen.dart
```

### Home Tab (3)
```
home_screen.dart
search_screen.dart
post_notice_screen.dart
```

### Churches Tab (6)
```
churches_screen.dart
church_profile_screen.dart
suggest_edit_screen.dart
church_announcements_screen.dart
claim_church_screen.dart
suggest_church_screen.dart
```

### Events Tab (3)
```
events_screen.dart
event_detail_screen.dart
post_event_screen.dart
```

### Marketplace Tab (8)
```
marketplace_screen.dart
shop_screen.dart
category_screen.dart
listing_detail_screen.dart
seller_profile_screen.dart
jobs_screen.dart
job_detail_screen.dart
post_job_screen.dart
```

### Profile Tab (14)
```
profile_screen.dart
edit_profile_screen.dart
my_conversations_screen.dart
chat_screen.dart
my_events_screen.dart
saved_listings_screen.dart
prayer_requests_screen.dart
post_prayer_screen.dart
member_directory_screen.dart
my_directory_profile_screen.dart
settings_screen.dart
notification_preferences_screen.dart
sabbath_timer_screen.dart
blocked_users_screen.dart
```

### Seller Screens (5)
```
seller_dashboard_screen.dart
setup_store_screen.dart
add_product_screen.dart
manage_products_screen.dart
edit_store_screen.dart
```

### Admin Screens (3)
```
admin_login_screen.dart         ← NOTE: This is for church admins only
admin_dashboard_screen.dart     ← Church admin dashboard — NOT app admin
pending_approvals_screen.dart   ← Church admin view of pending content
```

> App-level admin (you) uses the WEB DASHBOARD only — not these screens.
> These screens are for church admins managing their own church.

### Utility Screens (3)
```
offline_screen.dart
report_submitted_screen.dart
terms_privacy_screen.dart
```

---

## PART 10 — FILE STRUCTURE

```
lib/
├── main.dart
├── config/
│   ├── supabase_config.dart
│   └── router_config.dart
├── theme/
│   ├── app_colors.dart
│   ├── app_text_styles.dart
│   └── app_theme.dart
├── services/
│   ├── auth_service.dart
│   ├── biometric_service.dart
│   ├── message_service.dart
│   ├── notification_service.dart
│   ├── analytics_service.dart
│   ├── connectivity_service.dart
│   ├── report_service.dart
│   ├── share_service.dart
│   ├── audio_service.dart
│   ├── storage_service.dart
│   ├── cache_service.dart          ← NEW V4: offline caching
│   └── secure_storage_service.dart ← NEW V4: token management
├── models/
│   ├── profile.dart
│   ├── church.dart
│   ├── announcement.dart
│   ├── event.dart
│   ├── seller.dart
│   ├── product.dart
│   ├── job_post.dart
│   ├── conversation.dart
│   ├── message.dart
│   ├── prayer_request.dart
│   ├── notice.dart
│   ├── report.dart
│   └── urgent_banner.dart          ← NEW V4
└── screens/
    ├── auth/
    ├── home/
    ├── churches/
    ├── events/
    ├── marketplace/
    ├── profile/
    ├── seller/
    ├── admin/
    └── shared/
```

---

## PART 11 — DATABASE TABLES (31 TABLES — V4 EXPANDED)

### Table 1: profiles
```sql
id                    UUID PRIMARY KEY REFERENCES auth.users(id)
created_at            TIMESTAMPTZ DEFAULT NOW()
full_name             TEXT
username              TEXT UNIQUE
profile_photo_url     TEXT
province              TEXT
city                  TEXT
home_church_id        BIGINT REFERENCES churches(id)
account_type          TEXT DEFAULT 'member'
  -- 'member' / 'seller' / 'church_admin' / 'super_admin'
biometric_enabled     BOOLEAN DEFAULT FALSE
is_verified           BOOLEAN DEFAULT FALSE
is_banned             BOOLEAN DEFAULT FALSE
banned_reason         TEXT
fcm_token             TEXT
last_active_at        TIMESTAMPTZ DEFAULT NOW()
language_preference   TEXT DEFAULT 'english'
  -- 'english' / 'shona' / 'ndebele'
is_discoverable       BOOLEAN DEFAULT TRUE
show_online_status    BOOLEAN DEFAULT FALSE
date_of_birth         DATE
  -- Required. Under 13 blocked at signup.
```

### Table 2: churches
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
name                  TEXT NOT NULL
district              TEXT
  -- e.g. "Bikita North" extracted from "Bikita North - Chikuku"
conference            TEXT
  -- Full name e.g. "North Zimbabwe Conference"
conference_code       TEXT
  -- Short code e.g. "NZC"
province              TEXT
city                  TEXT
suburb                TEXT
address               TEXT
latitude              DECIMAL
  -- NULL = no GPS. App shows "no location" badge.
longitude             DECIMAL
phone                 TEXT
email                 TEXT
website               TEXT
whatsapp_group_link   TEXT          ← NEW V4
facebook_page_url     TEXT          ← NEW V4

-- Leadership (replaces pastor_name/pastor_phone)
leader_name           TEXT          ← NEW V4
leader_role           TEXT          ← NEW V4
  -- 'Pastor' / 'Local Elder' / 'District Pastor' / 'Acting Elder'
leader_phone          TEXT          ← NEW V4
district_pastor_name  TEXT          ← NEW V4
district_pastor_phone TEXT          ← NEW V4

-- Service times (structured — not plain text)
sabbath_school_time   TEXT          ← NEW V4 e.g. "09:00"
main_service_time     TEXT          ← NEW V4 e.g. "11:00"
afternoon_service_time TEXT         ← NEW V4 optional
friday_fellowship_time TEXT         ← NEW V4 optional
service_language      TEXT          ← NEW V4 e.g. "Shona / English"

-- Location handling
location_status       TEXT DEFAULT 'has_building'  ← NEW V4
  -- 'has_building'    → show map normally
  -- 'meets_at_venue'  → show venue note instead of map
  -- 'no_fixed_venue'  → show "contact church for location"
  -- 'unconfirmed'     → show warning banner
  -- 'inactive'        → grey out with notice
meeting_venue_note    TEXT          ← NEW V4
  -- e.g. "Meets at Dzivarasekwa Primary School Hall"
venue_is_permanent    BOOLEAN DEFAULT TRUE  ← NEW V4

-- Entity type (church vs company)
entity_type           TEXT DEFAULT 'church'  ← NEW V4
  -- 'church'   → official organised SDA church
  -- 'company'  → unorganised congregation working toward church status

-- Company fields (only used when entity_type = 'company')
company_founded_date  DATE          ← NEW V4 self-reported, max 11 months old
company_registered_by UUID REFERENCES profiles(id)  ← NEW V4
auto_eligible_at      DATE          ← NEW V4 calculated: founded_date + 365 days
organised_date        DATE          ← NEW V4 filled when you approve as church

-- Existing fields
profile_photo_url     TEXT
banner_url            TEXT
follower_count        INTEGER DEFAULT 0
is_verified           BOOLEAN DEFAULT FALSE
is_claimed            BOOLEAN DEFAULT FALSE
status                TEXT DEFAULT 'active'
  -- 'active' / 'company_new' / 'company_eligible' / 'pending_official'
  -- 'inactive' / 'merged' / 'relocated' / 'unconfirmed'
```

### Table 3: church_followers
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
church_id             BIGINT REFERENCES churches(id)
user_id               UUID REFERENCES profiles(id)
UNIQUE(church_id, user_id)
```

### Table 4: church_admins
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
church_id             BIGINT REFERENCES churches(id)
user_id               UUID REFERENCES profiles(id)
role                  TEXT
  -- 'primary'   → full control, can manage other admins (one per church)
  -- 'standard'  → can post content only
appointment_letter_url TEXT
status                TEXT DEFAULT 'pending'
rejection_reason      TEXT
approved_at           TIMESTAMPTZ
UNIQUE(church_id, user_id)
```

### Table 5: church_edit_suggestions
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
church_id             BIGINT REFERENCES churches(id)
suggested_by          UUID REFERENCES profiles(id)
field_name            TEXT
current_value         TEXT
suggested_value       TEXT
status                TEXT DEFAULT 'pending'
```

### Table 6: announcements
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
church_id             BIGINT REFERENCES churches(id)
posted_by             UUID REFERENCES profiles(id)
title                 TEXT NOT NULL
body                  TEXT NOT NULL
category              TEXT
  -- 'general' / 'urgent' / 'obituary' / 'event' / 'program'
is_pinned             BOOLEAN DEFAULT FALSE
publish_at            TIMESTAMPTZ
expires_at            TIMESTAMPTZ
view_count            INTEGER DEFAULT 0
is_broadcast          BOOLEAN DEFAULT FALSE  ← NEW V4
  -- TRUE = delivered directly to followers' message inbox
```

### Table 7: church_suggestions
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
suggested_by          UUID REFERENCES profiles(id)
church_name           TEXT NOT NULL
province              TEXT
city                  TEXT
suburb                TEXT
pastor_name           TEXT
contact_phone         TEXT
status                TEXT DEFAULT 'pending'
```

### Table 8: events
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
posted_by             UUID REFERENCES profiles(id)
church_id             BIGINT REFERENCES churches(id)
title                 TEXT NOT NULL
description           TEXT
start_date            DATE NOT NULL
end_date              DATE
start_time            TEXT
end_time              TEXT
province              TEXT
city                  TEXT
venue                 TEXT
address               TEXT
flyer_url             TEXT
category              TEXT
  -- 'camp_meeting'/'youth'/'concert'/'graduation'/'week_of_prayer'/'other'
contact_name          TEXT
contact_phone         TEXT
capacity              INTEGER
status                TEXT DEFAULT 'pending'
rejection_reason      TEXT
rsvp_count            INTEGER DEFAULT 0
event_source          TEXT DEFAULT 'community'  ← NEW V4
  -- 'church'     → posted by church admin, auto-approved
  -- 'community'  → posted by member, needs review
stream_link           TEXT  ← NEW V4 Zoom/YouTube link for online events
is_online             BOOLEAN DEFAULT FALSE  ← NEW V4
is_recurring          BOOLEAN DEFAULT FALSE  ← NEW V4
recurrence_interval   TEXT  ← NEW V4 e.g. 'yearly'
```

### Table 9: event_rsvps
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
event_id              BIGINT REFERENCES events(id)
user_id               UUID REFERENCES profiles(id)
status                TEXT  -- 'going' / 'interested' / 'not_going'
UNIQUE(event_id, user_id)
```

### Table 10: sellers
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
auth_user_id          UUID REFERENCES profiles(id)
business_name         TEXT NOT NULL
category              TEXT NOT NULL
description           TEXT
province              TEXT
city                  TEXT
suburb                TEXT
address               TEXT
phone                 TEXT NOT NULL
whatsapp              TEXT
contact_name          TEXT
profile_photo_url     TEXT
payment_methods       TEXT
offers_delivery       BOOLEAN DEFAULT FALSE
delivery_area         TEXT
delivery_fee          TEXT
status                TEXT DEFAULT 'pending'
rejection_reason      TEXT
verified              BOOLEAN DEFAULT FALSE
sda_verified          BOOLEAN DEFAULT FALSE
featured              BOOLEAN DEFAULT FALSE
rating                DECIMAL DEFAULT 0
rating_count          INTEGER DEFAULT 0
is_active             BOOLEAN DEFAULT TRUE
approved_at           TIMESTAMPTZ
observes_sabbath      BOOLEAN DEFAULT FALSE  ← NEW V4
sabbath_notice_text   TEXT  ← NEW V4
```

### Table 11: products
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
seller_id             BIGINT REFERENCES sellers(id)
auth_user_id          UUID REFERENCES profiles(id)
category              TEXT NOT NULL
subcategory           TEXT
name                  TEXT NOT NULL
description           TEXT
price_amount          DECIMAL NOT NULL CHECK (price_amount > 0)  ← CHANGED V4
price_currency        TEXT DEFAULT 'USD'  ← NEW V4
price_display         TEXT  ← NEW V4 e.g. "USD 50.00"
photo_urls            TEXT[] DEFAULT '{}'
available             BOOLEAN DEFAULT TRUE
is_featured           BOOLEAN DEFAULT FALSE  ← NEW V4
featured_until        TIMESTAMPTZ  ← NEW V4
featured_paid_at      TIMESTAMPTZ  ← NEW V4
view_count            INTEGER DEFAULT 0
```

### Table 12: seller_ratings
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
seller_id             BIGINT REFERENCES sellers(id)
rated_by              UUID REFERENCES profiles(id)
rating                INTEGER CHECK (rating BETWEEN 1 AND 5)
review_text           TEXT
UNIQUE(seller_id, rated_by)
```

### Table 13: saved_listings
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
user_id               UUID REFERENCES profiles(id)
product_id            BIGINT REFERENCES products(id)
UNIQUE(user_id, product_id)
```

### Table 14: job_posts
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
posted_by             UUID REFERENCES profiles(id)
post_type             TEXT NOT NULL  -- 'seeking' / 'hiring'
job_category          TEXT NOT NULL
  -- 'teaching_education' / 'healthcare' / 'construction_trades'
  -- 'farming_agriculture' / 'driving_transport' / 'domestic_caregiving'
  -- 'business_admin' / 'it_technology' / 'ministry_church' / 'other'
job_title             TEXT NOT NULL
description           TEXT NOT NULL
first_name            TEXT NOT NULL
business_name         TEXT
city                  TEXT NOT NULL
province              TEXT NOT NULL
sabbath_friendly      BOOLEAN DEFAULT FALSE
is_sda_institution    BOOLEAN DEFAULT FALSE  ← NEW V4
is_active             BOOLEAN DEFAULT TRUE
is_filled             BOOLEAN DEFAULT FALSE
expires_at            TIMESTAMPTZ
  -- Auto set to 30 days from posting. Renewable by poster.
phone                 TEXT
full_name             TEXT
email                 TEXT
```

### Table 15: conversations
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
participant_one_id    UUID REFERENCES profiles(id)
participant_two_id    UUID REFERENCES profiles(id)
listing_id            BIGINT REFERENCES products(id)
job_post_id           BIGINT REFERENCES job_posts(id)
conversation_source   TEXT DEFAULT 'direct'  ← NEW V4
  -- 'marketplace' / 'job' / 'message_request' / 'prayer_support'
last_message_text     TEXT
last_message_at       TIMESTAMPTZ
last_message_by       UUID REFERENCES profiles(id)
participant_one_unread INTEGER DEFAULT 0
participant_two_unread INTEGER DEFAULT 0
participant_one_typing BOOLEAN DEFAULT FALSE  ← NEW V4
participant_two_typing BOOLEAN DEFAULT FALSE  ← NEW V4
typing_updated_at     TIMESTAMPTZ  ← NEW V4
contacts_shared       BOOLEAN DEFAULT FALSE
participant_one_archived BOOLEAN DEFAULT FALSE
participant_two_archived BOOLEAN DEFAULT FALSE
```

### Table 16: messages
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
conversation_id       BIGINT REFERENCES conversations(id)
sender_id             UUID REFERENCES profiles(id)
message_text          TEXT CHECK (char_length(message_text) <= 1000)
message_type          TEXT DEFAULT 'text'  -- 'text' / 'voice' / 'system'
audio_url             TEXT
audio_duration_seconds INTEGER
is_read               BOOLEAN DEFAULT FALSE
is_delivered          BOOLEAN DEFAULT FALSE
is_system_message     BOOLEAN DEFAULT FALSE
is_deleted_for_sender BOOLEAN DEFAULT FALSE  ← NEW V4
is_deleted_for_all    BOOLEAN DEFAULT FALSE  ← NEW V4
deleted_at            TIMESTAMPTZ  ← NEW V4
```

### Table 17: contact_requests
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
conversation_id       BIGINT REFERENCES conversations(id)
requester_id          UUID REFERENCES profiles(id)
recipient_id          UUID REFERENCES profiles(id)
status                TEXT DEFAULT 'pending'
responded_at          TIMESTAMPTZ
```

### Table 18: member_connections (NEW V4)
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
requester_id          UUID REFERENCES profiles(id)
recipient_id          UUID REFERENCES profiles(id)
status                TEXT DEFAULT 'pending'
  -- 'pending' / 'accepted' / 'declined'
intro_message         TEXT  -- max 100 characters
responded_at          TIMESTAMPTZ
```

### Table 19: prayer_requests
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
posted_by             UUID REFERENCES profiles(id)
title                 TEXT NOT NULL
body                  TEXT NOT NULL
visibility            TEXT DEFAULT 'public'
  -- 'public' / 'church_only' / 'anonymous'
church_id             BIGINT REFERENCES churches(id)
prayer_count          INTEGER DEFAULT 0
is_answered           BOOLEAN DEFAULT FALSE
expires_at            TIMESTAMPTZ  ← NEW V4 auto 30 days, renewable
is_urgent             BOOLEAN DEFAULT FALSE  ← NEW V4
```

### Table 20: prayer_responses
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
prayer_id             BIGINT REFERENCES prayer_requests(id)
user_id               UUID REFERENCES profiles(id)
response_type         TEXT  -- 'praying' / 'message'
message               TEXT
```

### Table 21: member_directory
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
user_id               UUID REFERENCES profiles(id)
profession            TEXT
skills                TEXT
church_id             BIGINT REFERENCES churches(id)
province              TEXT
city                  TEXT
bio                   TEXT
is_visible            BOOLEAN DEFAULT TRUE
```

### Table 22: notification_preferences
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
user_id               UUID REFERENCES profiles(id)
church_id             BIGINT REFERENCES churches(id)
all_notifications     BOOLEAN DEFAULT TRUE
urgent_only           BOOLEAN DEFAULT FALSE
none                  BOOLEAN DEFAULT FALSE
UNIQUE(user_id, church_id)
```

### Table 23: notifications
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
user_id               UUID REFERENCES profiles(id)
title                 TEXT NOT NULL
body                  TEXT NOT NULL
type                  TEXT
reference_id          BIGINT
reference_type        TEXT
is_read               BOOLEAN DEFAULT FALSE
```

### Table 24: urgent_banners (NEW V4)
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
posted_by             UUID REFERENCES profiles(id)
  -- Must be super_admin or conference_admin only
conference            TEXT
  -- NULL = nationwide. Conference code = conference specific.
title                 TEXT NOT NULL  -- max 60 characters
body                  TEXT NOT NULL  -- max 200 characters
is_active             BOOLEAN DEFAULT TRUE
expires_at            TIMESTAMPTZ
  -- Auto expires 48 hours after posting
deactivated_at        TIMESTAMPTZ
deactivated_by        UUID REFERENCES profiles(id)
```

### Table 25: reports
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
reported_by           UUID REFERENCES profiles(id)
content_type          TEXT
content_id            BIGINT
reason                TEXT NOT NULL
details               TEXT
status                TEXT DEFAULT 'pending'
reviewed_by           UUID REFERENCES profiles(id)
reviewed_at           TIMESTAMPTZ
action_taken          TEXT
```

### Table 26: blocked_users
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
blocker_id            UUID REFERENCES profiles(id)
blocked_id            UUID REFERENCES profiles(id)
UNIQUE(blocker_id, blocked_id)
```

### Table 27: notices
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
posted_by             UUID REFERENCES profiles(id)
title                 TEXT NOT NULL
body                  TEXT NOT NULL
category              TEXT
  -- 'general' / 'lost_and_found' / 'accommodation' / 'transport'
  -- 'congratulations' / 'other'
province              TEXT
city                  TEXT
contact_phone         TEXT
image_url             TEXT
is_approved           BOOLEAN DEFAULT FALSE
expires_at            TIMESTAMPTZ  -- auto 30 days
```

### Table 28: image_uploads
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
uploaded_by           UUID REFERENCES profiles(id)
storage_path          TEXT NOT NULL
file_size_bytes       INTEGER NOT NULL
content_type          TEXT NOT NULL
purpose               TEXT
```

### Table 29: rate_limits
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
user_id               UUID REFERENCES profiles(id)
action_type           TEXT NOT NULL
last_action_at        TIMESTAMPTZ DEFAULT NOW()
action_count_today    INTEGER DEFAULT 1
UNIQUE(user_id, action_type)
```

### Table 30: conference_admins (NEW V4)
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
user_id               UUID REFERENCES profiles(id)
conference            TEXT NOT NULL
  -- Conference code e.g. 'NZC'
role                  TEXT NOT NULL
  -- 'super_admin' / 'conference_admin' / 'district_admin'
is_active             BOOLEAN DEFAULT TRUE
last_login            TIMESTAMPTZ
created_by            UUID REFERENCES profiles(id)
  -- Who granted this access
```

### Table 31: admin_audit_log (NEW V4)
```sql
id                    BIGSERIAL PRIMARY KEY
created_at            TIMESTAMPTZ DEFAULT NOW()
admin_id              UUID REFERENCES profiles(id)
action_type           TEXT NOT NULL
  -- 'approved_church' / 'banned_user' / 'rejected_seller'
  -- 'approved_event' / 'removed_content' / 'approved_church_admin'
target_id             BIGINT
target_type           TEXT
  -- 'church' / 'user' / 'seller' / 'event' / 'announcement'
old_value             TEXT
new_value             TEXT
ip_address            TEXT
device_info           TEXT
```

---

## PART 12 — RLS POLICIES

> All policies from V3 remain unchanged.
> New tables added below.

### profiles, churches, events, sellers, products, messages, conversations
[All V3 policies unchanged — refer to V3 for these]

### urgent_banners (NEW)
```sql
-- Anyone authenticated can read active banners
CREATE POLICY "banners_select" ON urgent_banners
  FOR SELECT USING (is_active = true AND auth.role() = 'authenticated');
-- Only super_admin inserts — enforced via Edge Function
CREATE POLICY "banners_insert" ON urgent_banners
  FOR INSERT WITH CHECK (false);
```

### member_connections (NEW)
```sql
CREATE POLICY "connections_select" ON member_connections
  FOR SELECT USING (auth.uid() = requester_id OR auth.uid() = recipient_id);
CREATE POLICY "connections_insert" ON member_connections
  FOR INSERT WITH CHECK (auth.uid() = requester_id);
CREATE POLICY "connections_update" ON member_connections
  FOR UPDATE USING (auth.uid() = recipient_id);
```

### conference_admins (NEW)
```sql
-- Conference admins read their own record only
CREATE POLICY "conf_admin_select" ON conference_admins
  FOR SELECT USING (auth.uid() = user_id);
-- No inserts from Flutter — web dashboard only via service role
CREATE POLICY "conf_admin_insert" ON conference_admins
  FOR INSERT WITH CHECK (false);
```

### admin_audit_log (NEW)
```sql
-- No reads from Flutter — web dashboard only
CREATE POLICY "audit_select" ON admin_audit_log
  FOR SELECT USING (false);
-- Inserts via service role only
CREATE POLICY "audit_insert" ON admin_audit_log
  FOR INSERT WITH CHECK (false);
```

---

## PART 13 — REALTIME

Enable Realtime on THESE TABLES ONLY:
- **messages** — chat delivery
- **conversations** — typing indicators, unread counts
- **notifications** — in-app notification bell

Do NOT enable Realtime on all tables.

---

## PART 14 — STORAGE BUCKETS

| Bucket | Access | Max Size |
|--------|--------|---------|
| profile_photos | Public read | 500KB |
| church_photos | Public read | 800KB |
| product_photos | Public read | 600KB |
| appointment_letters | **Private** | 2MB |
| voice_notes | **Private** | 10MB |
| event_flyers | Public read | 1MB |

**File type validation — server side:**
- Images: jpg, jpeg, png, webp ONLY
- Documents: pdf ONLY
- Audio: m4a, mp3, aac ONLY
- Reject anything else before it reaches storage

**Image compression before upload (client side):**
Use image_cropper to compress on device before uploading.
Never upload raw camera photos — they can be 10MB+.

---

## PART 15 — CHURCHES TAB COMPLETE SPECIFICATION

### Church Discovery Flow
1. User opens Churches tab
2. App requests location permission via geolocator
3. If allowed: churches sorted nearest first with distance shown
4. If denied: churches sorted alphabetically, soft banner to enable location

### Churches Screen Layout
- Search bar at top
- Filter chips: `All` `Nearby` `Verified` `My Province`
- Conference filter dropdown
- Church cards in list

### Church Card Shows
- Church photo or placeholder
- Church name (bold)
- Suburb, City, Province
- Distance if GPS available
- Verified badge if claimed
- Follower count
- Latest announcement preview (obituaries shown with red badge)

### Church Profile Screen
**If GPS coordinates exist:**
- Static map preview + "Get Directions" button
- Distance from user

**If no GPS (location_status = 'meets_at_venue'):**
- No map shown
- "📍 Meets at [meeting_venue_note]"
- "Get Directions" opens Google Maps with text address

**If location_status = 'unconfirmed':**
- Warning banner: "This congregation may have relocated. Verify before visiting."

**If location_status = 'inactive':**
- Grey profile with notice: "This congregation is no longer active."

### Church Profile Sections
1. Header — banner, photo, name, badge, follower count, Follow button
2. Service Times — structured fields
3. Leadership — leader_role + leader_name + district_pastor if exists
4. Contact — phone, email, WhatsApp group link
5. Announcements — 5 most recent, obituaries first, pinned second
6. "View All Announcements" button

### Unclaimed Church Banner
"Is this your church? Tap to become the official admin" → claim_church_screen

### Church Admin Powers (Once Approved)
**Primary Admin:**
- Full profile management — photos, times, contacts, leader info
- Post all content types
- Add and remove standard admins
- Transfer primary admin role

**Standard Admin:**
- Post announcements, events, obituaries
- Cannot change profile or manage other admins

### Company Registration
- entity_type = 'company' during registration
- Founded date required — maximum 11 months old at registration
- App shows countdown to 1-year eligibility
- At 1 year: status changes to 'company_eligible' automatically
- You get notified → verify with Conference → approve manually
- Only you can upgrade company to official_church status

### Church Size Handling
Rural churches, school congregations, churches with no building:
- Use location_status field to control profile rendering
- Never show broken map for churches with no coordinates
- Always show meeting_venue_note if location_status = 'meets_at_venue'

---

## PART 16 — HOME TAB COMPLETE SPECIFICATION

### Feed Structure — Option C (Personalised + Zimbabwe Wide)

**Section 0 — Urgent Banner (if active)**
Full width red banner at very top. Cannot be dismissed until Read More tapped.
Only super_admin or conference_admin can post. Auto-expires 48 hours.

**Top Bar**
- App logo left
- Search icon right
- Notification bell right with unread count badge

**Greeting**
- "Good morning, [first name]"
- Today's date
- Sabbath countdown if user has enabled it in Settings

**Quick Actions Strip**
Horizontal scrollable pill chips:
[ Post Notice ] [ Find Church ] [ Post Event ] [ Find Job ]

**Section 1 — Your Churches**
Content from followed churches. Chronological.
If no churches followed: "Follow your home church to see their announcements here" + [Find My Church] button

**Section 2 — Latest Products**
Horizontal scroll of 5 newest marketplace products
"See all →" link to Shop

**Section 3 — Latest Jobs**
3 most recent job cards
"See all →" link to Jobs

**Section 4 — From Around Zimbabwe**
Mixed content — events, notices, prayers, new churches nationwide

**Bottom**
Google AdMob banner

### Content Type Badges
| Type | Badge | Colour |
|------|-------|--------|
| Obituary | 🖤 Obituary | Red |
| Urgent | 🔴 Urgent | Red |
| Event | 📅 Event | Blue |
| Announcement | 📢 Notice | Navy |
| Job | 💼 Job | Navy |
| Product | 🛍️ Product | Blue |
| Prayer | 🙏 Prayer | Navy |
| New Church | 🏛️ Directory | Gold |

### Sabbath Countdown
Off by default. User enables in Settings → Preferences.
When enabled: shows in greeting area.
Auto-calculates Friday sundown based on user's province.

### Notice Categories for post_notice_screen
- General community notice
- Lost and found
- Accommodation needed or available
- Transport sharing
- Congratulations — births, graduations, marriages
- Other

---

## PART 17 — EVENTS TAB COMPLETE SPECIFICATION

### Who Can Post Events
**Church admins:** Auto-approved. Appears immediately with verified church badge.
**Regular members:** Goes to your admin review queue. Appears with community badge after approval.

```sql
event_source TEXT DEFAULT 'community'
-- 'church'     → auto-approved
-- 'community'  → needs your review
```

### Event Cards Visual Difference
**Church event:** Church profile photo + church name + ✅ Verified Church Event
**Community event:** Member profile photo + member name + 🌐 Community Event

### Event Features
- RSVP requires login — no anonymous RSVPs
- Event reminder notifications — 24 hours before for RSVPd members
- Online events — stream_link field for Zoom/YouTube
- Recurring events — nudge system (not auto-repost) for annual events
- Flyer image upload

### Recurring Event Nudge
When annual event date passes:
System sends notification to church admin:
"Camp Meeting 2025 has ended. Post Camp Meeting 2026?"
Pre-fills form with previous year's details. Admin updates dates and reposts.

### RSVP Options
- Going (counted in rsvp_count)
- Interested
- Not going

---

## PART 18 — MARKETPLACE TAB COMPLETE SPECIFICATION

### Layout
Toggle at top of Marketplace screen: **[ Shop ] [ Jobs ]**

### Shop Features
- Two-column product grid (three columns if width > 600dp)
- Filter by category, province, price
- Saved listings (heart icon on product cards)
- Contact seller opens WhatsApp with pre-filled message:
  "Hi, I saw your [product name] on Advent Connect ZW. Is it still available?"
- No cart — saved listings serve this purpose
- No payments — all transactions happen outside the app

### Seller Sabbath Observance
Optional badge on seller profile:
"🕊️ This seller observes the Sabbath. Response times may be slower Friday sundown to Saturday sundown."
Buyer sees soft warning before opening WhatsApp during Sabbath hours.
Buyer can disable this warning in Settings.

### Jobs Board Features
- Toggle between Hiring and Seeking posts
- Visual difference on cards:
  - Hiring: 🏢 Hiring — [title] — [business] · [city]
  - Seeking: 👤 Seeking — [skill] — Available in [city]
- Sabbath Friendly filter — prominent, not hidden
- SDA Institution tag for Solusi, Maranatha, SDA clinics
- Jobs auto-expire after 30 days
- Poster gets notification 3 days before expiry: "Still relevant? Renew for 30 more days"
- "Mark as Filled" button — weekly reminder if not marked

### Job Categories
teaching_education / healthcare / construction_trades /
farming_agriculture / driving_transport / domestic_caregiving /
business_admin / it_technology / ministry_church / other

### No CV Uploads
Contact via WhatsApp or phone directly. Consistent with marketplace approach.

---

## PART 19 — PROFILE TAB COMPLETE SPECIFICATION

### Profile Screen — Option B (Activity Dashboard)

**Top Section — Identity Card**
- Profile photo — circle with gold border if verified
- Full name (bold)
- Username (@handle)
- Home church name (tappable)
- Province and city
- Member since date
- Account type badge
- Profile completion progress bar with next step hint

**Quick Stats Strip**
| Churches Followed | Events RSVPd | Prayers Posted | Products Saved |
Tapping each number navigates directly to that list.

**Action Buttons**
[ Edit Profile ] [ Share Profile ]
Share generates WhatsApp shareable link.

**Account Management Section**
- Become a Seller (if not already)
- Claim a Church (if not already church admin)
- My Seller Dashboard (if approved seller)
- My Church Dashboard (if approved church admin)

### Settings Screen Sections
**Account:** Edit profile, change password, change email, 2FA optional, biometric toggle, delete account (bottom, red)

**Preferences:** Sabbath countdown on/off, Sabbath marketplace warning on/off, language (English/Shona/Ndebele), province filter, online status on/off (default off)

**Notifications:** Per church settings, global notification preferences

**Privacy:** Show in member directory, who can message me (Everyone/Members only), block list

**About:** App version, terms, privacy policy, contact support (WhatsApp), rate app (Google Play)

> ⚠️ NO 7-TAP ADMIN ACCESS IN SETTINGS. PERMANENTLY REMOVED.

### Delete Account Flow
Settings → Delete Account
→ Warning: full consequences explained
→ Type "DELETE" to confirm
→ Final confirmation
→ RPC deletes account
→ Logged out immediately
→ Confirmation email sent

Data kept after deletion: reports filed (legal), audit logs (legal)
Data deleted: profile, messages, products, prayer requests

---

## PART 20 — MESSAGING COMPLETE SPECIFICATION

### Conversation Starting Rules

| Scenario | How Conversation Starts | Request Needed |
|----------|------------------------|----------------|
| Buyer contacts seller | Tap "Contact Seller" on product | ❌ Opens immediately |
| Job enquiry | Tap "Contact" on job post | ❌ Opens immediately |
| Member to member | Tap "Send Message Request" on profile | ✅ Recipient must accept |
| Prayer support | Tap "Send Private Support" on prayer | ✅ Recipient must accept |
| Directory connection | Tap "Send Message Request" on directory profile | ✅ Recipient must accept |

### Message Request Flow
1. Tap "Send Message Request"
2. Write intro — max 100 characters
3. Request appears in recipient's notifications
4. Recipient sees: name, photo, intro message, [Accept] [Decline] [Block]
5. If accepted: conversation opens
6. If declined: requester sees "Request not accepted" — no reason given
7. After decline: requester cannot send another request to same person

### Anti-Abuse Rules
- New accounts (under 24 hours old) cannot send any messages or requests
- Maximum 10 message requests per day per user
- Maximum 30 messages per hour per conversation
- Maximum 10 new conversations started per day per user
- Blocked users cannot send requests — ever

### Chat Screen Features
- Real-time delivery via Supabase Realtime
- Text messages — max 1,000 characters
- Voice notes — max 60 seconds
- Typing indicator — "James is typing..."
- Read receipts (✓ sent, ✓✓ delivered, blue ✓✓ read)
- Message deletion:
  - Delete for me: anytime
  - Delete for everyone: within 5 minutes of sending only
  - Deleted shows: "This message was deleted"
  - Never truly deleted from database — kept for moderation

### Conversation Context Tag
Every conversation shows at top what started it:
- "Started from: Wooden Chair listing"
- "Started from: Teaching Job post"
- "Started from: Message request"

### Conversations List
- Profile photo of other person
- Name
- Last message preview (1 line)
- Time of last message
- Unread count badge
- Context tag
- Swipe left: Archive
- Swipe right: Mark as read
- Long press: Archive / Delete / Block / Report

### Church Broadcast Channel
Church admins can send one-way broadcast to all church followers.
Maximum 3 broadcasts per day per church.
Members receive in their conversations list.
Members can read but cannot reply.
Members can mute channel without unfollowing church.

### Online Status
Default: OFF
User enables in Settings → Privacy → "Show my online status"
When enabled: shows "Active 2h ago" on profile and in chat
When disabled: shows "Usually responds within a day" (based on average response time)

### Screenshot Prevention
Apply `FlutterWindowManager.FLAG_SECURE` to:
- chat_screen.dart
- my_conversations_screen.dart
- settings_screen.dart

### How Members Find Each Other
1. Church member list — on church profile
2. Member directory — searchable opt-in directory
3. Event attendees — on event detail screen
4. Prayer request — "Send Private Support" button
5. Marketplace — contact seller directly
6. People You May Know — shown in Profile tab and after following a church

---

## PART 21 — PRAYER REQUESTS COMPLETE SPECIFICATION

### Layout — Private Board (NOT a Feed)

**Entry Screen — Prayer Wall**

Section 1 — My Church
Prayer requests from churches you follow.

Section 2 — Public Requests  
Members who chose public visibility.

Section 3 — My Requests
Your own prayer requests.

**Daily Prayer Focus (top of screen)**
Set by you (admin) from web dashboard.
Rotates daily. Shared focus for all members.
e.g. "Today's focus: Pray for members in Manicaland province"

### Prayer Card Content
**Public:**
Name, church, time posted, prayer count, [I'm Praying] [Send Support]

**Anonymous:**
"Posted anonymously", city, time, prayer count, [I'm Praying]
No "Send Support" — anonymous means no contact

**Answered:**
Green answered badge, original request, prayer count, "Marked as answered"

### I'm Praying Button
Tapping increments prayer count.
Poster notified: "Someone is praying for you"
Who prayed is never shown publicly — only the count.

### Answered Prayer Flow
Poster taps "Mark as Answered"
→ Card gets green badge
→ Moves to answered section
→ Everyone who prayed gets notification: "[Name]'s prayer was answered. Praise God! 🙏"

### What Is NOT Included
- No comments section — becomes argument section
- No like button — prayer is not a popularity contest
- No share to home feed — too public for intimate requests
- No prayer streaks — gamification cheapens prayer
- No public display of who prayed

### Post Prayer Request Fields
- Title — max 80 characters
- Body — max 500 characters
- Visibility — Public / My Church Only / Anonymous
- Urgent flag — shows urgent badge
- Auto-expires 30 days — renewable

---

## PART 22 — MEMBER DIRECTORY COMPLETE SPECIFICATION

Opt-in only. Nobody listed without choosing to be.
User controls via Settings → Privacy → "Show me in member directory"

### Each Directory Listing Shows
- Name and profile photo
- Profession or skill
- Home church
- Province and city
- Send Message Request button

### Search Filters
- Name
- Profession or skill
- Province and city
- Home church
- Conference

### Privacy Rules
- No phone number or email shown publicly
- Contact via message request only
- If also a seller: seller store linked on profile
- User removes themselves anytime from Settings

---

## PART 23 — NOTIFICATIONS COMPLETE SPECIFICATION

### What Triggers Notifications

| Trigger | Recipient |
|---------|----------|
| Church posts announcement | All followers (per their preference) |
| Church posts obituary | All followers — always delivered |
| Urgent banner posted | All users in that conference |
| Event approved | Person who posted it |
| Event reminder | RSVPd members — 24 hours before |
| Someone praying for you | You |
| Prayer answered | Everyone who prayed |
| Message request received | You |
| New message received | You |
| Seller account approved/rejected | You |
| Church claim approved/rejected | You |
| Job post expiring in 3 days | You (poster) |
| Job marked as filled | You (poster — success message) |
| Church admin action | You (super admin — for review queue items) |

### Notification Centre Layout
**Today**
Items grouped, most recent first
Red for obituaries and urgent
Blue for messages
Navy for announcements and events

**Yesterday**
Same grouping

Tapping any notification navigates directly to relevant screen.
Never just opens home screen.

### Notification Preferences
Per church: All / Urgent and Obituaries Only / None
Global: Messages always on, prayers on/off, event reminders on/off, job alerts by category on/off

---

## PART 24 — ADMOB SPECIFICATION

### Banner Ad Locations
- Home screen — below full feed
- Churches screen — below list
- Events screen — below list
- Marketplace screen — below list
- Jobs screen — below list

### Where Ads NEVER Appear
- Chat screen
- Prayer requests screen
- Any screen showing obituary/funeral content
- Any screen mid-conversation

---

## PART 25 — ONBOARDING FLOW

### Screen 1 — Splash
App logo animation. 2 seconds.

### Screens 2-4 — Three Onboarding Slides
Dark navy background. Can be skipped at any point.

Slide 1: 🏛️ "Zimbabwe's SDA Community" — find church, announcements, directory
Slide 2: 🛍️ "Buy and Sell Within Your Community" — marketplace, jobs, Sabbath friendly
Slide 3: 🙏 "Stay Connected Spiritually" — prayer, events, obituaries

### Screen 5 — Account Choice
[ Continue with Google ]
[ Sign up with Email ]
"Already have an account? Log in"
Terms and Privacy Policy link — required before proceeding

### After Signup — 3 Step Profile Setup
**Step 1:** Name (required) + profile photo (optional, can skip)
**Step 2:** Find home church — search 2,600 churches. "I'll do this later" skip option.
**Step 3:** Province selection — dropdown. Personalises feed immediately.

**Done — user is in the app.**
Profile completion bar shows 40% and nudges them to add bio etc over time.

### Age Verification
Date of birth required on signup.
If under 13: "Sorry, Advent Connect ZW is for members 13 and older." Account blocked.

---

## PART 26 — SECURITY IMPLEMENTATION

### Stage 1 — Add to main.dart
```dart
// Crashlytics
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

// Root detection (add flutter_jailbreak_detection)
bool isJailbroken = await FlutterJailbreakDetection.jailbroken;
if (isJailbroken) {
  // Show warning, restrict sensitive features
}
```

### Token Storage — MANDATORY
```dart
// Always use flutter_secure_storage for auth tokens
const storage = FlutterSecureStorage();
await storage.write(key: 'supabase_token', value: token);
```

### Screenshot Prevention — Sensitive Screens
```dart
// Add to initState of: chat_screen, settings_screen, conversations_screen
await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);

// Remove in dispose
await FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
```

### Input Validation Rules
- All text fields: strip HTML tags before saving
- Phone numbers: validate Zimbabwe format (+263 or 07x)
- Prices: must be positive decimal
- File uploads: validate type AND size server-side via Edge Function
- Age on signup: block under 13 completely

### Rate Limiting — Enforce in Edge Functions
- Messages: max 30 per hour per user
- New conversations: max 10 per day per user
- Message requests: max 10 per day per user
- Product listings: new sellers max 5 products in first 7 days
- Broadcasts: max 3 per day per church

### Code Obfuscation — Every Release Build
```bash
flutter build apk --obfuscate --split-debug-info=build/debug-info
```

### Service Role Key Rules
- NEVER in Flutter code
- NEVER in any committed file
- NEVER in WhatsApp or email
- Store in password manager only
- Change immediately if suspected leak

---

## PART 27 — OFFLINE MODE SPECIFICATION

### What Works Offline
- Home feed — last cached 50 items (up to 24 hours old)
- Followed church profiles — cached versions
- Upcoming events for next 30 days — cached
- Conversations — history visible, new messages queued
- User's own profile — always available

### What Doesn't Work Offline
- Search — disabled with "Search requires connection" message
- New posts — queued and sent when reconnected
- Payments/contact buttons — disabled

### Offline Indicator
Subtle top banner: "📡 You're offline — showing saved content"
Not a crash. Not a full screen error.

### Cache Strategy
Use hive_flutter for local caching.
Cache on every successful load.
Clear cache older than 24 hours.

### Message Queue
Messages typed offline are stored in hive.
On reconnection — auto-send in order.
User sees: ⏳ "Sending..." → ✅ "Delivered"

---

## PART 28 — PERFORMANCE RULES

### Image Compression — Before Every Upload
```
Profile photo:   500KB max, 800x800px
Church photo:    800KB max, 1200x800px
Product photo:   600KB max, 1000x1000px
Event flyer:     1MB max, 1200x1600px
```
Use image_cropper to compress on device. Never upload raw.

### Pagination — Everywhere
```
Churches list:    20 at a time
Home feed:        15 items at a time
Products grid:    16 at a time
Messages:         30 at a time
Notifications:    20 at a time
```

### Target Test Devices
- Tecno Spark 8 — very common Zimbabwe
- Samsung Galaxy A13 — mid range Zimbabwe
- Infinix Hot 12 — budget Zimbabwe
- Redmi 9A — entry level

If smooth on Tecno Spark — it's ready.

---

## PART 29 — CONTENT MODERATION POLICY

### Response Times
- Urgent (sexual content, threats, child safety): 2 hours
- Standard (spam, harassment, fraud): 24 hours
- Low priority (misinformation, minor): 48 hours

### Action Levels
| Violation | First | Second | Third |
|-----------|-------|--------|-------|
| Spam | Warning + remove | 7 day suspension | Permanent ban |
| Harassment | Warning + remove | 30 day suspension | Permanent ban |
| False info | Remove | Warning | 7 day suspension |
| Marketplace fraud | Suspend | Permanent ban | — |
| Sexual content | Immediate permanent ban | — | — |
| Child safety | Permanent ban + report to authorities | — | — |
| Hate speech | Immediate permanent ban | — | — |

### Reported Content Flow
```
User reports
→ Content immediately hidden (not deleted — hidden for evidence)
→ Admin queue
→ Review within 24 hours
→ Action taken
→ Reporter notified of outcome
```

---

## PART 30 — ANALYTICS TRACKING

### Custom Firebase Events — Add to Every Feature
```dart
FirebaseAnalytics.instance.logEvent(name: 'church_followed');
FirebaseAnalytics.instance.logEvent(name: 'message_sent');
FirebaseAnalytics.instance.logEvent(name: 'prayer_posted');
FirebaseAnalytics.instance.logEvent(name: 'marketplace_contact');
FirebaseAnalytics.instance.logEvent(name: 'event_rsvp');
FirebaseAnalytics.instance.logEvent(name: 'church_claimed');
FirebaseAnalytics.instance.logEvent(name: 'job_posted');
FirebaseAnalytics.instance.logEvent(name: 'seller_applied');
```

### Key Metrics to Monitor Weekly
- Day 7 retention (target 35%+)
- Daily Active Users
- Most visited screen
- Churches claimed per week
- Messages sent per day
- Reports filed per week (rising = problem)

---

## PART 31 — MONETISATION ROADMAP

| Stage | Timing | Revenue Stream | Expected |
|-------|--------|---------------|---------|
| 1 | Launch | AdMob banners | $2-20/month |
| 2 | Month 3 | Featured seller listings ($2-5/week) | $50-200/month |
| 3 | Month 6 | Featured events ($5-10 per event) | $30-100/month |
| 4 | Month 12+ | Conference partnerships | $100-500/month |
| 5 | Year 2 | Premium church/seller accounts | $200-800/month |

### Featured Listings Implementation
```sql
-- Already in products table:
is_featured      BOOLEAN DEFAULT FALSE
featured_until   TIMESTAMPTZ
featured_paid_at TIMESTAMPTZ
```
Collect payment via EcoCash to your number. Mark featured manually in Supabase initially.

---

## PART 32 — LEGAL REQUIREMENTS

### Before Google Play Submission — Non-Negotiable
1. Terms of Service document — hosted on public URL
2. Privacy Policy document — hosted on public URL
3. Both linked from app and Google Play listing
4. Host free on Google Sites or Carrd.co

### Key Privacy Policy Points
- Data stored on Supabase Africa Cape Town
- Third parties: Supabase, Firebase, Google AdMob, Google Sign In
- Children: no under 13 accounts
- Deletion: Settings → Delete Account removes all personal data
- Contact: mtechstudioszw@gmail.com

### Content Rating
Set to "Everyone 10+" during Google Play submission questionnaire.

---

## PART 33 — BETA TESTING PLAN

### Tester Mix (50 people total)
- 10 aged 15-25
- 15 aged 26-40
- 10 aged 41-60
- 5 church administrators or elders
- 5 pastors or conference workers
- 5 people in rural areas / slow internet

### 4 Week Structure
Week 1: Recruit via WhatsApp beta group. Use Google Play internal testing track.
Week 2: Structured daily tasks (signup → church → marketplace → prayer → messaging)
Week 3: Google Form feedback collection
Week 4: Fix all critical issues. No new features.

### Fix Threshold
If 3+ testers are confused by the same thing — it's your design, not them. Fix it.

---

## PART 34 — VERSIONING

```
1.0.0  — Public launch (all 20 stages complete, beta tested)
1.0.1  — First bug fix patch
1.1.0  — Post-launch feature update
1.2.0  — Featured listings + payment groundwork
2.0.0  — Payments, Shona/Ndebele language, web dashboard
```

Force update ONLY for critical security vulnerabilities.

---

## PART 35 — BUILD STAGES (20 STAGES)

### Stage 1 — Foundation
pubspec.yaml, app_colors.dart, app_text_styles.dart, app_theme.dart,
supabase_config.dart, router_config.dart, main.dart
Add Crashlytics to main.dart. Add flutter_secure_storage service.

### Stage 2 — Auth
splash_screen, onboarding (3 slides + account choice),
login, signup (with age verification), email_verification,
profile_setup (name + photo), profile_setup_church (church selection),
forgot_password, reset_password

### Stage 3 — Database Setup
All 31 tables SQL. All RLS policies. Storage buckets.
Enable Realtime on messages, conversations, notifications only.

### Stage 4 — Church Models + Services
church.dart model, auth_service.dart, storage_service.dart,
connectivity_service.dart, cache_service.dart

### Stage 5 — Profile Tab
profile_screen (activity dashboard), edit_profile_screen,
settings_screen, notification_preferences_screen,
sabbath_timer_screen, blocked_users_screen

### Stage 6 — Home Tab
home_screen (Option C feed + urgent banner), search_screen,
post_notice_screen

### Stage 7 — Churches Tab
churches_screen, church_profile_screen (all location_status variants),
suggest_edit_screen, church_announcements_screen,
claim_church_screen, suggest_church_screen

### Stage 8 — Church Seed Data
Import 2,600 churches from cleaned CSV.
SQL INSERT statements in batches of 100.

### Stage 9 — Events Tab
events_screen, event_detail_screen, post_event_screen
Both church (auto-approve) and community (pending) flows.

### Stage 10 — Seller Setup
setup_store_screen, seller_dashboard_screen,
edit_store_screen

### Stage 11 — Marketplace Shop
marketplace_screen (with Shop/Jobs toggle),
shop_screen, category_screen, listing_detail_screen,
seller_profile_screen, add_product_screen, manage_products_screen
Saved listings. Sabbath badge. WhatsApp contact with pre-fill.

### Stage 12 — Jobs Board
jobs_screen, job_detail_screen, post_job_screen
All job categories. Auto-expire 30 days. Mark as filled.

### Stage 13 — Seller Ratings
seller_ratings table. Rating UI on seller profile.
Trigger: only after conversation with seller.

### Stage 14 — Prayer Requests
prayer_requests_screen (private board layout),
post_prayer_screen. Three visibility levels. Answered prayer flow.
Daily prayer focus from admin.

### Stage 15 — Member Directory
member_directory_screen, my_directory_profile_screen
Opt-in. Searchable. Message request integration.

### Stage 16 — Messaging
my_conversations_screen, chat_screen
Real-time. Voice notes. Typing indicator. Read receipts.
Message requests. Screenshot prevention.

### Stage 17 — Notifications
notification_service.dart. FCM integration.
In-app notification centre. All triggers wired up.

### Stage 18 — Admin Screens
Church admin dashboard (not app admin — that's web only).
Approval queue for church admin. Church content management.

### Stage 19 — Firebase + FCM
firebase_messaging full setup. Background notifications.
Analytics events. Crashlytics.

### Stage 20 — AdMob + Polish + Testing
AdMob banner integration on all approved screens.
Offline mode (hive caching). Performance optimisation.
Code obfuscation on release build. Final bug fix sweep.

---

## PART 36 — LAUNCH STRATEGY

### Before Writing Code (Now)
- Create WhatsApp beta group — target 50 SDA members
- Write formal letter to all 6 conference offices requesting partnership meeting
- Commission app icon design ($20-50 on Fiverr)

### During Development
- Share weekly progress updates to beta WhatsApp group
- Follow up with conference communications departments
- Prepare Google Play listing copy and screenshots

### Beta Launch (After Stage 15)
- 50 testers on Google Play internal testing track
- 4 weeks structured testing
- Fix all critical issues

### Public Launch
- Target camp meeting season for announcement
- Request 5 minutes on stage at major SDA event
- Bring printed QR codes linking to Google Play

### First 100 Users
Beta group (50) + one conference endorsement post (200+) + camp meeting announcement (100+) = 350+ in first month

---

## PART 37 — ADMIN DASHBOARD (WEB — BUILD AFTER APP)

### Technology
Phase 1: Supabase table editor (free, immediate)
Phase 2: Retool free tier (5 users, one weekend to build)
Phase 3: Custom Next.js dashboard (hosted free on Vercel)

### Admin Roles
- super_admin (you): full access to everything
- conference_admin: their conference only
- district_admin: their district only

### RLS for Conference Admins
Conference admins see only their conference data.
Enforced at database level — not just hidden on screen.

### Estimated Build Cost
Retool (self-built): Free
Retool (hired developer): $200-500 once off
Custom Next.js (hired developer): $800-2,000 once off

### Build Priority
Build after app is fully working and you have real users.
Use Supabase table editor for all approvals during development.

---

## PART 38 — CHURCH SEED DATA

### CSV File
File: zimbabwe_churches_cleaned.csv
Records: 2,600 churches (1 non-Zimbabwe record removed)
Coverage: All 10 Zimbabwe provinces, all 6 conferences

### Columns in Cleaned CSV
name, district, city, province, conference, conference_code,
church_size, status, entity_type, is_verified, location_status,
latitude, longitude, leader_name, leader_role, district_pastor_name,
sabbath_school_time, main_service_time, service_language,
meeting_venue_note, whatsapp_group_link, phone, email

### GPS Coordinates
All NULL — no coordinates in source data.
Plan: After import, use Nominatim batch geocoding for city-level coordinates.
Church admins provide precise coordinates when they claim their church.

### Before Launch — Manual Seed Top 50 Churches
Manually add service times, pastor names, phone numbers for:
- Top 20 Harare churches by size
- Top 15 Bulawayo churches by size
- Top 15 other major city churches

These are the first churches users will find. They must look complete.

---

## PART 39 — HOW TO USE THIS DOCUMENT IN EVERY CLAUDE CODE SESSION

At the start of every session:
1. `cd path/to/advent_connect_zw`
2. `claude`
3. Type: `Read MASTER_REFERENCE_V4.md. We are on Stage [X]. Build Stage [X] as described in Part 35.`
4. `/compact` after every 3-4 files
5. `flutter run` after every file
6. `git commit` after every working stage

Never deviate from anything in this document without discussing first.

---

## PART 40 — STAGE 1 SESSION — WORD FOR WORD

```
Read MASTER_REFERENCE_V4.md before writing anything.

We are starting Stage 1 from Part 35.

Build these files completely:
1. pubspec.yaml — use exact versions from Part 5
2. lib/theme/app_colors.dart — all colors from Part 2
3. lib/theme/app_text_styles.dart — Poppins all weights
4. lib/theme/app_theme.dart — full MaterialTheme
5. lib/config/supabase_config.dart — Africa Cape Town region
6. lib/config/router_config.dart — go_router skeleton all 53 screens
7. lib/services/secure_storage_service.dart — flutter_secure_storage wrapper
8. lib/main.dart — with Crashlytics initialised

Give me complete files only. No partial files.
Configure for BOTH Android and iOS simultaneously.
Add all iOS permissions to Info.plist.
Add SafeArea to every scaffold.
Use Platform.isAndroid check for flutter_windowmanager.
Generate placeholder google-services.json and GoogleService-Info.plist structures.
Add firebase_crashlytics initialisation to main.dart.
Use flutter_secure_storage for all token storage — never SharedPreferences.
After each file I will run the app and confirm before moving on.
```

---

*ADVENT CONNECT ZW — MASTER REFERENCE V4*
*MTech Studios ZW — Tanatswa Michael Mikuwa*
*mtechstudioszw@gmail.com*

---

## PART 41 — PLATFORM CONFIGURATION — ANDROID AND iOS

### Why Both Platforms From Day One
Flutter writes code once — runs on both platforms.
Extra configuration work is approximately 2-3 hours across the entire project.
Not extra screens. Not extra logic. Just configuration files.

### What Is Different Per Platform

| Item | Android | iOS |
|------|---------|-----|
| Config file | google-services.json | GoogleService-Info.plist |
| Permissions | AndroidManifest.xml | Info.plist |
| AdMob App ID | AndroidManifest.xml | Info.plist |
| Screenshot prevention | flutter_windowmanager | Platform.isAndroid check |
| Safe area | Automatic | SafeArea widget on every scaffold |
| Back navigation | Hardware back button | Swipe right gesture |
| Biometric label | Fingerprint/Face Unlock | Face ID/Touch ID |

### iOS Permissions — Add ALL of These to Info.plist
```xml
NSCameraUsageDescription
"Advent Connect ZW uses your camera to upload profile and product photos."

NSPhotoLibraryUsageDescription
"Advent Connect ZW accesses your photos to upload profile and product images."

NSMicrophoneUsageDescription
"Advent Connect ZW uses your microphone to record voice notes in chat."

NSLocationWhenInUseUsageDescription
"Advent Connect ZW uses your location to find SDA churches near you."

NSFaceIDUsageDescription
"Advent Connect ZW uses Face ID to securely unlock your account."

NSContactsUsageDescription
"Advent Connect ZW does not access your contacts."
```

### Platform Check for Screenshot Prevention
```dart
import 'dart:io';

// In initState of sensitive screens:
if (Platform.isAndroid) {
  await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
}
// iOS handles secure fields natively
// No equivalent full-screen prevention needed on iOS

// In dispose:
if (Platform.isAndroid) {
  await FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
}
```

### SafeArea — Every Scaffold
```dart
// Every screen must wrap content in SafeArea for iOS notch compatibility
Scaffold(
  body: SafeArea(
    child: // your content
  ),
)
```

### Two AdMob App IDs
Create both in Google AdMob console before Stage 20:
- Android App ID → goes in AndroidManifest.xml
- iOS App ID → goes in Info.plist

### Testing Priority
1. Test Android first — primary Zimbabwe market
2. When Android is stable — test iOS
3. One person in beta group must have iPhone for iOS testing

---

## PART 42 — COST AND SPONSORSHIP ARRANGEMENT

### One-Off Costs — Covered by Sponsor
| Cost | Amount | Frequency |
|------|--------|-----------|
| Google Play Developer Account | $25 | Once off — permanent |
| Apple Developer Account | $99 | Once per year |
| App icon design | $20-50 | Once off |

### Monthly Costs — Covered by Developer
| Cost | Amount | When |
|------|--------|------|
| Claude Pro | ~$20-24/month | During active development only |
| Supabase Pro | $25/month | Only after 300 DAU |

### Claude Pro Strategy — Do Not Pay Every Month Forever
Only subscribe during active building months.
Cancel during beta testing period.
Cancel after launch when no active building.
Resubscribe when adding new features.

Estimated total Claude Pro spend to complete app: $140-160 (7 months)

### When Supabase Pro Becomes Necessary
Free tier limits:
- 500MB database
- 1GB storage
- 500,000 API requests/month
- Project pauses after 7 days inactivity (fix with UptimeRobot)

Upgrade to Pro ($25/month) when:
- Approaching 300 DAU
- Storage over 800MB
- API requests over 400,000/month

By the time you need Pro — AdMob and featured listings should cover the cost.

### Showing Sponsor Return on Investment
Every dollar of AdMob revenue — screenshot and send to sponsor.
Every church claimed — update sponsor with milestone.
Every 100 users — send sponsor a progress update.
Sponsors who see traction become long term supporters.
