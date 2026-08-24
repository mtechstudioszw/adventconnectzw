-- =====================================================================
--  PATCH 252 — Advent AI: the app-knowledge base
--
--  The second part the original roadmap promised and never delivered.
--  Without it, "how do I create a post?" is answered from the model's
--  imagination, and it WILL invent buttons, menus and screens this app
--  does not have (brief §32). A confident wrong answer about the app is
--  worse than "I'm not sure" — the member goes hunting for something
--  that was never there, and concludes the app is broken.
--
--  ## Why a table and not a paragraph in the prompt
--
--  The brief is explicit: do not hard-code a giant description. Three
--  reasons it would fail:
--
--   1. **It goes stale silently.** The app ships every couple of weeks.
--      A prompt string in a TypeScript file is not something anyone
--      remembers to update, and nothing fails when it is wrong.
--   2. **It costs money on every single question.** A 3,000-token app
--      description would ride along on "what does Romans 8 mean?" as
--      well, for nothing. Retrieval sends only the two or three entries
--      that match.
--   3. **It cannot be fixed without a deploy.** This table is editable
--      from the Supabase dashboard: a wrong answer is a one-row UPDATE,
--      live immediately, no APK.
--
--  ## Accuracy rules for anyone adding rows — READ THIS
--
--  Every `route` in the seed below was taken from
--  `lib/config/router_config.dart`, and the tab names from
--  `lib/screens/widgets/main_bottom_nav.dart`. They are not from memory.
--
--   * **Never name a button you have not seen in the source.** Describe
--     navigation ("open the Chat tab") rather than inventing labels
--     ("tap the blue New Message button"). Navigation is stable; labels
--     and icons change every redesign.
--   * The five tabs are **Home, Watch, Chat, Marketplace, Profile**.
--     Note the third is labelled "Chat" even though its route is
--     `/messages` — writing "the Messages tab" sends members looking
--     for a tab that does not exist.
--   * If a feature is admin-only or seller-only, say so. A member being
--     told to use something they cannot see is its own bug report.
--   * When unsure, leave it out. An absent entry makes the model say it
--     is not sure, which is correct. A wrong entry makes it lie
--     confidently.
--
--  IDEMPOTENT: yes.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.ai_app_knowledge (
  id          BIGSERIAL PRIMARY KEY,

  -- Short slug for humans editing this table. Not shown to members.
  topic       TEXT NOT NULL UNIQUE,

  -- The question as a member would ask it. Feeds the search index, so
  -- phrase it the way people actually type, not the way a manual would.
  question    TEXT NOT NULL,

  -- The answer, in the assistant's own voice. Kept SHORT — this is
  -- injected into a prompt, and every word is paid for on every
  -- matching question. Two or three sentences.
  answer      TEXT NOT NULL,

  -- Where in the app this lives, e.g. '/marketplace'. Lets the app
  -- offer a "take me there" action beside the answer later.
  route       TEXT,

  -- Extra words that should match this entry but do not appear in the
  -- question — synonyms and the words members use instead of ours.
  keywords    TEXT,

  -- Higher wins when several entries match equally.
  weight      SMALLINT NOT NULL DEFAULT 0,

  -- Lets a wrong entry be switched off from the dashboard without
  -- deleting it, so the fix is reversible.
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,

  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ai_app_knowledge_fts_idx
  ON public.ai_app_knowledge
  USING GIN (to_tsvector('english',
    question || ' ' || answer || ' ' || COALESCE(keywords, '')));

-- ---------------------------------------------------------------------
--  Retrieval
--
--  Returns the few best matches for a question. Bounded hard: a large
--  result set would crowd out the conversation itself and cost more
--  than the answer is worth.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_app_help(
  p_query TEXT,
  p_limit INT DEFAULT 3
)
RETURNS TABLE (topic TEXT, question TEXT, answer TEXT, route TEXT)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT k.topic, k.question, k.answer, k.route
    FROM public.ai_app_knowledge k
   WHERE k.is_active
     AND to_tsvector('english',
           k.question || ' ' || k.answer || ' ' || COALESCE(k.keywords, ''))
         @@ websearch_to_tsquery('english', p_query)
   ORDER BY
     ts_rank(to_tsvector('english',
       k.question || ' ' || k.answer || ' ' || COALESCE(k.keywords, '')),
       websearch_to_tsquery('english', p_query)) DESC,
     k.weight DESC
   LIMIT GREATEST(LEAST(COALESCE(p_limit, 3), 6), 1);
$$;

ALTER TABLE public.ai_app_knowledge ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_app_knowledge_read ON public.ai_app_knowledge;
CREATE POLICY ai_app_knowledge_read ON public.ai_app_knowledge
  FOR SELECT USING (is_active);

REVOKE ALL ON public.ai_app_knowledge FROM anon, authenticated;
GRANT SELECT ON public.ai_app_knowledge TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_app_help(TEXT, INT) TO authenticated;

-- ---------------------------------------------------------------------
--  Seed
--
--  Routes verified against router_config.dart; tab names against
--  main_bottom_nav.dart. Deliberately describes navigation rather than
--  button labels — see the accuracy rules above.
-- ---------------------------------------------------------------------
INSERT INTO public.ai_app_knowledge
  (topic, question, answer, route, keywords, weight) VALUES

('create_post',
 'How do I create a post?',
 'Posts are made from the Home tab — the composer sits at the top of the feed, above the posts. You can add text and photos, and it goes out to your part of the community.',
 '/home', 'write share status update publish new post feed', 10),

('edit_profile',
 'How do I edit my profile or change my profile picture?',
 'Open the Profile tab and choose to edit your profile. Your photo, name and details are all changed from there.',
 '/profile', 'avatar picture photo bio details change update account', 10),

('find_friends',
 'How do I find friends or follow people?',
 'The Directory lets you search for other members, and Scan Friend adds someone who is with you in person by scanning their code. You can also tap anyone''s name on a post to open their profile.',
 '/directory', 'follow add people search members connect friend scan', 8),

('send_message',
 'How do I send a message?',
 'Messaging lives in the Chat tab. Start a new chat there, or open someone''s profile and message them from it. Chats are private between you and the person you are talking to.',
 '/messages', 'dm text private conversation talk inbox message someone', 10),

('create_group',
 'How do I create a group chat?',
 'From the Chat tab you can start a new group and add the members you want in it.',
 '/messages', 'group chat create add people together', 6),

('prayer_request',
 'How do I post a prayer request?',
 'The Prayer section is where prayer requests are posted and where you can pray for other members'' requests.',
 '/prayer', 'pray request intercession prayer circle need prayer', 8),

('find_church',
 'How do I find a church?',
 'The Churches section lists Adventist churches with their details, and you can search it to find one near you or the one you attend.',
 '/churches', 'congregation find church near me locate assembly', 8),

('find_events',
 'How do I find events?',
 'Events shows what is coming up — camp meetings, programmes and church events. You can browse it and see the details of each one.',
 '/events', 'programme camp meeting calendar upcoming what is on', 8),

('marketplace_buy',
 'How does the marketplace work?',
 'The Marketplace tab is where members buy and sell. You can browse products, add them to your cart and place an order.',
 '/marketplace', 'buy sell shop products cart order store purchase', 8),

('become_seller',
 'How do I become a seller?',
 'Selling is set up from the Seller section, where you register as a seller and then list your products. Until you have set that up you can still buy as normal.',
 '/seller', 'sell my products vendor shop open store trader business', 8),

('bible_reader',
 'Where is the Bible in the app?',
 'The Bible is in the Library, and it works offline once the app is installed. You can read, search it, and keep your place.',
 '/library', 'scripture read bible kjv verse chapter offline', 9),

('sabbath_school',
 'Where is the Sabbath School lesson?',
 'The Sabbath School lesson is in the Library, alongside the Bible, the Hymnal and the Ellen G. White writings.',
 '/library', 'lesson study quarterly ss sabbath school adult lesson', 9),

('hymnal',
 'Where is the Hymnal?',
 'The Hymnal is in the Library. You can find hymns by number or by searching the words.',
 '/library', 'hymn sing song music sda hymnal number', 8),

('egw_books',
 'Where can I read Ellen G. White''s books?',
 'The Ellen G. White writings are in the Library, and books can be downloaded to read offline.',
 '/library', 'egw spirit of prophecy books desire of ages steps to christ', 8),

('quiz',
 'How does the Quiz work?',
 'The Quiz is a Bible quiz you can play on your own or against other members. It is in the Quiz section.',
 '/quiz', 'game trivia bible quiz challenge play compete arena', 7),

('watch',
 'What is the Watch tab?',
 'Watch is where sermons, programmes and other video content live, including live streams when something is on.',
 '/watch', 'video sermon stream live youtube channel preaching', 7),

('premium',
 'What is Premium and what does it include?',
 'Premium is an optional monthly subscription. It removes ads, includes a monthly allowance of Advent AI questions, and helps keep the app free for members who cannot pay. Everything else in the app is free either way.',
 '/premium', 'subscription pay upgrade cost price ads paid plan', 9),

('ai_free_questions',
 'How many Advent AI questions do I get?',
 'Every member gets a small number of free Advent AI questions each month. Premium members get a much larger monthly allowance. Your remaining questions are shown in Advent AI itself.',
 '/premium', 'advent ai free questions limit allowance how many left credit', 9),

('report_content',
 'How do I report something inappropriate?',
 'Posts, profiles and listings can be reported from the item itself, and blocking someone stops them contacting you. Reports go to the moderators, not to the person you reported.',
 NULL, 'report block abuse inappropriate offensive flag moderation spam', 8),

('settings_notifications',
 'How do I change my notification settings?',
 'Notification settings are in Settings, where you can choose which kinds of notifications you receive.',
 '/settings', 'notifications push alerts turn off mute silence', 7),

('privacy_who_can_message',
 'How do I control who can message me?',
 'Settings has privacy options, including who is allowed to message you.',
 '/settings', 'privacy who can message block strangers dm requests', 7),

('delete_account',
 'How do I delete my account?',
 'Account deletion is in Settings. It removes your account and your content, and it cannot be undone.',
 '/settings', 'delete remove close account leave quit erase data', 6),

('offline',
 'Does the app work without internet?',
 'Parts of it do. The Bible works fully offline, and downloaded books and music stay available. Anything that loads new content — the feed, chat, marketplace — needs a connection.',
 NULL, 'offline no internet data connection airplane works without', 6),

('donate',
 'How do I give or donate?',
 'The Donate section is where giving is handled in the app.',
 '/donate', 'give offering tithe donate support contribute', 5),

('jobs',
 'Are there jobs on the app?',
 'The Jobs section lists opportunities shared with the community.',
 '/jobs', 'work vacancy employment career hiring opportunity', 5),

('help_support',
 'How do I get help or contact support?',
 'There is a Help section in the app, and you can send feedback from Settings if something is wrong or you need a person to look at it.',
 '/help', 'support contact us problem bug feedback complain assistance', 7)

ON CONFLICT (topic) DO UPDATE
  SET question = EXCLUDED.question,
      answer   = EXCLUDED.answer,
      route    = EXCLUDED.route,
      keywords = EXCLUDED.keywords,
      weight   = EXCLUDED.weight,
      updated_at = NOW();

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
DO $$
DECLARE v_n INT; v_hit INT;
BEGIN
  SELECT COUNT(*) INTO v_n FROM public.ai_app_knowledge WHERE is_active;
  IF v_n < 20 THEN
    RAISE EXCEPTION 'patch 252: only % knowledge rows seeded', v_n;
  END IF;

  -- The retrieval path must actually return something for the single
  -- most likely question, or the table is decorative.
  SELECT COUNT(*) INTO v_hit
    FROM public.ai_app_help('how do I send a message', 3);
  IF v_hit = 0 THEN
    RAISE EXCEPTION 'patch 252: ai_app_help returned nothing for a seeded topic';
  END IF;

  RAISE NOTICE 'patch 252 OK — % knowledge rows, retrieval verified', v_n;
END $$;
