-- =====================================================================
--  ADVENT CONNECT ZW — SEED DATA (development / staging only)
--
--  Run this AFTER schema.sql.
--
--  Profiles, prayers, products, jobs, etc. all reference auth.users.id.
--  Before running this script you must:
--    1. Sign up 3 test accounts in Supabase Auth (or via the app), and
--    2. Replace the three UUIDs in the variables block below with the
--       actual user IDs from auth.users.
--
--  The DO block uses temp variables so the rest of the file stays clean.
-- =====================================================================

-- =====================================================================
--  PART 1 — Reference data with NO auth dependency
--  (Churches can be seeded freely.)
-- =====================================================================

INSERT INTO public.churches (
  name, description, district, conference, conference_code,
  province, city, suburb, address, latitude, longitude,
  phone, email, pastor_name, members_count, founded_year,
  cover_photo_url, follower_count, verified, status
) VALUES
  ('Harare Central SDA', 'Flagship downtown congregation with weekly youth ministry and active community outreach.',
   'Harare Central', 'East Zimbabwe Conference', 'EZC',
   'Harare', 'Harare', 'CBD', 'Cnr Sam Nujoma & Jason Moyo Street, Harare',
   -17.8252, 31.0335, '+263 24 270 1234', 'harare.central@adventistszimbabwe.org',
   'Pastor Tendai Moyo', 850, 1924,
   NULL, 0, TRUE, 'active'),

  ('Bulawayo City SDA', 'Historic Bulawayo congregation. Sabbath school 09:00, divine service 11:00.',
   'Bulawayo Central', 'West Zimbabwe Conference', 'WZC',
   'Bulawayo', 'Bulawayo', 'City Centre', '12th Avenue & Fife Street, Bulawayo',
   -20.1539, 28.5891, '+263 29 226 4789', 'bulawayo.city@adventistszimbabwe.org',
   'Pastor Sipho Ndlovu', 620, 1946,
   NULL, 0, TRUE, 'active'),

  ('Mutare Central SDA', 'Eastern Highlands hub with strong choir tradition and Pathfinder club.',
   'Mutare', 'East Zimbabwe Conference', 'EZC',
   'Manicaland', 'Mutare', 'Avenues', '5 Aerodrome Road, Mutare',
   -18.9707, 32.6731, '+263 20 6 4321', 'mutare.central@adventistszimbabwe.org',
   'Pastor Emmanuel Chinaka', 410, 1968,
   NULL, 0, TRUE, 'active'),

  ('Gweru Memorial SDA', 'Central Zimbabwe congregation, host of the annual youth congress.',
   'Gweru', 'West Zimbabwe Conference', 'WZC',
   'Midlands', 'Gweru', 'Senga', '12 Senga Road, Gweru',
   -19.4515, 29.8121, '+263 54 222 0099', NULL,
   'Elder Joyce Mhlanga', 295, 1979,
   NULL, 0, FALSE, 'active'),

  ('Masvingo SDA', 'Masvingo provincial congregation. Family-friendly Sabbath fellowship after divine service.',
   'Masvingo', 'East Zimbabwe Conference', 'EZC',
   'Masvingo', 'Masvingo', 'Mucheke', 'Stand 113 Mucheke Township, Masvingo',
   -20.0744, 30.8328, '+263 39 226 7711', NULL,
   'Pastor Rumbidzai Sithole', 180, 1992,
   NULL, 0, FALSE, 'active');


-- =====================================================================
--  PART 2 — Auth-dependent seed data
--
--  EDIT THESE THREE UUIDs to match real rows in auth.users.
--  Each user should already have a row in public.profiles (created on
--  signup, or insert manually before running this section).
-- =====================================================================

DO $$
DECLARE
  -- ⚠️  REPLACE WITH REAL auth.users.id VALUES BEFORE RUNNING ⚠️
  user_a   UUID := '00000000-0000-0000-0000-000000000001';
  user_b   UUID := '00000000-0000-0000-0000-000000000002';
  user_c   UUID := '00000000-0000-0000-0000-000000000003';

  church_harare   BIGINT;
  church_bulawayo BIGINT;
  church_mutare   BIGINT;
  church_gweru    BIGINT;
  church_masvingo BIGINT;

  event_camp     BIGINT;
  event_youth    BIGINT;
  event_concert  BIGINT;
  event_grad     BIGINT;
  event_prayer   BIGINT;

  prayer_id   BIGINT;
  product_id  BIGINT;
  job_id      BIGINT;

  conversation_id BIGINT;
BEGIN
  -- Look up the church IDs we just inserted (idempotent — by name)
  SELECT id INTO church_harare   FROM public.churches WHERE name = 'Harare Central SDA';
  SELECT id INTO church_bulawayo FROM public.churches WHERE name = 'Bulawayo City SDA';
  SELECT id INTO church_mutare   FROM public.churches WHERE name = 'Mutare Central SDA';
  SELECT id INTO church_gweru    FROM public.churches WHERE name = 'Gweru Memorial SDA';
  SELECT id INTO church_masvingo FROM public.churches WHERE name = 'Masvingo SDA';

  -- Verify the test profiles exist before continuing
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = user_a) THEN
    RAISE NOTICE 'Skipping auth-dependent seed: profile % not found. Edit seed_data.sql with real UUIDs.', user_a;
    RETURN;
  END IF;

  -- ---- Update profile metadata for the three test users ----
  UPDATE public.profiles SET
    full_name = 'Tatenda Chirwa',
    username  = 'tatenda',
    bio       = 'Worship team lead at Harare Central. Loves hymns and hiking.',
    province  = 'Harare', city = 'Harare', church_id = church_harare,
    is_verified = TRUE
  WHERE id = user_a;

  UPDATE public.profiles SET
    full_name = 'Rufaro Sibanda',
    username  = 'rufaro',
    bio       = 'Pathfinder leader · biology teacher · prays for revival in Bulawayo.',
    province  = 'Bulawayo', city = 'Bulawayo', church_id = church_bulawayo
  WHERE id = user_b;

  UPDATE public.profiles SET
    full_name = 'Tinashe Moyo',
    username  = 'tinashe',
    bio       = 'Software developer · seller · always brewing rooibos.',
    province  = 'Manicaland', city = 'Mutare', church_id = church_mutare,
    account_type = 'seller'
  WHERE id = user_c;

  -- ---- 5 Events ----
  INSERT INTO public.events (
    title, description, start_date, end_date, start_time, end_time,
    province, city, venue, address, church_id, organizer_id,
    category, capacity, cover_photo_url, contact_name, contact_phone,
    event_source, status
  ) VALUES
  ('Zimbabwe Camp Meeting 2026',
   'Annual camp meeting bringing together believers from across Zimbabwe for a week of revival, study and fellowship.',
   '2026-08-12', '2026-08-19', '08:00', '20:00',
   'Mashonaland West', 'Solusi', 'Solusi University Grounds', 'Solusi University, off Plumtree Road',
   church_bulawayo, user_a, 'camp_meeting', 5000, NULL,
   'Camp Coordinator', '+263 77 123 4567', 'church', 'approved')
  RETURNING id INTO event_camp;

  INSERT INTO public.events (
    title, description, start_date, start_time, province, city, venue, address,
    church_id, organizer_id, category, capacity, contact_name, contact_phone,
    event_source, status
  ) VALUES
  ('Harare Youth Rally',
   'A vibrant Sabbath afternoon of music, testimonies and Bible study for SDA youth across Harare.',
   '2026-06-13', '14:00',
   'Harare', 'Harare', 'Harare Central SDA Hall', 'Cnr Sam Nujoma & Jason Moyo Street',
   church_harare, user_a, 'youth', 800, 'Tatenda Chirwa', '+263 77 555 1234',
   'church', 'approved')
  RETURNING id INTO event_youth;

  INSERT INTO public.events (
    title, description, start_date, start_time, province, city, venue, address,
    church_id, organizer_id, category, capacity, stream_link, is_online,
    event_source, status
  ) VALUES
  ('Sacred Choirs Night — Mutare',
   'An evening of sacred choral music featuring choirs from across Manicaland. Donations support the local school feeding fund.',
   '2026-07-04', '18:30',
   'Manicaland', 'Mutare', 'Mutare Central SDA', '5 Aerodrome Road, Mutare',
   church_mutare, user_c, 'concert', 600,
   'https://youtube.com/live/example', TRUE, 'church', 'approved')
  RETURNING id INTO event_concert;

  INSERT INTO public.events (
    title, description, start_date, start_time, province, city, venue, address,
    church_id, organizer_id, category, capacity, event_source, status
  ) VALUES
  ('Solusi Graduation Sabbath',
   'Join us in honouring the 2026 graduating class. Special divine service followed by a community lunch.',
   '2026-11-21', '09:00',
   'Matabeleland North', 'Solusi', 'Solusi University Chapel', 'Solusi University Campus',
   church_bulawayo, user_b, 'graduation', 1200, 'church', 'approved')
  RETURNING id INTO event_grad;

  INSERT INTO public.events (
    title, description, start_date, end_date, start_time, end_time,
    province, city, venue, address, church_id, organizer_id, category, capacity,
    event_source, status
  ) VALUES
  ('Week of Prayer — Gweru',
   'Eight evenings of focused prayer and Scripture, led by visiting pastors from across Zimbabwe.',
   '2026-05-25', '2026-06-01', '18:30', '20:00',
   'Midlands', 'Gweru', 'Gweru Memorial SDA', '12 Senga Road, Gweru',
   church_gweru, user_b, 'week_of_prayer', 400, 'church', 'approved')
  RETURNING id INTO event_prayer;

  -- A handful of RSVPs across users
  INSERT INTO public.event_rsvps (event_id, user_id, status) VALUES
    (event_camp,   user_a, 'going'),
    (event_camp,   user_b, 'going'),
    (event_camp,   user_c, 'interested'),
    (event_youth,  user_b, 'going'),
    (event_youth,  user_c, 'going'),
    (event_concert,user_a, 'interested'),
    (event_grad,   user_a, 'going'),
    (event_prayer, user_b, 'going');

  -- Church follows
  INSERT INTO public.church_followers (church_id, user_id) VALUES
    (church_harare,   user_a),
    (church_harare,   user_b),
    (church_bulawayo, user_b),
    (church_mutare,   user_c),
    (church_gweru,    user_a),
    (church_masvingo, user_c);

  -- ---- 10 Prayer requests ----
  INSERT INTO public.prayers (author_id, title, content, visibility, church_id, is_urgent)
  VALUES
    (user_a, 'Healing for my mother',
     'My mother has been admitted to Parirenyatwa Hospital. Please join me in praying for her full recovery and peace for our family.',
     'public', church_harare, TRUE),
    (user_b, 'Wisdom for school leadership',
     'I take up a new role as deputy head next term. Pray that I would lead our learners with patience and the mind of Christ.',
     'public', church_bulawayo, FALSE),
    (user_c, 'Marketplace launch',
     'I am launching a small online business. Pray for honest customers and that the work would honour God and provide for my family.',
     'public', church_mutare, FALSE),
    (user_a, 'Pathfinder camp safety',
     'We travel to camp meeting next month. Pray for the safety of every Pathfinder making the long journey.',
     'church_only', church_harare, FALSE),
    (user_b, 'Reconciliation with a friend',
     'A close friendship has been strained for two years. I want to pursue reconciliation. Pray for softened hearts on both sides.',
     'anonymous', NULL, FALSE),
    (user_c, 'Job opportunity for my brother',
     'My younger brother graduated last year and is still searching. Please stand with us in prayer for the right opportunity.',
     'public', NULL, FALSE),
    (user_a, 'Revival in Harare CBD',
     'Pray that our outreach efforts in the CBD this Sabbath would meet souls who are hungry for the gospel.',
     'public', church_harare, FALSE),
    (user_b, 'Strength during exams',
     'Final exams are this month. Pray for clarity, calm and faithful study habits — for me and my classmates.',
     'public', NULL, FALSE),
    (user_c, 'My grandmother''s salvation',
     'I have been praying for my grandmother for years. She is open to studies for the first time. Please pray with me.',
     'public', church_mutare, TRUE),
    (user_a, 'Drought relief in our community',
     'The dry season has been hard on rural members. Pray for early rains and for hearts moved to share with those in need.',
     'public', NULL, FALSE);

  -- A few "I''m praying" reactions on the first two prayers
  SELECT id INTO prayer_id FROM public.prayers WHERE author_id = user_a AND title = 'Healing for my mother' LIMIT 1;
  IF prayer_id IS NOT NULL THEN
    INSERT INTO public.prayer_responses (prayer_id, user_id, response_type) VALUES
      (prayer_id, user_b, 'praying'),
      (prayer_id, user_c, 'praying');
    INSERT INTO public.prayer_responses (prayer_id, user_id, response_type, message) VALUES
      (prayer_id, user_b, 'message',
       'Standing with you. May the Lord hold your mother and your family close this week.');
  END IF;

  -- ---- 5 Products ----
  INSERT INTO public.products (
    seller_id, title, description, price, price_currency, category, subcategory,
    image_urls, condition, province, location, status, is_featured
  ) VALUES
    (user_c, 'MacBook Air M2 — 13" 256GB',
     'Lightly used, immaculate condition. Comes with original box, charger and a leather sleeve. No dents.',
     950.00, 'USD', 'Electronics', 'Laptops', '{}', 'like_new',
     'Manicaland', 'Mutare', 'available', TRUE),
    (user_c, 'Sabbath Hymnal — Hardcover',
     'Brand new SDA Hymnal in English. Perfect for choirs and gifting.',
     22.00, 'USD', 'Books', 'Religious', '{}', 'new',
     'Manicaland', 'Mutare', 'available', FALSE),
    (user_a, 'Hand-knit Baby Blanket',
     'Soft cotton blanket, hand-knit by a member of our quilting circle. Profits support the deacons fund.',
     35.00, 'USD', 'Home & Living', 'Baby', '{}', 'new',
     'Harare', 'Harare', 'available', FALSE),
    (user_b, 'Honda Fit 2014 — Manual',
     'One owner, full service history, 138,000 km. Recently serviced. Perfect first car.',
     6500.00, 'USD', 'Vehicles', 'Cars', '{}', 'good',
     'Bulawayo', 'Bulawayo', 'available', TRUE),
    (user_a, 'Vegetable Box — Weekly Subscription',
     'Fresh organic produce delivered every Friday in time for Sabbath. Cancel any time.',
     18.00, 'USD', 'Food', 'Produce', '{}', 'new',
     'Harare', 'Harare', 'available', FALSE);

  -- ---- 5 Jobs ----
  INSERT INTO public.jobs (
    poster_id, title, company, description, requirements, category, job_type,
    post_type, salary_range, province, location, sabbath_friendly, is_sda_institution,
    contact_phone, contact_email, status
  ) VALUES
    (user_a, 'Mathematics Teacher',
     'Solusi Adventist High School',
     'Full-time mathematics teacher for forms 1–4, joining a passionate team of educators in a Christian environment.',
     'Diploma in Education (mathematics major) and minimum 2 years teaching experience.',
     'teaching_education', 'full_time', 'hiring', 'USD 600–900 / month',
     'Matabeleland North', 'Solusi', TRUE, TRUE,
     '+263 77 555 9090', 'careers@solusi.ac.zw', 'open'),

    (user_b, 'Registered Nurse — Casualty',
     'Mutare Adventist Hospital',
     'Day shift registered nurse to join our casualty department. Sabbath observance respected by roster.',
     'Diploma in General Nursing, valid Council of Zimbabwe registration, BLS certified.',
     'healthcare', 'full_time', 'hiring', 'USD 700–1100 / month',
     'Manicaland', 'Mutare', TRUE, TRUE,
     '+263 20 6 0000', 'hr@mutareadventist.co.zw', 'open'),

    (user_c, 'Flutter Developer (Remote, Part-time)',
     'Mtech Studios ZW',
     'Build mobile features for a community app serving the SDA community in Zimbabwe. Remote, flexible hours.',
     'Two years of Flutter experience, comfortable with Supabase and Riverpod, portfolio of shipped apps.',
     'it_technology', 'part_time', 'hiring', 'USD 800–1500 / month',
     'Harare', 'Remote (Zimbabwe)', TRUE, FALSE,
     NULL, 'jobs@mtechstudios.co.zw', 'open'),

    (user_a, 'Looking for: Driver / Personal Assistant',
     NULL,
     'Seeking a Sabbath-keeping driver and PA for a small business owner in Harare. Trustworthy, punctual, defensive driver.',
     'Class 4 licence with at least 5 years clean driving record. Bring two referees.',
     'driving_transport', 'full_time', 'seeking', 'Negotiable',
     'Harare', 'Harare CBD', TRUE, FALSE,
     '+263 77 222 7777', NULL, 'open'),

    (user_b, 'Caregiver for Elderly Couple',
     'Private — Bulawayo',
     'Live-in caregiver needed for a retired couple. Cooking, light cleaning, medication reminders.',
     'Caregiver certificate, two written references from previous employers, sympathetic and patient.',
     'domestic_caregiving', 'full_time', 'hiring', 'USD 350 / month + accommodation',
     'Bulawayo', 'Bulawayo', TRUE, FALSE,
     '+263 71 444 8888', NULL, 'open');

  -- ---- A sample conversation thread ----
  -- Note: assumes patch_003_conversations_v4 has been applied (scalar
  -- columns + denormalised names). Names are pulled from profiles so
  -- the seed survives a re-import.
  INSERT INTO public.conversations (
    participant_a_id, participant_b_id,
    participant_a_name, participant_b_name,
    conversation_source
  )
  VALUES (
    user_a, user_c,
    (SELECT full_name FROM public.profiles WHERE id = user_a),
    (SELECT full_name FROM public.profiles WHERE id = user_c),
    'marketplace'
  )
  RETURNING id INTO conversation_id;

  INSERT INTO public.messages (conversation_id, sender_id, content, read) VALUES
    (conversation_id, user_a, 'Hi Tinashe — is the MacBook still available?',         TRUE),
    (conversation_id, user_c, 'Yes, still available. Are you in Harare or Mutare?',   TRUE),
    (conversation_id, user_a, 'Harare. Could we meet on Sunday afternoon?',           TRUE),
    (conversation_id, user_c, 'Sunday works. Let''s confirm a venue closer to the day.', FALSE);

  RAISE NOTICE 'Seed completed for users %, %, %.', user_a, user_b, user_c;
END $$;
