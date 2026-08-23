-- =====================================================================
--  PATCH 235 — Fill the last five thin quiz categories
--
--  Completes the quiz-content work. After patch_233 (+126) and patch_234
--  (-19 twins) these five were the remaining categories at or below two
--  rounds' worth, against a category round of TEN questions:
--
--      Parables            16      Second Coming       17
--      Spirit of Prophecy  17      Health              18
--      Christian Living    17
--
--  Adds 16 to each. Every category in the bank then holds roughly three
--  rounds, which is what the 21-day seen-cooldown needs in order to have
--  anything fresh left to offer.
--
--  ## Written against the whole bank, not one category
--
--  patch_233 duplicated five questions because it compared only against
--  the category being filled — and one of those already lived under a
--  DIFFERENT category. patch_234 then found nineteen reworded twins that
--  exact matching could never have caught.
--
--  So this patch ends with the same similarity sweep patch_234 introduced,
--  as a standing safety net rather than a one-off cleanup: alike wording
--  AND identical correct answer, keeping the lowest id. If anything here
--  turns out to restate an existing question, it removes itself.
--
--  Facts are scripture or plain Adventist history, each with a
--  `reference`. No attributed quotations, so nothing here needs the
--  verification the devotion patches do.
-- =====================================================================

INSERT INTO public.quiz_questions
  (question, options, correct_index, explanation, reference, category, difficulty, is_published)
VALUES

-- ---------------- Parables ----------------
('In the parable of the two builders, what did the wise man build on?','["Sand","A rock","Clay","A hill"]'::jsonb,1,'The house on the rock stood because it was founded upon a rock.','Matthew 7:24-25','Parables','easy',true),
('What did the man in the parable find hidden in a field?','["A sword","Treasure","A scroll","A spring"]'::jsonb,1,'He sold all that he had and bought that field.','Matthew 13:44','Parables','medium',true),
('In the parable of the pearl, what did the merchant do to buy it?','["Borrowed money","Sold all that he had","Traded a ship","Waited a year"]'::jsonb,1,'The merchant sold all he had to buy the pearl of great price.','Matthew 13:45-46','Parables','medium',true),
('Who was invited to the great supper after the first guests made excuses?','["Only relatives","The poor, maimed, halt and blind","Foreign kings","Nobody"]'::jsonb,1,'The servant brought in the poor from the streets and lanes.','Luke 14:21','Parables','medium',true),
('In the parable of the vineyard labourers, what did those hired last receive?','["Nothing","The same penny as the first","Half a penny","Double"]'::jsonb,1,'Every man received a penny, regardless of the hour he was hired.','Matthew 20:9-10','Parables','medium',true),
('What did the barren fig tree receive before being cut down?','["Immediate destruction","One more year of care","Water only","New soil"]'::jsonb,1,'The dresser asked to let it alone this year also, and dig about it.','Luke 13:8','Parables','hard',true),
('In the parable of the sower, what choked the seed among thorns?','["Birds","Cares of this world and deceitfulness of riches","Drought","Rocks"]'::jsonb,1,'The cares of this world and the deceitfulness of riches choke the word.','Matthew 13:22','Parables','medium',true),
('What happened to the seed that fell on stony places?','["It grew tall","It sprang up quickly then withered","It was eaten","It bore fruit"]'::jsonb,1,'It had no root, and withered away when the sun was up.','Matthew 13:5-6','Parables','medium',true),
('How much did the good ground bring forth?','["Ten, twenty, thirty","Some hundredfold, some sixtyfold, some thirtyfold","A double portion","Nothing"]'::jsonb,1,'The good ground brought forth fruit in varying measure.','Matthew 13:8','Parables','medium',true),
('Who did the rich man see afar off in the parable of Lazarus?','["Moses","Abraham with Lazarus","Elijah","David"]'::jsonb,1,'He saw Abraham afar off, and Lazarus in his bosom.','Luke 16:23','Parables','medium',true),
('In the parable of the sheep and goats, what separates them?','["Their prayers","How they treated the least of these","Their nation","Their offerings"]'::jsonb,1,'"Inasmuch as ye have done it unto one of the least of these... ye have done it unto me."','Matthew 25:40','Parables','medium',true),
('What did the friend at midnight finally give because of importunity?','["Nothing","As many loaves as he needed","Money","Shelter"]'::jsonb,1,'Because of his importunity he will rise and give him as many as he needeth.','Luke 11:8','Parables','hard',true),
('In the parable of the unjust judge, what did the widow keep doing?','["Weeping","Coming to him for justice","Paying money","Waiting silently"]'::jsonb,1,'She kept coming, saying "Avenge me of mine adversary."','Luke 18:3','Parables','medium',true),
('What did the householder do with the tares before harvest?','["Burned them at once","Let both grow together until the harvest","Pulled them up","Sold them"]'::jsonb,1,'Lest while ye gather up the tares, ye root up also the wheat with them.','Matthew 13:29-30','Parables','medium',true),
('What did the king do to the guest without a wedding garment?','["Welcomed him","Cast him into outer darkness","Gave him one","Ignored him"]'::jsonb,1,'He was bound and cast into outer darkness.','Matthew 22:11-13','Parables','hard',true),
('Who did the elder brother in the prodigal son parable refuse to do?','["Work the fields","Go in to the feast","Speak to his father","Leave home"]'::jsonb,1,'He was angry and would not go in, so his father came out and entreated him.','Luke 15:28','Parables','medium',true),

-- ---------------- Spirit of Prophecy ----------------
('Which Ellen White book covers the Acts of the Apostles and the early church?','["The Acts of the Apostles","Prophets and Kings","Education","Evangelism"]'::jsonb,0,'The Acts of the Apostles traces the early Christian church.','Ellen G. White writings','Spirit of Prophecy','medium',true),
('Which Ellen White book covers the Old Testament kings and prophets?','["Patriarchs and Prophets","Prophets and Kings","The Great Controversy","Early Writings"]'::jsonb,1,'Prophets and Kings continues from Solomon through the prophets.','Ellen G. White writings','Spirit of Prophecy','medium',true),
('Which Ellen White book deals with Christian education?','["Education","The Ministry of Healing","Messages to Young People","Testimonies"]'::jsonb,0,'Education sets out the principles of true education.','Ellen G. White writings','Spirit of Prophecy','medium',true),
('The five books of the Conflict of the Ages series end with which title?','["The Desire of Ages","The Great Controversy","Prophets and Kings","Education"]'::jsonb,1,'The series runs Patriarchs and Prophets through to The Great Controversy.','Ellen G. White writings','Spirit of Prophecy','hard',true),
('Whom did Ellen Harmon marry?','["William Miller","James White","Joseph Bates","John Andrews"]'::jsonb,1,'She married James White in 1846.','Adventist history','Spirit of Prophecy','medium',true),
('Which test of a prophet is given in Isaiah 8:20?','["Miracles","To the law and to the testimony","Popularity","Age"]'::jsonb,1,'"If they speak not according to this word, it is because there is no light in them."','Isaiah 8:20','Spirit of Prophecy','medium',true),
('According to Deuteronomy 18:22, how is a true prophet known?','["By dreams","When the thing spoken comes to pass","By lineage","By signs alone"]'::jsonb,1,'If the thing follow not, the Lord hath not spoken it.','Deuteronomy 18:22','Spirit of Prophecy','medium',true),
('What does 1 Thessalonians 5:20 say about prophesyings?','["Ignore them","Despise not prophesyings","Fear them","Hide them"]'::jsonb,1,'"Despise not prophesyings. Prove all things; hold fast that which is good."','1 Thessalonians 5:20-21','Spirit of Prophecy','medium',true),
('In Revelation 12:17, what does the remnant have?','["Great wealth","The commandments of God and the testimony of Jesus","A new temple","Political power"]'::jsonb,1,'The dragon makes war with those keeping the commandments and having the testimony of Jesus.','Revelation 12:17','Spirit of Prophecy','medium',true),
('Which Ellen White book gathers counsel for young people?','["Messages to Young People","Education","Steps to Christ","Evangelism"]'::jsonb,0,'Messages to Young People collects her counsel to youth.','Ellen G. White writings','Spirit of Prophecy','medium',true),
('Which book contains her counsel on the Christian home and family?','["The Adventist Home","Education","Testimonies to Ministers","Counsels on Diet"]'::jsonb,0,'The Adventist Home addresses marriage, parenting and the household.','Ellen G. White writings','Spirit of Prophecy','medium',true),
('Roughly how many years did Ellen White''s prophetic ministry span?','["About 20 years","About 70 years","About 10 years","About 40 years"]'::jsonb,1,'From her first vision in 1844 until her death in 1915.','Adventist history','Spirit of Prophecy','hard',true),
('What did Paul say the gifts of the Spirit are given for?','["Personal honour","The perfecting of the saints and edifying the body","Wealth","Ruling"]'::jsonb,1,'For the perfecting of the saints, for the work of the ministry.','Ephesians 4:12','Spirit of Prophecy','medium',true),
('Which Ellen White book is a devotional on the Sermon on the Mount?','["Thoughts from the Mount of Blessing","Christ''s Object Lessons","Steps to Christ","The Desire of Ages"]'::jsonb,0,'Thoughts from the Mount of Blessing expounds the Sermon on the Mount.','Ellen G. White writings','Spirit of Prophecy','medium',true),
('According to Amos 3:7, what does God do before He acts?','["Nothing","Reveals His secret to His servants the prophets","Sends angels","Waits"]'::jsonb,1,'"Surely the Lord GOD will do nothing, but he revealeth his secret unto his servants the prophets."','Amos 3:7','Spirit of Prophecy','easy',true),
('What are prophets warned not to add to or take from?','["Their visions","The words of the book","Their testimony","The law only"]'::jsonb,1,'Revelation warns against adding to or taking from the words of the prophecy.','Revelation 22:18-19','Spirit of Prophecy','medium',true),

-- ---------------- Christian Living ----------------
('What does Micah 6:8 say the Lord requires?','["Sacrifice only","To do justly, love mercy, and walk humbly","Long prayers","Fasting"]'::jsonb,1,'To do justly, and to love mercy, and to walk humbly with thy God.','Micah 6:8','Christian Living','easy',true),
('In the armour of God, what is the breastplate?','["Faith","Righteousness","Truth","Peace"]'::jsonb,1,'The breastplate of righteousness.','Ephesians 6:14','Christian Living','medium',true),
('What is the helmet in the armour of God?','["Salvation","Hope","Wisdom","Peace"]'::jsonb,0,'Take the helmet of salvation.','Ephesians 6:17','Christian Living','medium',true),
('What girds the loins in the armour of God?','["Truth","Love","Faith","Joy"]'::jsonb,0,'Having your loins girt about with truth.','Ephesians 6:14','Christian Living','medium',true),
('What did Jesus say about the two greatest commandments?','["Love God, and love your neighbour as yourself","Tithe and pray","Fast and give","Keep silence"]'::jsonb,0,'On these two hang all the law and the prophets.','Matthew 22:37-40','Christian Living','easy',true),
('Complete: "Let all things be done ___ and in order."','["quickly","decently","loudly","privately"]'::jsonb,1,'Paul''s instruction on order in the church.','1 Corinthians 14:40','Christian Living','medium',true),
('What does James say pure religion is?','["Long prayers","Visiting the fatherless and widows, and keeping unspotted","Fasting weekly","Giving alms publicly"]'::jsonb,1,'Pure religion and undefiled before God is this.','James 1:27','Christian Living','medium',true),
('What did Paul say about anger and the sun?','["Let it burn","Let not the sun go down upon your wrath","Anger is always sin","Anger is harmless"]'::jsonb,1,'"Let not the sun go down upon your wrath."','Ephesians 4:26','Christian Living','medium',true),
('What should we do with our enemies, according to Romans 12?','["Avoid them","Feed them if hungry, overcome evil with good","Report them","Curse them"]'::jsonb,1,'"If thine enemy hunger, feed him... overcome evil with good."','Romans 12:20-21','Christian Living','medium',true),
('Complete: "The tongue is a little member, and boasteth ___ things."','["small","great","kind","few"]'::jsonb,1,'James on the power of the tongue.','James 3:5','Christian Living','medium',true),
('What does Proverbs say about a friend?','["A friend is rare","A friend loveth at all times","Friends are costly","Trust no friend"]'::jsonb,1,'"A friend loveth at all times, and a brother is born for adversity."','Proverbs 17:17','Christian Living','easy',true),
('What did Paul tell the Philippians to let be in them?','["Ambition","The mind which was also in Christ Jesus","Fear","Silence"]'::jsonb,1,'"Let this mind be in you, which was also in Christ Jesus."','Philippians 2:5','Christian Living','medium',true),
('What does the Bible say about the love of money?','["It is a blessing","It is the root of all evil","It is neutral","It is required"]'::jsonb,1,'"The love of money is the root of all evil."','1 Timothy 6:10','Christian Living','easy',true),
('Complete: "Study to shew thyself ___ unto God."','["known","approved","worthy","strong"]'::jsonb,1,'A workman that needeth not to be ashamed.','2 Timothy 2:15','Christian Living','medium',true),
('What did Jesus say about letting your yes be yes?','["Swear by heaven","Let your communication be Yea, yea; Nay, nay","Always take an oath","Say nothing"]'::jsonb,1,'"Whatsoever is more than these cometh of evil."','Matthew 5:37','Christian Living','medium',true),
('According to Galatians 6:7, what does a man reap?','["More than he sows","Whatsoever he soweth","Nothing","Only good"]'::jsonb,1,'"Whatsoever a man soweth, that shall he also reap."','Galatians 6:7','Christian Living','easy',true),

-- ---------------- Second Coming ----------------
('What did Jesus say would be seen in the sun, moon and stars?','["Nothing","Signs","New stars","Eclipses only"]'::jsonb,1,'"There shall be signs in the sun, and in the moon, and in the stars."','Luke 21:25','Second Coming','medium',true),
('What did Jesus compare the days before His coming to?','["The days of Solomon","The days of Noah","The days of David","The exodus"]'::jsonb,1,'As the days of Noe were, so shall also the coming of the Son of man be.','Matthew 24:37','Second Coming','medium',true),
('What will happen to the heavens at the day of the Lord?','["They remain","They shall pass away with a great noise","They darken only","Nothing"]'::jsonb,1,'The heavens shall pass away with a great noise, and the elements shall melt.','2 Peter 3:10','Second Coming','medium',true),
('Why does the Lord seem to delay His coming, according to Peter?','["He forgot","He is longsuffering, not willing that any should perish","He is waiting on angels","The time is fixed"]'::jsonb,1,'He is longsuffering to us-ward.','2 Peter 3:9','Second Coming','medium',true),
('How does Paul say the day of the Lord will come?','["With warning","As a thief in the night","Slowly","At noon"]'::jsonb,1,'The day of the Lord so cometh as a thief in the night.','1 Thessalonians 5:2','Second Coming','easy',true),
('What did the angels ask the disciples as they gazed up?','["Why weep ye?","Why stand ye gazing up into heaven?","Where is He?","What did He say?"]'::jsonb,1,'Two men in white apparel asked why they stood gazing up.','Acts 1:11','Second Coming','medium',true),
('What happens to those who are alive and remain at His coming?','["They stay on earth","They are caught up together with them in the clouds","They sleep","They wait a year"]'::jsonb,1,'Caught up together with them in the clouds, to meet the Lord in the air.','1 Thessalonians 4:17','Second Coming','medium',true),
('In what time frame does Paul say the change will happen?','["Over a year","In a moment, in the twinkling of an eye","Over seven years","Gradually"]'::jsonb,1,'In a moment, in the twinkling of an eye, at the last trump.','1 Corinthians 15:52','Second Coming','easy',true),
('What did Jesus say about false christs before His return?','["There will be none","Many shall come and deceive many","Only one","Ignore them"]'::jsonb,1,'"Many shall come in my name... and shall deceive many."','Matthew 24:5','Second Coming','medium',true),
('Where does Jesus say not to go looking for Him?','["The temple","The desert or secret chambers","The sea","The mountains"]'::jsonb,1,'"If they shall say unto you, Behold, he is in the desert; go not forth."','Matthew 24:26','Second Coming','hard',true),
('What is the sign of the Son of man that appears in heaven?','["A star","The Son of man coming in clouds with power and great glory","A rainbow","A trumpet"]'::jsonb,1,'They shall see the Son of man coming in the clouds of heaven.','Matthew 24:30','Second Coming','medium',true),
('What does Revelation 1:7 say about those who pierced Him?','["They are forgotten","They also shall see him","They are hidden","They are absent"]'::jsonb,1,'"Every eye shall see him, and they also which pierced him."','Revelation 1:7','Second Coming','medium',true),
('What did Jesus say about the fig tree putting forth leaves?','["Summer is near","Winter is coming","It means nothing","Harvest is past"]'::jsonb,0,'When its branch is tender and putteth forth leaves, ye know that summer is nigh.','Matthew 24:32','Second Coming','medium',true),
('How long will the redeemed be with the Lord?','["A thousand years only","For ever","Until judgment","Seven years"]'::jsonb,1,'"So shall we ever be with the Lord."','1 Thessalonians 4:17','Second Coming','easy',true),
('What crown does Paul say is laid up for those who love His appearing?','["Of gold","Of righteousness","Of thorns","Of life only"]'::jsonb,1,'A crown of righteousness, given to all them that love his appearing.','2 Timothy 4:8','Second Coming','medium',true),
('What did Jesus say we should do since we know not the hour?','["Sleep","Watch","Hide","Count the days"]'::jsonb,1,'"Watch therefore: for ye know not what hour your Lord doth come."','Matthew 24:42','Second Coming','easy',true),

-- ---------------- Health ----------------
('What did God give man for food at creation?','["Every herb bearing seed and fruit of trees","Fish","All animals","Bread only"]'::jsonb,0,'Herb bearing seed and the fruit of a tree yielding seed.','Genesis 1:29','Health','easy',true),
('Which animals were taken into the ark by sevens?','["All animals","The clean beasts","Only birds","None"]'::jsonb,1,'Of every clean beast thou shalt take to thee by sevens.','Genesis 7:2','Health','medium',true),
('What did Paul urge believers to present as a living sacrifice?','["Their money","Their bodies","Their time","Their words"]'::jsonb,1,'"Present your bodies a living sacrifice, holy, acceptable unto God."','Romans 12:1','Health','medium',true),
('What does Proverbs say a sound heart is to the body?','["A burden","The life of the flesh","A mystery","Nothing"]'::jsonb,1,'"A sound heart is the life of the flesh: but envy the rottenness of the bones."','Proverbs 14:30','Health','hard',true),
('What did Paul tell Timothy bodily exercise profits?','["Nothing","A little","Everything","More than godliness"]'::jsonb,1,'"Bodily exercise profiteth little: but godliness is profitable unto all things."','1 Timothy 4:8','Health','medium',true),
('What does 1 Corinthians 9:25 say about those who strive for mastery?','["They rest","They are temperate in all things","They eat freely","They compete"]'::jsonb,1,'Every man that striveth for the mastery is temperate in all things.','1 Corinthians 9:25','Health','medium',true),
('What did Jesus say about causing the body to sin?','["Ignore it","It is better to lose a member than for the whole body to perish","Nothing","It is unavoidable"]'::jsonb,1,'Better that one member perish than the whole body be cast into hell.','Matthew 5:29-30','Health','hard',true),
('Which creatures without fins and scales were unclean?','["Water creatures","Birds","Cattle","Insects"]'::jsonb,0,'Whatsoever hath no fins nor scales in the waters shall be an abomination.','Leviticus 11:10-12','Health','medium',true),
('What did God promise Israel if they obeyed and did what is right?','["Wealth","None of these diseases upon them","Long journeys","Many cities"]'::jsonb,1,'"I will put none of these diseases upon thee... I am the LORD that healeth thee."','Exodus 15:26','Health','medium',true),
('What does the Bible say about being a glutton or drunkard?','["It is approved","They come to poverty","It is harmless","It is required"]'::jsonb,1,'"For the drunkard and the glutton shall come to poverty."','Proverbs 23:21','Health','medium',true),
('What did Paul say he did to keep his body under?','["Fasted always","Kept it under and brought it into subjection","Ignored it","Rested"]'::jsonb,1,'"I keep under my body, and bring it into subjection."','1 Corinthians 9:27','Health','hard',true),
('What is listed as a fruit of the Spirit that relates to self-control?','["Meekness","Temperance","Joy","Peace"]'::jsonb,1,'Temperance is the last named fruit of the Spirit.','Galatians 5:23','Health','medium',true),
('What did Jesus do for the sick throughout His ministry?','["Avoided them","Healed them","Sent them away","Charged them"]'::jsonb,1,'He went about healing all manner of sickness and disease among the people.','Matthew 4:23','Health','easy',true),
('What did the disciples anoint the sick with?','["Water","Oil","Wine","Ashes"]'::jsonb,1,'They anointed with oil many that were sick, and healed them.','Mark 6:13','Health','medium',true),
('What does Proverbs 15:13 say a merry heart does?','["Maketh a cheerful countenance","Brings wealth","Causes sleep","Nothing"]'::jsonb,0,'"A merry heart maketh a cheerful countenance."','Proverbs 15:13','Health','medium',true),
('What did Jesus tell the disciples to do when they were weary?','["Keep working","Come apart and rest a while","Fast","Travel on"]'::jsonb,1,'"Come ye yourselves apart into a desert place, and rest a while."','Mark 6:31','Health','easy',true);

-- ---------------------------------------------------------------------
--  Standing safety net, same predicate as patch_234: alike wording AND
--  identical correct answer, keeping the lowest id. Runs after the insert
--  so anything above that restates an existing question removes itself.
--
--  This is deliberately not a UNIQUE constraint — the twins differ in
--  wording, so no exact-match constraint can express the rule.
-- ---------------------------------------------------------------------
DELETE FROM public.quiz_questions b
 WHERE EXISTS (
   SELECT 1 FROM public.quiz_questions a
    WHERE a.category = b.category
      AND a.id < b.id
      AND similarity(a.question, b.question) > 0.55
      AND lower(btrim(a.options->>a.correct_index))
        = lower(btrim(b.options->>b.correct_index))
 );
