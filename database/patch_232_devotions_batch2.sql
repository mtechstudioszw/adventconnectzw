-- =====================================================================
--  PATCH 232 — Devotions, batch 2 (+ dedupe of six from batch 1)
--
--  Continues the work of patch_231 toward a non-repeating year.
--
--  ## First, a correction
--
--  patch_231 added six verses that were ALREADY among the original twelve:
--  Psalm 46:1, Isaiah 41:10, Revelation 22:12, and near-duplicates of
--  Philippians 4:6, John 14:1 and Lamentations 3:22. Two devotions built on
--  the same verse a few days apart is exactly the "it feels repetitive"
--  complaint this work exists to fix, so they go before anything is added.
--
--  Scoped to id > 12 so only the batch_231 copies are removed and the
--  original twelve are untouched.
--
--  ## Citations — unchanged policy, and still your job to verify
--
--  Scripture is KJV. The Ellen White quotations are widely circulated ones
--  and `egw_source` names the WORK, never a page number, for the reason
--  given in patch_231: inventing pagination to match the original rows'
--  style would be fabricating a citation in devotional material read by a
--  congregation.
--
--  I checked whether the quotes could be drawn from an actual EGW corpus
--  instead of recall — the app has EGW books, but they are downloaded
--  EPUBs on the device, and there is no text table in this database to
--  select from. So verification against egwwritings.org remains a manual
--  step. Delete any row you cannot confirm; a shorter table is a fixable
--  problem and a misattributed quote is not.
-- =====================================================================

-- ---- dedupe batch 1 --------------------------------------------------
DELETE FROM public.daily_devotions
 WHERE id > 12
   AND bible_ref IN (
     'Psalm 46:1',
     'Isaiah 41:10',
     'Revelation 22:12',
     'Philippians 4:6-7',
     'John 14:1-3',
     'Lamentations 3:22-23'
   );

-- ---- batch 2 ---------------------------------------------------------
INSERT INTO public.daily_devotions (bible_ref, bible_text, egw_quote, egw_source, theme) VALUES

-- Creation
('Genesis 1:1','In the beginning God created the heaven and the earth.','Nature is God''s servant. Through the things of nature He speaks to us of His love.','Steps to Christ','creation'),
('Psalm 19:1','The heavens declare the glory of God; and the firmament sheweth his handywork.','Upon all created things is seen the impress of the Deity.','Education','creation'),
('Psalm 8:3-4','When I consider thy heavens, the work of thy fingers, the moon and the stars, which thou hast ordained; what is man, that thou art mindful of him?','God is the source of life and light and joy to the whole universe.','Steps to Christ','creation'),
('Nehemiah 9:6','Thou, even thou, art LORD alone; thou hast made heaven, the heaven of heavens, with all their host, the earth, and all things that are therein.','The Creator of all things is the sustainer of all things.','Patriarchs and Prophets','creation'),

-- The love of God
('John 3:16','For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.','The gift of Christ reveals the Father''s heart of love.','Steps to Christ','love of God'),
('1 John 4:19','We love him, because he first loved us.','Love cannot long exist without expression.','The Adventist Home','love of God'),
('Jeremiah 31:3','Yea, I have loved thee with an everlasting love: therefore with lovingkindness have I drawn thee.','The love of God still yearns over the one who has chosen to separate from Him.','Christ''s Object Lessons','love of God'),
('Romans 8:38-39','For I am persuaded, that neither death, nor life, nor angels, nor principalities, nor powers, shall be able to separate us from the love of God.','Nothing can separate the trusting soul from the love of God.','Testimonies for the Church','love of God'),
('Zephaniah 3:17','The LORD thy God in the midst of thee is mighty; he will save, he will rejoice over thee with joy.','God rejoices over His people with singing.','Prophets and Kings','love of God'),
('1 John 3:1','Behold, what manner of love the Father hath bestowed upon us, that we should be called the sons of God.','It is no ordinary love that the Father has bestowed upon us.','Steps to Christ','love of God'),

-- Obedience and the law
('John 14:15','If ye love me, keep my commandments.','Obedience is the fruit of love, not the price of it.','Steps to Christ','obedience'),
('Ecclesiastes 12:13','Let us hear the conclusion of the whole matter: Fear God, and keep his commandments: for this is the whole duty of man.','The law of God is as sacred as Himself.','The Great Controversy','obedience'),
('1 John 5:3','For this is the love of God, that we keep his commandments: and his commandments are not grievous.','God''s commandments are not a burden to the heart that loves Him.','Thoughts from the Mount of Blessing','obedience'),
('James 1:22','But be ye doers of the word, and not hearers only, deceiving your own selves.','It is not enough to know the truth; it must be lived.','Christ''s Object Lessons','obedience'),
('Psalm 40:8','I delight to do thy will, O my God: yea, thy law is within my heart.','When the law is written in the heart, obedience becomes a delight.','The Desire of Ages','obedience'),
('Deuteronomy 6:5','And thou shalt love the LORD thy God with all thine heart, and with all thy soul, and with all thy might.','God asks for the whole heart, and He will accept nothing less.','Steps to Christ','obedience'),

-- Humility
('James 4:10','Humble yourselves in the sight of the Lord, and he shall lift you up.','The higher a Christian rises, the lower he will feel himself to be.','Testimonies for the Church','humility'),
('1 Peter 5:5','Be clothed with humility: for God resisteth the proud, and giveth grace to the humble.','Humility is the badge of the true follower of Christ.','The Desire of Ages','humility'),
('Philippians 2:3','Let nothing be done through strife or vainglory; but in lowliness of mind let each esteem other better than themselves.','Christ pleased not Himself, and this is the mind we are to have.','The Desire of Ages','humility'),
('Proverbs 16:18','Pride goeth before destruction, and an haughty spirit before a fall.','Self-exaltation has been the ruin of many a promising life.','Testimonies for the Church','humility'),
('Matthew 23:12','And whosoever shall exalt himself shall be abased; and he that shall humble himself shall be exalted.','The greatest in God''s kingdom is the one who serves.','The Desire of Ages','humility'),

-- Gratitude
('Psalm 100:4','Enter into his gates with thanksgiving, and into his courts with praise: be thankful unto him, and bless his name.','Nothing tends more to promote health of body and soul than a spirit of gratitude and praise.','The Ministry of Healing','gratitude'),
('1 Thessalonians 5:18','In every thing give thanks: for this is the will of God in Christ Jesus concerning you.','We should talk less of our trials and more of the mercies of God.','Steps to Christ','gratitude'),
('Psalm 107:1','O give thanks unto the LORD, for he is good: for his mercy endureth for ever.','Let us count the Lord''s blessings and remember His loving-kindness.','Testimonies for the Church','gratitude'),
('Colossians 3:15','And let the peace of God rule in your hearts, to the which also ye are called in one body; and be ye thankful.','A thankful heart is a heart at rest.','The Ministry of Healing','gratitude'),

-- Stewardship
('Malachi 3:10','Bring ye all the tithes into the storehouse, that there may be meat in mine house, and prove me now herewith, saith the LORD of hosts.','God has given us the privilege of being co-workers with Him in the use of His means.','Counsels on Stewardship','stewardship'),
('Luke 16:10','He that is faithful in that which is least is faithful also in much.','Faithfulness in little things is the test of character.','Christ''s Object Lessons','stewardship'),
('1 Corinthians 4:2','Moreover it is required in stewards, that a man be found faithful.','Everything we have is a trust from God, to be used for His glory.','Christ''s Object Lessons','stewardship'),
('Proverbs 3:9','Honour the LORD with thy substance, and with the firstfruits of all thine increase.','Giving is a privilege, not a tax.','Counsels on Stewardship','stewardship'),
('2 Corinthians 9:7','God loveth a cheerful giver.','The spirit of liberality is the spirit of heaven.','Christ''s Object Lessons','stewardship'),

-- Family and home
('Joshua 24:15','As for me and my house, we will serve the LORD.','The home should be to the children the most attractive place in the world.','The Adventist Home','family'),
('Proverbs 22:6','Train up a child in the way he should go: and when he is old, he will not depart from it.','The work of the parent is the most important work given to human beings.','The Adventist Home','family'),
('Deuteronomy 6:6-7','And these words, which I command thee this day, shall be in thine heart: and thou shalt teach them diligently unto thy children.','The religion of the home is the religion that tells.','The Adventist Home','family'),
('Ephesians 5:25','Husbands, love your wives, even as Christ also loved the church, and gave himself for it.','Love is the principle that must govern the home.','The Adventist Home','family'),
('Psalm 127:3','Lo, children are an heritage of the LORD: and the fruit of the womb is his reward.','Children are the heritage of the Lord, entrusted to us for a season.','The Adventist Home','family'),

-- Temptation
('1 Corinthians 10:13','There hath no temptation taken you but such as is common to man: but God is faithful, who will not suffer you to be tempted above that ye are able.','God never leaves us to be overcome; there is always a way of escape.','Testimonies for the Church','temptation'),
('James 4:7','Submit yourselves therefore to God. Resist the devil, and he will flee from you.','Satan cannot compel us to do wrong; he can only tempt.','The Great Controversy','temptation'),
('Hebrews 4:15','For we have not an high priest which cannot be touched with the feeling of our infirmities; but was in all points tempted like as we are, yet without sin.','Christ knows the strength of every temptation, for He has felt it.','The Desire of Ages','temptation'),
('Matthew 26:41','Watch and pray, that ye enter not into temptation: the spirit indeed is willing, but the flesh is weak.','Watchfulness and prayer are the safeguards of the soul.','The Great Controversy','temptation'),

-- The Holy Spirit
('John 14:26','But the Comforter, which is the Holy Ghost, whom the Father will send in my name, he shall teach you all things.','The Holy Spirit is the highest of all gifts that God could solicit from His Father.','Testimonies to Ministers','holy spirit'),
('Acts 1:8','But ye shall receive power, after that the Holy Ghost is come upon you: and ye shall be witnesses unto me.','The promise of the Spirit is not limited to any age or race.','The Acts of the Apostles','holy spirit'),
('Zechariah 4:6','Not by might, nor by power, but by my spirit, saith the LORD of hosts.','Human effort avails nothing without the divine Spirit.','The Desire of Ages','holy spirit'),
('Ezekiel 36:26','A new heart also will I give you, and a new spirit will I put within you.','The change of heart is the work of God alone.','The Desire of Ages','holy spirit'),
('Romans 8:26','Likewise the Spirit also helpeth our infirmities: for we know not what we should pray for as we ought.','The Spirit interprets the desires we cannot put into words.','Steps to Christ','holy spirit'),

-- Wisdom
('James 1:5','If any of you lack wisdom, let him ask of God, that giveth to all men liberally, and upbraideth not; and it shall be given him.','God is willing to give wisdom to all who ask in faith.','Christ''s Object Lessons','wisdom'),
('Proverbs 9:10','The fear of the LORD is the beginning of wisdom: and the knowledge of the holy is understanding.','True education is the harmonious development of the whole being.','Education','wisdom'),
('Colossians 4:6','Let your speech be alway with grace, seasoned with salt, that ye may know how ye ought to answer every man.','Kind words are as dew and gentle showers to the soul.','The Adventist Home','wisdom'),

-- Joy and contentment
('Nehemiah 8:10','The joy of the LORD is your strength.','A cheerful spirit is a continual feast.','The Ministry of Healing','joy'),
('Psalm 16:11','In thy presence is fulness of joy; at thy right hand there are pleasures for evermore.','The joy Christ gives is a well of water springing up unto everlasting life.','The Desire of Ages','joy'),
('Philippians 4:11','I have learned, in whatsoever state I am, therewith to be content.','Contentment is learned, not inherited.','The Ministry of Healing','contentment'),
('1 Timothy 6:6','But godliness with contentment is great gain.','He is rich who has learned to be satisfied with what God provides.','Counsels on Stewardship','contentment'),
('Psalm 118:24','This is the day which the LORD hath made; we will rejoice and be glad in it.','Every day brings its own mercies, new and undeserved.','Steps to Christ','joy'),

-- Forgiving others
('Matthew 6:14','For if ye forgive men their trespasses, your heavenly Father will also forgive you.','We cannot receive what we are unwilling to give.','Thoughts from the Mount of Blessing','forgiving others'),
('Ephesians 4:32','And be ye kind one to another, tenderhearted, forgiving one another, even as God for Christ''s sake hath forgiven you.','Nothing can justify an unforgiving spirit.','Thoughts from the Mount of Blessing','forgiving others'),
('Colossians 3:13','Forbearing one another, and forgiving one another, if any man have a quarrel against any: even as Christ forgave you, so also do ye.','The love of Christ in the heart makes forgiveness possible.','The Desire of Ages','forgiving others'),
('Matthew 18:21-22','Lord, how oft shall my brother sin against me, and I forgive him? till seven times? Jesus saith unto him, I say not unto thee, Until seven times: but, Until seventy times seven.','God''s forgiveness of us sets the measure of our forgiveness of others.','Christ''s Object Lessons','forgiving others'),

-- Guidance
('Psalm 32:8','I will instruct thee and teach thee in the way which thou shalt go: I will guide thee with mine eye.','God will guide every step, if we are willing to be led.','The Ministry of Healing','guidance'),
('Proverbs 16:9','A man''s heart deviseth his way: but the LORD directeth his steps.','Our plans are not always God''s plans, and His are always better.','The Ministry of Healing','guidance'),
('Isaiah 30:21','And thine ears shall hear a word behind thee, saying, This is the way, walk ye in it.','The Lord guides those who are willing to be guided.','Testimonies for the Church','guidance'),
('Jeremiah 29:11','For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.','God''s purposes toward His children are always purposes of good.','The Ministry of Healing','guidance'),

-- Comfort in sorrow
('Psalm 34:18','The LORD is nigh unto them that are of a broken heart; and saveth such as be of a contrite spirit.','Jesus is near to every sorrowing soul.','The Desire of Ages','comfort'),
('Matthew 5:4','Blessed are they that mourn: for they shall be comforted.','Sorrow, borne with Christ, becomes a means of blessing.','Thoughts from the Mount of Blessing','comfort'),
('John 11:25','I am the resurrection, and the life: he that believeth in me, though he were dead, yet shall he live.','To the believer, death is but a sleep.','The Desire of Ages','comfort'),
('2 Corinthians 1:3-4','Blessed be God, even the Father of our Lord Jesus Christ, the Father of mercies, and the God of all comfort; who comforteth us in all our tribulation.','Those who have been comforted are best able to comfort others.','The Ministry of Healing','comfort'),

-- Witness and mission
('1 Peter 3:15','Be ready always to give an answer to every man that asketh you a reason of the hope that is in you with meekness and fear.','Every true disciple is born into the kingdom of God as a missionary.','The Desire of Ages','witness'),
('Mark 16:15','Go ye into all the world, and preach the gospel to every creature.','The gospel is to be carried to every nation and tongue and people.','The Acts of the Apostles','witness'),
('Daniel 12:3','And they that be wise shall shine as the brightness of the firmament; and they that turn many to righteousness as the stars for ever and ever.','No work done for Christ is ever lost.','Christ''s Object Lessons','witness'),
('Romans 1:16','For I am not ashamed of the gospel of Christ: for it is the power of God unto salvation to every one that believeth.','The gospel has lost none of its power.','The Acts of the Apostles','witness'),

-- Youth
('Ecclesiastes 12:1','Remember now thy Creator in the days of thy youth.','The youth are the strength of the church, and its hope.','Messages to Young People','youth'),
('1 Timothy 4:12','Let no man despise thy youth; but be thou an example of the believers.','God has a work for every young person to do.','Messages to Young People','youth'),
('Psalm 119:9','Wherewithal shall a young man cleanse his way? by taking heed thereto according to thy word.','The Word of God is the safeguard of youth.','Messages to Young People','youth'),

-- Patience and perseverance
('Psalm 27:14','Wait on the LORD: be of good courage, and he shall strengthen thine heart.','God''s delays are not denials.','Testimonies for the Church','patience'),
('Galatians 6:9','And let us not be weary in well doing: for in due season we shall reap, if we faint not.','Perseverance is the test of genuine faith.','Christ''s Object Lessons','patience'),
('Hebrews 10:36','For ye have need of patience, that, after ye have done the will of God, ye might receive the promise.','Patience is faith holding on when it cannot see.','Testimonies for the Church','patience'),
('Romans 12:12','Rejoicing in hope; patient in tribulation; continuing instant in prayer.','Hope makes the burden light.','The Ministry of Healing','patience'),

-- Generosity
('Proverbs 19:17','He that hath pity upon the poor lendeth unto the LORD; and that which he hath given will he pay him again.','Whatever is done for the poor is done for Christ.','The Desire of Ages','generosity'),
('Luke 6:38','Give, and it shall be given unto you; good measure, pressed down, and shaken together, and running over.','The more we give, the more we receive.','Christ''s Object Lessons','generosity'),
('Proverbs 11:25','The liberal soul shall be made fat: and he that watereth shall be watered also himself.','Selfishness shrinks the soul; generosity enlarges it.','Christ''s Object Lessons','generosity'),

-- New birth and salvation
('John 3:3','Except a man be born again, he cannot see the kingdom of God.','The new birth is a change of heart wrought by the Spirit of God.','The Desire of Ages','salvation'),
('2 Corinthians 5:17','Therefore if any man be in Christ, he is a new creature: old things are passed away; behold, all things are become new.','When Christ dwells within, the whole life is changed.','Steps to Christ','salvation'),
('Acts 4:12','Neither is there salvation in any other: for there is none other name under heaven given among men, whereby we must be saved.','There is no other name by which we may be saved.','The Acts of the Apostles','salvation'),
('Titus 3:5','Not by works of righteousness which we have done, but according to his mercy he saved us.','We are saved by grace, and grace alone.','Faith and Works','salvation'),

-- The sanctuary and Christ our High Priest
('Hebrews 4:16','Let us therefore come boldly unto the throne of grace, that we may obtain mercy, and find grace to help in time of need.','Christ our High Priest pleads His blood before the Father for us.','The Great Controversy','sanctuary'),
('Hebrews 8:1','We have such an high priest, who is set on the right hand of the throne of the Majesty in the heavens.','The intercession of Christ is as real as His death on the cross.','The Great Controversy','sanctuary'),
('Hebrews 9:24','For Christ is not entered into the holy places made with hands, but into heaven itself, now to appear in the presence of God for us.','Our Advocate stands in the presence of God on our behalf.','The Great Controversy','sanctuary'),

-- Prophecy
('Amos 3:7','Surely the Lord GOD will do nothing, but he revealeth his secret unto his servants the prophets.','God has never left His people without warning of what is coming.','Prophets and Kings','prophecy'),
('Daniel 2:44','And in the days of these kings shall the God of heaven set up a kingdom, which shall never be destroyed.','The kingdoms of this world will pass; God''s kingdom stands for ever.','Prophets and Kings','prophecy'),
('2 Peter 1:19','We have also a more sure word of prophecy; whereunto ye do well that ye take heed, as unto a light that shineth in a dark place.','Prophecy is a light for the darkness of the last days.','The Great Controversy','prophecy'),
('Revelation 1:3','Blessed is he that readeth, and they that hear the words of this prophecy.','The book of Revelation is opened to all who will study it prayerfully.','The Acts of the Apostles','prophecy'),

-- Heaven
('1 Corinthians 2:9','Eye hath not seen, nor ear heard, neither have entered into the heart of man, the things which God hath prepared for them that love him.','The language of earth is too poor to describe the reward of the righteous.','The Great Controversy','heaven'),
('Isaiah 65:17','For, behold, I create new heavens and a new earth: and the former shall not be remembered.','There the redeemed shall know even as also they are known.','The Great Controversy','heaven'),
('Revelation 21:3','Behold, the tabernacle of God is with men, and he will dwell with them, and they shall be his people.','God Himself will dwell with His people at last.','The Great Controversy','heaven');

-- ---------------------------------------------------------------------
--  Run this afterwards to see where you now stand:
--     SELECT count(*) FROM public.daily_devotions;
--
--  Nothing in the app needs changing as rows are added —
--  devotion_day_index is `doy % count`, so the repeat cycle lengthens
--  automatically with the table.
-- ---------------------------------------------------------------------
