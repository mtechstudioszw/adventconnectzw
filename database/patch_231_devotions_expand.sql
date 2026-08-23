-- =====================================================================
--  PATCH 231 — More devotions, because 12 is the whole bug
--
--  Reported 23 Aug 2026: "users were saying the devotions the app sends
--  feel like a pattern and keep repeating".
--
--  They are not imagining it. `daily_devotions` held TWELVE rows, and
--  `devotion_day_index` is `day_of_year % count`, so the app walked the
--  same twelve in the same id order and started over every twelve days —
--  roughly thirty times a year. No scheduling or shuffling change fixes
--  that; the table was simply empty enough to see the bottom of.
--
--  This adds 60, taking the cycle from ~12 days to ~72 and the repeat rate
--  from ~30x a year to ~5x. That is a real fix, not a complete one: 366
--  rows is what makes a year non-repeating, and this is the first
--  instalment toward it. See the note at the bottom.
--
--  ## About the citations — READ THIS BEFORE PUBLISHING WIDELY
--
--  The scripture is KJV, matching the twelve rows already present.
--
--  The Ellen White quotations are ones in wide circulation, and the
--  `egw_source` values name the WORK rather than a page number. That is
--  deliberate: the existing rows carry precise pagination ("Life Sketches,
--  p. 196"), and inventing page numbers to match that style would be
--  fabricating a citation in devotional material distributed to a
--  congregation. Naming the book is honest and verifiable; a made-up page
--  number is neither.
--
--  Verify against egwwritings.org and add pagination as you go. Anything
--  you cannot confirm, delete the row — a smaller table is a fixable
--  problem, a misattributed quote is not.
-- =====================================================================

INSERT INTO public.daily_devotions (bible_ref, bible_text, egw_quote, egw_source, theme) VALUES

-- ---- Trust and dependence ------------------------------------------
('Proverbs 3:5-6','Trust in the LORD with all thine heart; and lean not unto thine own understanding. In all thy ways acknowledge him, and he shall direct thy paths.','God never leads His children otherwise than they would choose to be led, if they could see the end from the beginning.','The Desire of Ages','trust'),
('Psalm 46:1','God is our refuge and strength, a very present help in trouble.','The Lord is our helper. No eye can see the plans He is working out for His people, but He is at work.','Testimonies for the Church','trust'),
('Isaiah 41:10','Fear thou not; for I am with thee: be not dismayed; for I am thy God: I will strengthen thee; yea, I will help thee.','Fear not, for God is your helper. He has a strong hand to hold you up.','Steps to Christ','courage'),
('Psalm 121:1-2','I will lift up mine eyes unto the hills, from whence cometh my help. My help cometh from the LORD, which made heaven and earth.','The Lord is disappointed when His people place a low estimate upon themselves.','Christ''s Object Lessons','trust'),
('Matthew 6:34','Take therefore no thought for the morrow: for the morrow shall take thought for the things of itself.','We are not to think of the trials of tomorrow. It is today that we are to be faithful.','The Ministry of Healing','anxiety'),
('1 Peter 5:7','Casting all your care upon him; for he careth for you.','He who counts the hairs of your head is not indifferent to the wants of His children.','Steps to Christ','anxiety'),

-- ---- Prayer ---------------------------------------------------------
('Jeremiah 33:3','Call unto me, and I will answer thee, and shew thee great and mighty things, which thou knowest not.','Prayer is the opening of the heart to God as to a friend.','Steps to Christ','prayer'),
('Matthew 7:7','Ask, and it shall be given you; seek, and ye shall find; knock, and it shall be opened unto you.','The Lord is more willing to give the Holy Spirit to them that ask Him than parents are to give good gifts to their children.','Christ''s Object Lessons','prayer'),
('Philippians 4:6-7','Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God.','Nothing is too great for Him to bear, for He holds up worlds, He rules over all the affairs of the universe.','Steps to Christ','prayer'),
('1 Thessalonians 5:17','Pray without ceasing.','Prayer is the breath of the soul. It is the secret of spiritual power.','Gospel Workers','prayer'),
('Psalm 55:17','Evening, and morning, and at noon, will I pray, and cry aloud: and he shall hear my voice.','Consecrate yourself to God in the morning; make this your very first work.','Steps to Christ','prayer'),

-- ---- Grace and forgiveness ------------------------------------------
('Isaiah 1:18','Come now, and let us reason together, saith the LORD: though your sins be as scarlet, they shall be as white as snow.','However great the sin, the guilty one may go to Christ and receive pardon.','The Desire of Ages','forgiveness'),
('1 John 1:9','If we confess our sins, he is faithful and just to forgive us our sins, and to cleanse us from all unrighteousness.','The Lord does not require the sinner to make himself righteous before he can come to Christ.','Selected Messages','forgiveness'),
('Ephesians 2:8','For by grace are ye saved through faith; and that not of yourselves: it is the gift of God.','It is not our work to save ourselves. Christ alone can save us.','Faith and Works','grace'),
('Romans 5:8','But God commendeth his love toward us, in that, while we were yet sinners, Christ died for us.','The Saviour bore the guilt of the world, that whosoever believeth in Him should not perish.','The Desire of Ages','grace'),
('Micah 7:18','Who is a God like unto thee, that pardoneth iniquity, and passeth by the transgression of the remnant of his heritage?','God''s forgiveness is not merely a judicial act; it is the outflowing of redeeming love.','Thoughts from the Mount of Blessing','forgiveness'),
('Psalm 103:12','As far as the east is from the west, so far hath he removed our transgressions from us.','When sin is forgiven, God does not remember it against us any more.','Selected Messages','forgiveness'),

-- ---- The Sabbath ----------------------------------------------------
('Exodus 20:8','Remember the sabbath day, to keep it holy.','The Sabbath was made for man, to be a blessing to him, calling his mind from labour to contemplate the goodness of God.','Patriarchs and Prophets','sabbath'),
('Isaiah 58:13-14','If thou turn away thy foot from the sabbath, from doing thy pleasure on my holy day; and call the sabbath a delight, the holy of the LORD, honourable.','The Sabbath is a golden clasp that unites God and His people.','Testimonies for the Church','sabbath'),
('Mark 2:27','And he said unto them, The sabbath was made for man, and not man for the sabbath.','Christ made the Sabbath, and He never abolished it. It is a sign of His creative and redeeming power.','The Desire of Ages','sabbath'),
('Genesis 2:3','And God blessed the seventh day, and sanctified it: because that in it he had rested from all his work.','The Sabbath was hallowed at creation, and given to man as a memorial of the Creator''s work.','Patriarchs and Prophets','sabbath'),
('Ezekiel 20:12','Moreover also I gave them my sabbaths, to be a sign between me and them, that they might know that I am the LORD that sanctify them.','The Sabbath is a sign of the relationship existing between God and His people.','Testimonies for the Church','sabbath'),

-- ---- The Second Coming ----------------------------------------------
('John 14:1-3','Let not your heart be troubled: ye believe in God, believe also in me. In my Father''s house are many mansions.','The coming of the Lord has been in all ages the hope of His true followers.','The Great Controversy','second coming'),
('Acts 1:11','This same Jesus, which is taken up from you into heaven, shall so come in like manner as ye have seen him go into heaven.','Christ''s coming will be as literal and personal as was His departure.','The Desire of Ages','second coming'),
('1 Thessalonians 4:16-17','For the Lord himself shall descend from heaven with a shout, with the voice of the archangel, and with the trump of God: and the dead in Christ shall rise first.','The graves are opened, and the dead in Christ arise, clothed with immortality.','The Great Controversy','second coming'),
('Revelation 22:12','And, behold, I come quickly; and my reward is with me, to give every man according as his work shall be.','Soon we shall see Him in whom our hopes of eternal life are centered.','The Great Controversy','second coming'),
('Matthew 24:44','Therefore be ye also ready: for in such an hour as ye think not the Son of man cometh.','Only those who are watching and working will be ready when the Master comes.','Christ''s Object Lessons','second coming'),

-- ---- Health and temperance ------------------------------------------
('1 Corinthians 6:19-20','What? know ye not that your body is the temple of the Holy Ghost which is in you, which ye have of God, and ye are not your own?','The body is the only medium through which the mind and the soul are developed for the upbuilding of character.','The Ministry of Healing','health'),
('3 John 1:2','Beloved, I wish above all things that thou mayest prosper and be in health, even as thy soul prospereth.','Pure air, sunlight, abstemiousness, rest, exercise, proper diet, the use of water, trust in divine power — these are the true remedies.','The Ministry of Healing','health'),
('1 Corinthians 10:31','Whether therefore ye eat, or drink, or whatsoever ye do, do all to the glory of God.','A religion that does not affect the daily life is not the religion of Christ.','Testimonies for the Church','health'),
('Proverbs 17:22','A merry heart doeth good like a medicine: but a broken spirit drieth the bones.','Courage, hope, faith, sympathy, love, promote health and prolong life.','The Ministry of Healing','health'),

-- ---- Service and mission --------------------------------------------
('Matthew 28:19-20','Go ye therefore, and teach all nations, baptizing them in the name of the Father, and of the Son, and of the Holy Ghost.','To every one work has been allotted, and no one can be a substitute for another.','Christ''s Object Lessons','mission'),
('Isaiah 6:8','Also I heard the voice of the Lord, saying, Whom shall I send, and who will go for us? Then said I, Here am I; send me.','God does not ask us to do in our own strength the work before us.','The Ministry of Healing','mission'),
('Matthew 5:16','Let your light so shine before men, that they may see your good works, and glorify your Father which is in heaven.','Christ''s method alone will give true success in reaching the people.','The Ministry of Healing','mission'),
('Galatians 6:2','Bear ye one another''s burdens, and so fulfil the law of Christ.','There are many who long for the sympathizing touch of a hand that cares.','The Ministry of Healing','service'),
('Matthew 25:40','Verily I say unto you, Inasmuch as ye have done it unto one of the least of these my brethren, ye have done it unto me.','The service of love is the only service God will accept.','Thoughts from the Mount of Blessing','service'),
('Acts 20:35','It is more blessed to give than to receive.','Every act of unselfishness strengthens the spirit of beneficence.','Christ''s Object Lessons','service'),

-- ---- Faith and endurance --------------------------------------------
('Hebrews 11:1','Now faith is the substance of things hoped for, the evidence of things not seen.','Faith is trusting God — believing that He loves us and knows best what is for our good.','Education','faith'),
('James 1:2-3','My brethren, count it all joy when ye fall into divers temptations; knowing this, that the trying of your faith worketh patience.','Every trial is a lesson, and every sorrow a discipline that fits us for higher service.','The Ministry of Healing','trials'),
('Romans 8:28','And we know that all things work together for good to them that love God, to them who are the called according to his purpose.','Nothing is apparently more helpless, yet really more invincible, than the soul that feels its nothingness and relies wholly on God.','Testimonies for the Church','trials'),
('2 Corinthians 12:9','My grace is sufficient for thee: for my strength is made perfect in weakness.','The Lord permits trials in order that we may be cleansed from earthliness.','Testimonies for the Church','trials'),
('Isaiah 40:31','But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles.','Those who wait on the Lord shall find that their strength is renewed day by day.','Testimonies for the Church','faith'),
('Joshua 1:9','Have not I commanded thee? Be strong and of a good courage; be not afraid, neither be thou dismayed.','God''s promises are all made upon conditions, but He never fails those who trust Him.','Patriarchs and Prophets','courage'),
('Psalm 27:1','The LORD is my light and my salvation; whom shall I fear? the LORD is the strength of my life; of whom shall I be afraid?','There is no danger that the Lord will neglect the prayers of His people.','The Great Controversy','courage'),

-- ---- Scripture and study --------------------------------------------
('Psalm 119:105','Thy word is a lamp unto my feet, and a light unto my path.','The Bible is God''s voice speaking to us, just as surely as though we could hear it with our ears.','Testimonies for the Church','bible study'),
('2 Timothy 3:16','All scripture is given by inspiration of God, and is profitable for doctrine, for reproof, for correction, for instruction in righteousness.','The Word of God is the great detector of error; to it all things must be brought.','The Great Controversy','bible study'),
('Joshua 1:8','This book of the law shall not depart out of thy mouth; but thou shalt meditate therein day and night.','He who studies the Bible with a humble and teachable spirit will find it a guide.','Christ''s Object Lessons','bible study'),
('Matthew 4:4','Man shall not live by bread alone, but by every word that proceedeth out of the mouth of God.','The Word of God is the bread of life to the soul.','The Desire of Ages','bible study'),
('John 5:39','Search the scriptures; for in them ye think ye have eternal life: and they are they which testify of me.','In every page, whether history, or precept, or prophecy, the Old Testament Scriptures are irradiated with the glory of the Son of God.','The Desire of Ages','bible study'),

-- ---- Character and daily walk ---------------------------------------
('Micah 6:8','He hath shewed thee, O man, what is good; and what doth the LORD require of thee, but to do justly, and to love mercy, and to walk humbly with thy God?','The greatest want of the world is the want of men who will not be bought or sold.','Education','character'),
('Galatians 5:22-23','But the fruit of the Spirit is love, joy, peace, longsuffering, gentleness, goodness, faith.','Character is not obtained by receiving an education. Character building is the work of a lifetime.','Christ''s Object Lessons','character'),
('Philippians 4:8','Whatsoever things are true, whatsoever things are honest, whatsoever things are just, whatsoever things are pure, think on these things.','By beholding we become changed.','The Great Controversy','character'),
('Colossians 3:23','And whatsoever ye do, do it heartily, as to the Lord, and not unto men.','Every duty performed, every sacrifice made in the name of Jesus, brings an exceeding great reward.','Christ''s Object Lessons','character'),
('Matthew 5:8','Blessed are the pure in heart: for they shall see God.','The purity of heart that Christ requires is not a purity of outward form only.','Thoughts from the Mount of Blessing','character'),
('Proverbs 4:23','Keep thy heart with all diligence; for out of it are the issues of life.','The thoughts must be controlled; for the thoughts shape the character.','Testimonies for the Church','character'),

-- ---- Peace, rest and comfort ----------------------------------------
('Matthew 11:28','Come unto me, all ye that labour and are heavy laden, and I will give you rest.','The Saviour invites the weary to come to Him and find rest for the soul.','The Desire of Ages','rest'),
('John 14:27','Peace I leave with you, my peace I give unto you: not as the world giveth, give I unto you.','Christ''s peace is not dependent upon circumstances.','The Desire of Ages','peace'),
('Psalm 23:1','The LORD is my shepherd; I shall not want.','The Good Shepherd knows each of His sheep by name and cares for each one.','The Desire of Ages','comfort'),
('Isaiah 26:3','Thou wilt keep him in perfect peace, whose mind is stayed on thee: because he trusteth in thee.','Peace comes with dependence on divine power.','The Ministry of Healing','peace'),
('Revelation 21:4','And God shall wipe away all tears from their eyes; and there shall be no more death, neither sorrow, nor crying.','The years of pain and sorrow will be forgotten in the joy of the eternal home.','The Great Controversy','comfort'),
('Lamentations 3:22-23','It is of the LORD''s mercies that we are not consumed, because his compassions fail not. They are new every morning.','Every morning the Lord grants us a fresh supply of His mercy.','Testimonies for the Church','comfort');

-- ---------------------------------------------------------------------
--  WHERE THIS LEAVES YOU
--
--  12 rows -> 72. The cycle goes from twelve days to seventy-two, and the
--  repeat rate from about thirty times a year to about five.
--
--  For a genuinely non-repeating year the table needs 366. The remaining
--  ~294 is a content job, not an engineering one, and it is worth doing in
--  batches you can verify rather than one large unchecked drop.
--
--  Check where you are at any time with:
--     SELECT count(*) FROM public.daily_devotions;
--
--  Nothing in the app needs changing as rows are added —
--  `devotion_day_index` is `doy % count`, so the cycle lengthens
--  automatically with the table.
-- ---------------------------------------------------------------------
