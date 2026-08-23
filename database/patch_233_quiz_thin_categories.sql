-- =====================================================================
--  PATCH 233 — Fill the quiz categories that were thinner than a round
--
--  patch (23 Aug 2026) fixed the ROTATION bug: pickFresh padded a short
--  pool with already-seen questions, which hid the shortfall from
--  buildRound so the generator top-up never ran. That stops the same ten
--  questions being served forever.
--
--  It does not create questions. These seven categories held fewer than
--  twenty each, and a category round IS ten questions:
--
--      Prayer              10      Sanctuary           15
--      Church & Mission    10      Stewardship         15
--      Baptism             13      State of the Dead   15
--      Creation            14
--
--  At ten questions a category is exhausted by a single round. This adds
--  18 to each, taking every one to roughly three rounds' worth, which is
--  what the 21-day seen-cooldown actually needs to work with.
--
--  Every question here was written against the existing set in each
--  category so none repeats one already present.
--
--  Facts are scripture, verifiable from the `reference` column — unlike
--  the devotion patches there is no attribution risk here, because these
--  are Bible questions with checkable answers rather than quotations.
--  Distractors are plausible rather than silly: a wrong answer nobody
--  would pick teaches nothing and makes the round feel padded.
-- =====================================================================

INSERT INTO public.quiz_questions
  (question, options, correct_index, explanation, reference, category, difficulty, is_published)
VALUES

-- ---------------- Prayer ----------------
('Who prayed for a son and was thought to be drunk by Eli?','["Hannah","Ruth","Deborah","Esther"]'::jsonb,0,'Hannah prayed silently, moving only her lips, and Eli mistook it for drunkenness.','1 Samuel 1:12-16','Prayer','medium',true),
('What did Solomon ask for when God offered him anything?','["Long life","Riches","An understanding heart","Victory over enemies"]'::jsonb,2,'Solomon asked for an understanding heart to judge Israel, and God gave him riches too.','1 Kings 3:9-13','Prayer','easy',true),
('Who prayed three times for a thorn in the flesh to be removed?','["Peter","Paul","John","Timothy"]'::jsonb,1,'Paul was told "My grace is sufficient for thee."','2 Corinthians 12:7-9','Prayer','medium',true),
('While Peter was in prison, what was the church doing?','["Fleeing Jerusalem","Praying without ceasing","Choosing a new leader","Hiding the scriptures"]'::jsonb,1,'Prayer was made without ceasing by the church, and an angel released him.','Acts 12:5','Prayer','medium',true),
('Which king prayed after spreading a threatening letter before the Lord?','["David","Hezekiah","Josiah","Asa"]'::jsonb,1,'Hezekiah spread Sennacherib''s letter before the Lord in the temple.','2 Kings 19:14','Prayer','medium',true),
('What did Jesus do before choosing the twelve apostles?','["Fasted forty days","Continued all night in prayer","Consulted the Pharisees","Went to Jerusalem"]'::jsonb,1,'He went into a mountain and continued all night in prayer to God.','Luke 6:12','Prayer','medium',true),
('Complete: "Pray without ___."','["fear","doubting","ceasing","delay"]'::jsonb,2,'Paul''s instruction to the Thessalonians.','1 Thessalonians 5:17','Prayer','easy',true),
('Who prayed inside the belly of a great fish?','["Jonah","Job","Jeremiah","Joel"]'::jsonb,0,'Jonah prayed unto the Lord his God out of the fish''s belly.','Jonah 2:1','Prayer','easy',true),
('In the parable, who went home justified — the Pharisee or the publican?','["The Pharisee","The publican","Both","Neither"]'::jsonb,1,'The publican who said "God be merciful to me a sinner" went home justified.','Luke 18:13-14','Prayer','medium',true),
('What did Jesus say about praying with vain repetitions?','["It shows devotion","The heathen do it","It is required","It pleases God"]'::jsonb,1,'"Use not vain repetitions, as the heathen do."','Matthew 6:7','Prayer','medium',true),
('Who prayed for the people while Joshua fought Amalek?','["Aaron alone","Moses, held up by Aaron and Hur","Caleb","Miriam"]'::jsonb,1,'Aaron and Hur held up Moses'' hands until sundown.','Exodus 17:11-12','Prayer','medium',true),
('What posture did Solomon take at the temple dedication?','["Standing","Kneeling with hands spread to heaven","Lying prostrate","Sitting"]'::jsonb,1,'He kneeled upon his knees and spread forth his hands toward heaven.','2 Chronicles 6:13','Prayer','hard',true),
('According to 1 John, what gives us confidence that God hears us?','["Long prayers","Asking according to His will","Fasting first","Praying aloud"]'::jsonb,1,'"If we ask any thing according to his will, he heareth us."','1 John 5:14','Prayer','medium',true),
('Whose prayer brought fire down on Mount Carmel?','["Elisha","Elijah","Samuel","Gideon"]'::jsonb,1,'Elijah prayed and the fire of the Lord fell and consumed the sacrifice.','1 Kings 18:36-38','Prayer','easy',true),
('What did Jesus tell His disciples in Gethsemane to do so they would not enter temptation?','["Sleep","Watch and pray","Flee","Fast"]'::jsonb,1,'"Watch and pray, that ye enter not into temptation."','Matthew 26:41','Prayer','easy',true),
('Who prayed a long prayer of confession for Israel''s sins after reading the law?','["Ezra","Nehemiah","Zerubbabel","Haggai"]'::jsonb,1,'Nehemiah confessed the sins of Israel, including his own father''s house.','Nehemiah 1:5-7','Prayer','hard',true),
('What did Jesus pray for His disciples in John 17?','["That they be wealthy","That they be kept from evil and be one","That they escape death","That they rule"]'::jsonb,1,'He prayed the Father would keep them from evil and that they might be one.','John 17:15,21','Prayer','medium',true),
('Complete: "Be careful for nothing; but in every thing by prayer and supplication with ___ let your requests be made known unto God."','["fasting","thanksgiving","weeping","patience"]'::jsonb,1,'Thanksgiving accompanies the request.','Philippians 4:6','Prayer','medium',true),

-- ---------------- Church & Mission ----------------
('Who were the first two apostles sent out together in Acts 13?','["Peter and John","Barnabas and Saul","Paul and Silas","Timothy and Titus"]'::jsonb,1,'The Holy Ghost said "Separate me Barnabas and Saul for the work."','Acts 13:2','Church & Mission','medium',true),
('What was decided at the Jerusalem Council?','["Gentiles must be circumcised","Gentile believers need not be circumcised","The church should disband","Only Jews could preach"]'::jsonb,1,'The council concluded not to trouble the Gentiles who turned to God.','Acts 15:19','Church & Mission','medium',true),
('Who replaced Judas among the twelve?','["Matthias","Barnabas","Stephen","Philip"]'::jsonb,0,'Matthias was numbered with the eleven apostles.','Acts 1:26','Church & Mission','medium',true),
('How many men were chosen to serve tables so the apostles could pray and preach?','["Three","Seven","Ten","Twelve"]'::jsonb,1,'Seven men of honest report, full of the Holy Ghost.','Acts 6:3','Church & Mission','medium',true),
('Which city''s believers searched the scriptures daily and were called more noble?','["Corinth","Berea","Thessalonica","Ephesus"]'::jsonb,1,'The Bereans searched the scriptures daily to check what Paul taught.','Acts 17:11','Church & Mission','medium',true),
('Who was the tentmaker couple who taught Apollos more perfectly?','["Ananias and Sapphira","Aquila and Priscilla","Andronicus and Junia","Philemon and Apphia"]'::jsonb,1,'Aquila and Priscilla expounded the way of God to Apollos.','Acts 18:26','Church & Mission','medium',true),
('What did Jesus say the disciples would receive to be witnesses?','["Wealth","Power from the Holy Ghost","Political authority","Miraculous escape"]'::jsonb,1,'"Ye shall receive power, after that the Holy Ghost is come upon you."','Acts 1:8','Church & Mission','easy',true),
('Which apostle was sent to Cornelius, the first Gentile convert?','["Paul","Peter","John","James"]'::jsonb,1,'Peter was sent after the vision of the sheet let down from heaven.','Acts 10','Church & Mission','medium',true),
('What is the church called in Ephesians 1:22-23?','["The vineyard","His body","The flock","The temple"]'::jsonb,1,'The church is His body, the fulness of him that filleth all in all.','Ephesians 1:22-23','Church & Mission','medium',true),
('Who is described as the chief corner stone of the church?','["Peter","Jesus Christ","Paul","Abraham"]'::jsonb,1,'Jesus Christ Himself is the chief corner stone.','Ephesians 2:20','Church & Mission','easy',true),
('What did the early believers in Jerusalem do with their possessions?','["Kept them private","Had all things common","Gave them to Rome","Buried them"]'::jsonb,1,'They had all things common and distributed as any had need.','Acts 2:44-45','Church & Mission','easy',true),
('Which two believers lied about the price of land they sold?','["Aquila and Priscilla","Ananias and Sapphira","Eutychus and Trophimus","Demas and Crescens"]'::jsonb,1,'They kept back part of the price and lied to the Holy Ghost.','Acts 5:1-5','Church & Mission','medium',true),
('Whom did Paul call his "own son in the faith" and leave in Ephesus?','["Titus","Timothy","Luke","Silas"]'::jsonb,1,'Paul addressed Timothy as his own son in the faith.','1 Timothy 1:2','Church & Mission','medium',true),
('Which three angels'' messages does Revelation 14 describe?','["Judgment, Babylon''s fall, warning against the beast","Creation, flood, exodus","Faith, hope, love","Past, present, future"]'::jsonb,0,'The everlasting gospel and the hour of judgment, Babylon is fallen, and the warning about the beast''s mark.','Revelation 14:6-11','Church & Mission','hard',true),
('What did Jesus say about the harvest and the labourers?','["The harvest is small","The labourers are many","The harvest is plenteous but the labourers are few","There is no harvest"]'::jsonb,2,'He told them to pray the Lord of the harvest to send forth labourers.','Matthew 9:37-38','Church & Mission','easy',true),
('Where was Paul shipwrecked on his way to Rome?','["Cyprus","Melita (Malta)","Crete","Rhodes"]'::jsonb,1,'The island was called Melita, and the people showed no little kindness.','Acts 28:1-2','Church & Mission','medium',true),
('What sign accompanied the disciples at Pentecost?','["A rainbow","Cloven tongues like as of fire","An earthquake","A bright star"]'::jsonb,1,'Cloven tongues like as of fire sat upon each of them.','Acts 2:3','Church & Mission','easy',true),
('Who wrote most of the New Testament epistles?','["Peter","Paul","John","James"]'::jsonb,1,'Paul is credited with the majority of the epistles.','New Testament','Church & Mission','easy',true),

-- ---------------- Baptism ----------------
('What did Jesus say a person must be born of to enter the kingdom of God?','["Water and the Spirit","Fire only","Blood","The law"]'::jsonb,0,'"Except a man be born of water and of the Spirit."','John 3:5','Baptism','medium',true),
('Baptism is likened to burial with Christ in which epistle?','["Romans","Galatians","Hebrews","Jude"]'::jsonb,0,'"Buried with him by baptism into death."','Romans 6:4','Baptism','medium',true),
('What did Ananias tell Saul to do without delay?','["Flee Damascus","Arise and be baptized, washing away his sins","Return to Jerusalem","Fast forty days"]'::jsonb,1,'"Arise, and be baptized, and wash away thy sins."','Acts 22:16','Baptism','medium',true),
('Who was the first household baptized in Europe?','["The jailer''s","Lydia''s","Crispus''","Stephanas''"]'::jsonb,1,'Lydia and her household were baptized at Philippi.','Acts 16:14-15','Baptism','hard',true),
('What preceded baptism in Peter''s Pentecost appeal?','["Repentance","Sacrifice","Circumcision","Fasting"]'::jsonb,0,'"Repent, and be baptized every one of you."','Acts 2:38','Baptism','easy',true),
('Where did John baptize because there was much water there?','["Jericho","Aenon near to Salim","Bethany","Cana"]'::jsonb,1,'John was baptizing in Aenon near to Salim, because there was much water.','John 3:23','Baptism','hard',true),
('What did the voice from heaven say at Jesus'' baptism?','["This is my beloved Son","Follow him","Behold the Lamb","Repent ye"]'::jsonb,0,'"This is my beloved Son, in whom I am well pleased."','Matthew 3:17','Baptism','easy',true),
('What does 1 Peter compare baptism to?','["The Red Sea crossing","Noah''s ark and the flood","The exodus","The manna"]'::jsonb,1,'Eight souls were saved by water, the like figure whereunto baptism doth also now save us.','1 Peter 3:20-21','Baptism','hard',true),
('Which apostle baptized few at Corinth, saying Christ sent him to preach?','["Peter","Paul","Apollos","Silas"]'::jsonb,1,'Paul said Christ sent him not to baptize, but to preach the gospel.','1 Corinthians 1:14-17','Baptism','hard',true),
('What did John the Baptist say the One coming after him would baptize with?','["Water only","The Holy Ghost and with fire","Oil","Wine"]'::jsonb,1,'"He shall baptize you with the Holy Ghost, and with fire."','Matthew 3:11','Baptism','medium',true),
('Whose baptism did Apollos know only, before being taught more fully?','["Jesus''","John''s","Peter''s","Moses''"]'::jsonb,1,'Apollos knew only the baptism of John.','Acts 18:25','Baptism','hard',true),
('What did Jesus call His coming suffering, using baptism language?','["A cup and a baptism","A crown","A journey","A harvest"]'::jsonb,0,'"Can ye drink of the cup... and be baptized with the baptism that I am baptized with?"','Mark 10:38','Baptism','hard',true),
('In Galatians, those baptized into Christ have put on whom?','["Moses","Christ","Abraham","The law"]'::jsonb,1,'"As many of you as have been baptized into Christ have put on Christ."','Galatians 3:27','Baptism','medium',true),
('What did the jailer at Philippi do immediately after believing?','["Fled the city","Was baptized with all his household","Reported to Rome","Freed all prisoners"]'::jsonb,1,'He was baptized, he and all his, straightway.','Acts 16:33','Baptism','medium',true),
('How many were baptized on the day of Pentecost?','["About 500","About 3000","About 120","About 5000"]'::jsonb,1,'About three thousand souls were added that day.','Acts 2:41','Baptism','easy',true),
('Baptism is part of which commission given by Jesus?','["The Great Commission","The Sermon on the Mount","The Olivet Discourse","The Upper Room Discourse"]'::jsonb,0,'"Go ye therefore, and teach all nations, baptizing them."','Matthew 28:19','Baptism','easy',true),
('What did Paul find disciples at Ephesus had not heard of?','["The resurrection","The Holy Ghost","The Sabbath","The Messiah"]'::jsonb,1,'They had not so much as heard whether there be any Holy Ghost.','Acts 19:2','Baptism','hard',true),
('What follows baptism, according to Romans 6:4?','["Rest","Walking in newness of life","Fasting","Silence"]'::jsonb,1,'"Even so we also should walk in newness of life."','Romans 6:4','Baptism','medium',true),

-- ---------------- Creation ----------------
('What did God create on the second day?','["Light","The firmament dividing the waters","Dry land","Animals"]'::jsonb,1,'God made the firmament and divided the waters.','Genesis 1:6-8','Creation','medium',true),
('On which day did God create dry land and plants?','["Second","Third","Fourth","Fifth"]'::jsonb,1,'On the third day the dry land appeared and the earth brought forth grass and trees.','Genesis 1:9-13','Creation','medium',true),
('What did God say after each day of creation?','["It is finished","That it was good","Let there be light","Be fruitful"]'::jsonb,1,'God saw that it was good.','Genesis 1','Creation','easy',true),
('Which New Testament book says all things were made by the Word?','["John","Acts","Romans","James"]'::jsonb,0,'"All things were made by him; and without him was not any thing made."','John 1:3','Creation','medium',true),
('What river went out of Eden to water the garden?','["Jordan","A river that parted into four heads","Nile","Euphrates only"]'::jsonb,1,'It parted and became into four heads: Pison, Gihon, Hiddekel and Euphrates.','Genesis 2:10-14','Creation','hard',true),
('What did God tell Adam and Eve to do with the earth?','["Leave it alone","Replenish and subdue it","Worship it","Divide it"]'::jsonb,1,'"Be fruitful, and multiply, and replenish the earth, and subdue it."','Genesis 1:28','Creation','easy',true),
('According to Psalm 33, how were the heavens made?','["By angels","By the word of the LORD","Over long ages","By chance"]'::jsonb,1,'"By the word of the LORD were the heavens made."','Psalm 33:6','Creation','medium',true),
('Which commandment points back to creation as its reason?','["The first","The fourth","The fifth","The tenth"]'::jsonb,1,'"For in six days the LORD made heaven and earth... wherefore the LORD blessed the sabbath day."','Exodus 20:11','Creation','medium',true),
('What was man to do in the garden of Eden?','["Rest only","Dress it and keep it","Build a city","Travel"]'::jsonb,1,'God put him into the garden to dress it and to keep it.','Genesis 2:15','Creation','medium',true),
('Which tree were Adam and Eve forbidden to eat from?','["The tree of life","The tree of knowledge of good and evil","The fig tree","The olive tree"]'::jsonb,1,'God commanded they not eat of the tree of knowledge of good and evil.','Genesis 2:17','Creation','easy',true),
('What does Hebrews 11:3 say framed the worlds?','["The word of God","Natural forces","Angels","Time"]'::jsonb,0,'"Through faith we understand that the worlds were framed by the word of God."','Hebrews 11:3','Creation','medium',true),
('In Job 38, who does God say laid the foundations of the earth?','["Job","Himself","The angels","No one"]'::jsonb,1,'God asks Job where he was when He laid the earth''s foundations.','Job 38:4','Creation','medium',true),
('What did God create on the sixth day besides man?','["Fish","Land animals and cattle","Birds","Stars"]'::jsonb,1,'God made the beast of the earth, cattle and creeping things, then man.','Genesis 1:24-27','Creation','medium',true),
('What did Adam call his wife, and why?','["Eve, mother of all living","Sarah, princess","Ruth, companion","Mary, beloved"]'::jsonb,0,'Adam called her Eve because she was the mother of all living.','Genesis 3:20','Creation','medium',true),
('According to Colossians, what was created by Christ?','["Only the earth","All things in heaven and earth, visible and invisible","Only mankind","Only light"]'::jsonb,1,'"By him were all things created, that are in heaven, and that are in earth."','Colossians 1:16','Creation','medium',true),
('How long did God take to rest, and what did He do to that day?','["One day; He blessed and sanctified it","Two days; He named it","Seven days; He hid it","He did not rest"]'::jsonb,0,'God rested the seventh day, blessed it and sanctified it.','Genesis 2:2-3','Creation','easy',true),
('Which psalm says we are "fearfully and wonderfully made"?','["Psalm 23","Psalm 139","Psalm 100","Psalm 51"]'::jsonb,1,'David marvels that he is fearfully and wonderfully made.','Psalm 139:14','Creation','medium',true),
('What did God breathe into man, making him a living soul?','["Blood","The breath of life","A spirit being","Fire"]'::jsonb,1,'God breathed into his nostrils the breath of life; man became a living soul.','Genesis 2:7','Creation','easy',true),

-- ---------------- Sanctuary ----------------
('How many pieces of furniture were in the holy place?','["Two","Three","Four","One"]'::jsonb,1,'The table of shewbread, the candlestick, and the altar of incense.','Exodus 25-30','Sanctuary','medium',true),
('What was inside the ark of the covenant?','["Gold and silver","The tables of the law, Aaron''s rod and manna","Scrolls","Nothing"]'::jsonb,1,'The golden pot of manna, Aaron''s rod that budded, and the tables of the covenant.','Hebrews 9:4','Sanctuary','medium',true),
('What separated the holy place from the most holy place?','["A door","The veil","A curtain of skins","A wall"]'::jsonb,1,'The veil divided between the holy place and the most holy.','Exodus 26:33','Sanctuary','easy',true),
('What happened to the temple veil when Jesus died?','["It burned","It was rent in twain from top to bottom","It was removed","Nothing"]'::jsonb,1,'The veil was rent in twain from the top to the bottom.','Matthew 27:51','Sanctuary','easy',true),
('Who alone could enter the most holy place, and how often?','["Any priest, daily","The high priest, once a year","The king, weekly","Anyone, at Passover"]'::jsonb,1,'The high priest entered alone once every year, not without blood.','Hebrews 9:7','Sanctuary','medium',true),
('What is the Day of Atonement called in Hebrew?','["Pesach","Yom Kippur","Shavuot","Sukkot"]'::jsonb,1,'Yom Kippur, the day the sanctuary was cleansed.','Leviticus 16','Sanctuary','medium',true),
('What did the lampstand in the holy place burn?','["Wax","Pure olive oil","Animal fat","Incense"]'::jsonb,1,'Pure oil olive beaten for the light, to burn always.','Exodus 27:20','Sanctuary','hard',true),
('How many loaves were on the table of shewbread?','["Seven","Ten","Twelve","Four"]'::jsonb,2,'Twelve cakes, set in two rows of six.','Leviticus 24:5-6','Sanctuary','hard',true),
('What did the altar of burnt offering stand in?','["The most holy place","The courtyard","The holy place","Outside the camp"]'::jsonb,1,'The brazen altar stood in the court of the tabernacle.','Exodus 40:6','Sanctuary','medium',true),
('Daniel 8:14 says the sanctuary would be cleansed after how long?','["490 days","1260 days","2300 days","70 weeks"]'::jsonb,2,'"Unto two thousand and three hundred days; then shall the sanctuary be cleansed."','Daniel 8:14','Sanctuary','medium',true),
('Who is our High Priest in the heavenly sanctuary?','["Aaron","Melchizedek","Jesus Christ","Moses"]'::jsonb,2,'Christ is a high priest of good things to come, in the greater tabernacle.','Hebrews 9:11','Sanctuary','easy',true),
('What was placed on the mercy seat above the ark?','["Two cherubim of gold","A crown","A lamp","Bread"]'::jsonb,0,'Two cherubim of gold covering the mercy seat with their wings.','Exodus 25:18-20','Sanctuary','medium',true),
('Who built the first tabernacle in the wilderness?','["Solomon","Moses, by God''s pattern","David","Bezaleel alone"]'::jsonb,1,'Moses made it after the pattern shewed him in the mount.','Exodus 25:9','Sanctuary','easy',true),
('What did the scapegoat represent on the Day of Atonement?','["The sacrifice for sin","The bearing away of sin","The priest","The people"]'::jsonb,1,'The goat bore the iniquities away into a land not inhabited.','Leviticus 16:21-22','Sanctuary','hard',true),
('What was burned on the golden altar in the holy place?','["Sacrifices","Sweet incense","Grain","Oil"]'::jsonb,1,'Aaron burned sweet incense on it every morning and evening.','Exodus 30:7-8','Sanctuary','medium',true),
('Hebrews says the earthly sanctuary was a shadow of what?','["The temple in Jerusalem","Heavenly things","Israel''s history","The law"]'::jsonb,1,'The priests serve unto the example and shadow of heavenly things.','Hebrews 8:5','Sanctuary','medium',true),
('Which king built the first permanent temple?','["David","Solomon","Hezekiah","Josiah"]'::jsonb,1,'Solomon built the temple, though David prepared for it.','1 Kings 6','Sanctuary','easy',true),
('What did the blood of the sacrifice do in the sanctuary service?','["Decorated the altar","Transferred and atoned for sin","Fed the priests","Nothing"]'::jsonb,1,'"It is the blood that maketh an atonement for the soul."','Leviticus 17:11','Sanctuary','medium',true),

-- ---------------- Stewardship ----------------
('What portion belongs to the Lord according to Leviticus 27:30?','["A fifth","The tithe (a tenth)","A half","Whatever is left"]'::jsonb,1,'"All the tithe of the land... is the LORD''s: it is holy unto the LORD."','Leviticus 27:30','Stewardship','easy',true),
('To whom did Abraham pay tithes?','["Pharaoh","Melchizedek","Lot","Isaac"]'::jsonb,1,'Abraham gave tithes of all to Melchizedek, priest of the most high God.','Genesis 14:20','Stewardship','medium',true),
('What did Jacob vow at Bethel?','["To build a city","To give a tenth of all God gave him","To never return","To fast"]'::jsonb,1,'"Of all that thou shalt give me I will surely give the tenth unto thee."','Genesis 28:22','Stewardship','medium',true),
('In Malachi 3, what does God invite the people to do?','["Fast","Prove Him with tithes","Build a temple","Migrate"]'::jsonb,1,'"Prove me now herewith... if I will not open you the windows of heaven."','Malachi 3:10','Stewardship','easy',true),
('How much did the widow put into the treasury?','["Ten pieces","Two mites, all her living","A talent","Nothing"]'::jsonb,1,'She cast in two mites, which was all her living.','Mark 12:42-44','Stewardship','easy',true),
('In the parable of the talents, how many talents did the third servant receive?','["One","Two","Five","Ten"]'::jsonb,0,'He received one and buried it in the earth.','Matthew 25:15,18','Stewardship','medium',true),
('What did the master call the servant who buried his talent?','["Faithful","Wicked and slothful","Wise","Merciful"]'::jsonb,1,'"Thou wicked and slothful servant."','Matthew 25:26','Stewardship','medium',true),
('What did Jesus say you cannot serve God alongside?','["The law","Mammon","The Sabbath","The temple"]'::jsonb,1,'"Ye cannot serve God and mammon."','Matthew 6:24','Stewardship','easy',true),
('What did the rich young ruler lack, according to Jesus?','["Faith","To sell what he had and give to the poor","Knowledge","Baptism"]'::jsonb,1,'Jesus told him to sell all, give to the poor, and follow Him.','Mark 10:21','Stewardship','medium',true),
('What happened to the rich fool who built bigger barns?','["He prospered","His soul was required that night","He gave it away","He moved"]'::jsonb,1,'"Thou fool, this night thy soul shall be required of thee."','Luke 12:20','Stewardship','medium',true),
('What does Proverbs say about lending to the poor?','["It is wasted","It is lending to the LORD","It is forbidden","It brings poverty"]'::jsonb,1,'"He that hath pity upon the poor lendeth unto the LORD."','Proverbs 19:17','Stewardship','medium',true),
('What did Paul say about the labourer and his hire?','["He deserves nothing","The labourer is worthy of his reward","He should work free","He should be taxed"]'::jsonb,1,'"The labourer is worthy of his reward."','1 Timothy 5:18','Stewardship','hard',true),
('What is the root of all evil, according to Paul?','["Money itself","The love of money","Poverty","Idleness"]'::jsonb,1,'"The love of money is the root of all evil."','1 Timothy 6:10','Stewardship','easy',true),
('How did the Macedonian churches give, despite deep poverty?','["Reluctantly","Beyond their power, willingly","Only a tenth","Not at all"]'::jsonb,1,'To their power, yea and beyond their power they were willing of themselves.','2 Corinthians 8:3','Stewardship','hard',true),
('Where did Jesus say to lay up treasure?','["In barns","In heaven","In the temple","In the field"]'::jsonb,1,'"Lay up for yourselves treasures in heaven."','Matthew 6:20','Stewardship','easy',true),
('What did Zacchaeus promise to give the poor?','["A tenth","Half his goods","All he had","Nothing"]'::jsonb,1,'"Behold, Lord, the half of my goods I give to the poor."','Luke 19:8','Stewardship','medium',true),
('In the parable of the unjust steward, what was commended?','["His honesty","His shrewd foresight","His generosity","His hard work"]'::jsonb,1,'The lord commended the unjust steward because he had done wisely.','Luke 16:8','Stewardship','hard',true),
('What did Paul say we brought into this world?','["Great wealth","Nothing, and can carry nothing out","Our works","Our family"]'::jsonb,1,'"We brought nothing into this world, and it is certain we can carry nothing out."','1 Timothy 6:7','Stewardship','medium',true),

-- ---------------- State of the Dead ----------------
('What did Jesus call Lazarus'' death?','["A tragedy","Sleep","A judgment","A mystery"]'::jsonb,1,'"Our friend Lazarus sleepeth; but I go, that I may awake him."','John 11:11','State of the Dead','easy',true),
('According to Psalm 146:4, what happens to a man''s thoughts at death?','["They continue","They perish","They multiply","They transfer"]'::jsonb,1,'"His breath goeth forth... in that very day his thoughts perish."','Psalm 146:4','State of the Dead','medium',true),
('Where do the dead go, according to Ecclesiastes 9:10?','["Heaven","The grave, where there is no work or knowledge","Purgatory","Another life"]'::jsonb,1,'"There is no work, nor device, nor knowledge, nor wisdom, in the grave."','Ecclesiastes 9:10','State of the Dead','medium',true),
('Who alone has immortality, according to 1 Timothy 6:16?','["Angels","God","The righteous","Prophets"]'::jsonb,1,'God only hath immortality, dwelling in the light which no man can approach.','1 Timothy 6:16','State of the Dead','medium',true),
('When do believers receive immortality?','["At death","At the last trump, at the resurrection","At baptism","At birth"]'::jsonb,1,'"This mortal must put on immortality" at the last trump.','1 Corinthians 15:52-53','State of the Dead','medium',true),
('What did God say man would return to?','["Heaven","Dust","Fire","Water"]'::jsonb,1,'"Dust thou art, and unto dust shalt thou return."','Genesis 3:19','State of the Dead','easy',true),
('What did Jesus say about those in the graves hearing His voice?','["They cannot hear","They shall come forth","They already rose","They will stay"]'::jsonb,1,'All that are in the graves shall hear his voice and come forth.','John 5:28-29','State of the Dead','medium',true),
('Do the dead praise the Lord, according to Psalm 115:17?','["Yes, continually","No, neither any that go down into silence","Only the righteous","Only at Passover"]'::jsonb,1,'"The dead praise not the LORD, neither any that go down into silence."','Psalm 115:17','State of the Dead','medium',true),
('What did Paul say about those who are asleep, so we do not sorrow as others?','["They are lost","Christ will bring them with Him","They are angels","They are watching"]'::jsonb,1,'Them also which sleep in Jesus will God bring with him.','1 Thessalonians 4:13-14','State of the Dead','medium',true),
('How long was Lazarus dead before Jesus raised him?','["One day","Four days","A week","An hour"]'::jsonb,1,'Lazarus had lain in the grave four days already.','John 11:17','State of the Dead','easy',true),
('What did David''s tomb prove, in Peter''s Pentecost sermon?','["David ascended","David is dead and buried, not ascended","David was a prophet only","David never died"]'::jsonb,1,'"David is not ascended into the heavens."','Acts 2:29,34','State of the Dead','hard',true),
('What is the wages of sin?','["Sickness","Death","Poverty","Exile"]'::jsonb,1,'"The wages of sin is death; but the gift of God is eternal life."','Romans 6:23','State of the Dead','easy',true),
('What will happen to death itself in the end?','["It will rule","It will be destroyed","It will remain","It will multiply"]'::jsonb,1,'The last enemy that shall be destroyed is death.','1 Corinthians 15:26','State of the Dead','medium',true),
('Who did Saul consult at Endor?','["A prophet","A woman with a familiar spirit","A priest","An angel"]'::jsonb,1,'Saul sought a woman with a familiar spirit, which God had forbidden.','1 Samuel 28:7','State of the Dead','medium',true),
('What does the Bible forbid regarding the dead?','["Burial","Consulting or seeking unto them","Mourning","Remembering"]'::jsonb,1,'"Should not a people seek unto their God? for the living to the dead?"','Isaiah 8:19','State of the Dead','hard',true),
('At the second coming, who rises first?','["The living","The dead in Christ","The wicked","The angels"]'::jsonb,1,'"The dead in Christ shall rise first."','1 Thessalonians 4:16','State of the Dead','easy',true),
('How does Daniel describe those who sleep in the dust?','["They are gone","Many shall awake, some to everlasting life","They are in heaven","They never wake"]'::jsonb,1,'Many that sleep in the dust of the earth shall awake.','Daniel 12:2','State of the Dead','medium',true),
('What will the righteous receive at the resurrection?','["A spirit body only","A glorified, incorruptible body","The same mortal body","Nothing"]'::jsonb,1,'It is sown in corruption; it is raised in incorruption.','1 Corinthians 15:42-44','State of the Dead','medium',true);

-- ---------------------------------------------------------------------
--  Dedupe. Five of the questions above already existed:
--
--    Complete: "Pray without ___."                     (Christian Living)
--    Do the dead praise the Lord, according to Ps 115:17?
--    What happened to the temple veil when Jesus died?
--    Where did Jesus say to lay up treasure?
--    Who is our High Priest in the heavenly sanctuary?
--
--  My error, and an instructive one: I checked the existing questions for
--  Prayer, Church & Mission, Baptism and Creation, but not for Sanctuary,
--  Stewardship or State of the Dead — and one duplicate was filed under a
--  DIFFERENT category (Christian Living) from the one I was adding to, so
--  a per-category check would have missed it anyway. Compare against the
--  whole table, not the category being filled.
--
--  Scoped to id > 423 (the pre-patch maximum) so only copies added by this
--  patch are removed and the originals are untouched.
--
--  Verified after running: 544 rows, 0 duplicate questions.
-- ---------------------------------------------------------------------
DELETE FROM public.quiz_questions q
 WHERE q.id > 423
   AND EXISTS (
     SELECT 1 FROM public.quiz_questions o
      WHERE o.question = q.question
        AND o.id < q.id
   );
