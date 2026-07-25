-- patch_160: Bible Quiz content batch 3 — Bible Basics, Bible Characters,
-- Gospels, Parables, and a new Prayer category.
--
-- Context: the bank shipped with 158 questions across 19 categories, and
-- several categories had so few that picking them as a topic replayed the
-- same question every time (Baptism and Sanctuary had exactly one each).
-- Batches 3–5 bring every category above the 5-question floor the lobby
-- now requires, and roughly triple the bank overall.

insert into public.quiz_questions (question, options, correct_index, explanation, reference, category, difficulty) values

-- ---- Bible Basics ---------------------------------------------------------
('Which book of the Bible has the most chapters?', '["Isaiah", "Psalms", "Genesis", "Jeremiah"]'::jsonb, 1, 'Psalms has 150 chapters — more than any other book.', 'Psalms', 'Bible Basics', 'easy'),
('Which is the longest chapter in the Bible?', '["Psalm 119", "Psalm 23", "Isaiah 53", "Matthew 5"]'::jsonb, 0, 'Psalm 119 has 176 verses, each section built on a letter of the Hebrew alphabet.', 'Psalm 119', 'Bible Basics', 'medium'),
('Which is the shortest chapter in the Bible?', '["Psalm 100", "Psalm 117", "Psalm 1", "Jude 1"]'::jsonb, 1, 'Psalm 117 has just two verses.', 'Psalm 117', 'Bible Basics', 'medium'),
('Which prophet wrote the book of Lamentations?', '["Isaiah", "Ezekiel", "Jeremiah", "Daniel"]'::jsonb, 2, 'Jeremiah, the weeping prophet, lamented the fall of Jerusalem.', 'Lamentations 1', 'Bible Basics', 'medium'),
('Who wrote the book of Acts?', '["Peter", "Paul", "Luke", "John"]'::jsonb, 2, 'Luke wrote both the Gospel of Luke and Acts, addressed to Theophilus.', 'Acts 1:1', 'Bible Basics', 'medium'),
('How many books did Moses write?', '["Three", "Five", "Seven", "Ten"]'::jsonb, 1, 'Genesis, Exodus, Leviticus, Numbers and Deuteronomy — the Pentateuch.', '-', 'Bible Basics', 'easy'),
('Which book comes immediately after Genesis?', '["Leviticus", "Exodus", "Numbers", "Joshua"]'::jsonb, 1, 'Exodus follows Genesis and records the deliverance from Egypt.', '-', 'Bible Basics', 'easy'),
('Which book comes immediately before Revelation?', '["3 John", "James", "Jude", "Hebrews"]'::jsonb, 2, 'Jude is the last book before Revelation closes the canon.', '-', 'Bible Basics', 'medium'),
('How many books are counted as the Major Prophets?', '["Three", "Four", "Five", "Twelve"]'::jsonb, 2, 'Isaiah, Jeremiah, Lamentations, Ezekiel and Daniel.', '-', 'Bible Basics', 'medium'),
('How many Minor Prophets are there?', '["Seven", "Ten", "Twelve", "Fifteen"]'::jsonb, 2, 'Twelve, from Hosea through Malachi — "minor" refers to length, not importance.', '-', 'Bible Basics', 'medium'),
('Most of the Old Testament was originally written in which language?', '["Greek", "Latin", "Hebrew", "Aramaic"]'::jsonb, 2, 'The Old Testament was written mainly in Hebrew, with a little Aramaic.', '-', 'Bible Basics', 'medium'),
('The New Testament was originally written in which language?', '["Hebrew", "Greek", "Latin", "Aramaic"]'::jsonb, 1, 'The New Testament was written in common (Koine) Greek.', '-', 'Bible Basics', 'medium'),
('Which book of the Bible never mentions God by name?', '["Ruth", "Esther", "Obadiah", "Philemon"]'::jsonb, 1, 'Esther never names God, yet His providence runs through every chapter.', 'Esther', 'Bible Basics', 'hard'),
('How does the Bible end?', '["With a genealogy", "With the grace of our Lord Jesus Christ", "With the Ten Commandments", "With a psalm"]'::jsonb, 1, '"The grace of our Lord Jesus Christ be with you all. Amen."', 'Revelation 22:21', 'Bible Basics', 'medium'),
('Which of these books is one of the four Gospels?', '["Acts", "Romans", "Mark", "Hebrews"]'::jsonb, 2, 'Matthew, Mark, Luke and John are the four Gospels.', '-', 'Bible Basics', 'easy'),

-- ---- Bible Characters -----------------------------------------------------
('Who lived longer than anyone else recorded in the Bible?', '["Adam", "Noah", "Methuselah", "Enoch"]'::jsonb, 2, 'Methuselah lived 969 years.', 'Genesis 5:27', 'Bible Characters', 'medium'),
('Who walked with God and "was not, for God took him"?', '["Elijah", "Enoch", "Moses", "Noah"]'::jsonb, 1, 'Enoch was translated without seeing death.', 'Genesis 5:24', 'Bible Characters', 'medium'),
('Who is called the friend of God?', '["Moses", "David", "Abraham", "Job"]'::jsonb, 2, 'Abraham believed God and was called the friend of God.', 'James 2:23', 'Bible Characters', 'medium'),
('Who wrestled with the angel until the breaking of the day?', '["Esau", "Jacob", "Isaac", "Joseph"]'::jsonb, 1, 'Jacob wrestled until he was blessed, and was renamed Israel.', 'Genesis 32:24-28', 'Bible Characters', 'medium'),
('Who was the first murderer recorded in the Bible?', '["Cain", "Lamech", "Esau", "Nimrod"]'::jsonb, 0, 'Cain killed his brother Abel out of envy.', 'Genesis 4:8', 'Bible Characters', 'easy'),
('Who was the mother of Samuel?', '["Ruth", "Hannah", "Naomi", "Rachel"]'::jsonb, 1, 'Hannah prayed for a son and lent him to the LORD all his days.', '1 Samuel 1:20', 'Bible Characters', 'medium'),
('Which prophet anointed David as king?', '["Nathan", "Samuel", "Elijah", "Gad"]'::jsonb, 1, 'Samuel anointed David in the midst of his brothers.', '1 Samuel 16:13', 'Bible Characters', 'medium'),
('Who was David''s closest friend?', '["Joab", "Jonathan", "Absalom", "Uriah"]'::jsonb, 1, 'Jonathan, Saul''s son, loved David as his own soul.', '1 Samuel 18:1', 'Bible Characters', 'medium'),
('Which king asked God for wisdom rather than riches?', '["David", "Solomon", "Hezekiah", "Josiah"]'::jsonb, 1, 'Solomon asked for an understanding heart to judge God''s people.', '1 Kings 3:9', 'Bible Characters', 'easy'),
('Who were the three Hebrews thrown into the fiery furnace?', '["Shadrach, Meshach and Abednego", "Daniel, Ezra and Nehemiah", "Peter, James and John", "Hananiah, Ezra and Joel"]'::jsonb, 0, 'They refused to bow to the golden image and God delivered them.', 'Daniel 3', 'Bible Characters', 'easy'),
('Who was the first king of Israel?', '["David", "Saul", "Solomon", "Samuel"]'::jsonb, 1, 'Saul was anointed Israel''s first king.', '1 Samuel 10:1', 'Bible Characters', 'easy'),
('Who was the brother of Moses and Israel''s first high priest?', '["Caleb", "Aaron", "Joshua", "Hur"]'::jsonb, 1, 'Aaron and his sons were consecrated to the priesthood.', 'Exodus 28:1', 'Bible Characters', 'easy'),
('Who succeeded Moses as leader of Israel?', '["Caleb", "Aaron", "Joshua", "Eleazar"]'::jsonb, 2, 'Joshua led Israel into the promised land.', 'Joshua 1:1-2', 'Bible Characters', 'easy'),
('Which queen risked her life to save her people?', '["Vashti", "Esther", "Bathsheba", "Jezebel"]'::jsonb, 1, '"If I perish, I perish" — Esther went in unto the king unbidden.', 'Esther 4:16', 'Bible Characters', 'easy'),
('Who was the father of the Israelite nation, called out of Ur?', '["Isaac", "Abraham", "Jacob", "Terah"]'::jsonb, 1, 'God called Abram out of Ur of the Chaldees and made him a great nation.', 'Genesis 12:1-2', 'Bible Characters', 'easy'),

-- ---- Gospels --------------------------------------------------------------
('How many disciples did Jesus choose as apostles?', '["Seven", "Ten", "Twelve", "Seventy"]'::jsonb, 2, 'Jesus ordained twelve that they should be with Him.', 'Mark 3:14', 'Gospels', 'easy'),
('Which disciple betrayed Jesus?', '["Thomas", "Judas Iscariot", "Peter", "Simon the Zealot"]'::jsonb, 1, 'Judas betrayed Him for thirty pieces of silver.', 'Matthew 26:14-16', 'Gospels', 'easy'),
('How many men did Jesus feed with five loaves and two fishes?', '["About one thousand", "About three thousand", "About five thousand", "About ten thousand"]'::jsonb, 2, 'About five thousand men, besides women and children.', 'Matthew 14:21', 'Gospels', 'easy'),
('Which disciple walked on the water toward Jesus?', '["John", "James", "Peter", "Andrew"]'::jsonb, 2, 'Peter walked on the water until he saw the wind and was afraid.', 'Matthew 14:29-30', 'Gospels', 'medium'),
('Whom did Jesus raise after he had been dead four days?', '["Jairus'' daughter", "Lazarus", "The widow''s son", "Malchus"]'::jsonb, 1, 'Jesus called Lazarus out of the tomb at Bethany.', 'John 11:43-44', 'Gospels', 'easy'),
('Who was compelled to carry Jesus'' cross?', '["Joseph of Arimathaea", "Simon of Cyrene", "Nicodemus", "Barabbas"]'::jsonb, 1, 'Simon, a man of Cyrene, was compelled to bear His cross.', 'Matthew 27:32', 'Gospels', 'medium'),
('Who asked Pilate for the body of Jesus?', '["Nicodemus", "Joseph of Arimathaea", "Peter", "John"]'::jsonb, 1, 'Joseph of Arimathaea laid Him in his own new tomb.', 'Matthew 27:57-60', 'Gospels', 'medium'),
('To whom did Jesus first appear after His resurrection?', '["Peter", "Mary Magdalene", "John", "The two on the Emmaus road"]'::jsonb, 1, 'He appeared first to Mary Magdalene.', 'Mark 16:9', 'Gospels', 'medium'),
('What did Thomas say when he saw the risen Jesus?', '["Rabboni", "My Lord and my God", "Truly this was the Son of God", "It is the Lord"]'::jsonb, 1, 'Thomas answered, "My Lord and my God."', 'John 20:28', 'Gospels', 'medium'),
('Which two men appeared with Jesus at the transfiguration?', '["Abraham and David", "Moses and Elias", "Enoch and Elias", "Samuel and Moses"]'::jsonb, 1, 'Moses and Elias (Elijah) talked with Him.', 'Matthew 17:3', 'Gospels', 'medium'),

-- ---- Parables -------------------------------------------------------------
('In the parable of the sower, what does the seed represent?', '["Money", "The word of God", "Good works", "The church"]'::jsonb, 1, '"The seed is the word of God."', 'Luke 8:11', 'Parables', 'easy'),
('In the parable of the prodigal son, what did the father do when he saw him coming?', '["Sent a servant out", "Ran and fell on his neck and kissed him", "Waited at the gate", "Called the elder son"]'::jsonb, 1, 'While he was yet a great way off, his father ran to him.', 'Luke 15:20', 'Parables', 'easy'),
('In the parable of the good Samaritan, who passed by the wounded man first?', '["A Levite", "A priest", "A lawyer", "A merchant"]'::jsonb, 1, 'A priest passed by on the other side, then a Levite.', 'Luke 10:31', 'Parables', 'medium'),
('How many of the ten virgins were wise?', '["Three", "Five", "Seven", "Ten"]'::jsonb, 1, 'Five were wise and five were foolish.', 'Matthew 25:2', 'Parables', 'easy'),
('What did the wise virgins have that the foolish did not?', '["Better lamps", "Oil in their vessels", "Wedding garments", "Invitations"]'::jsonb, 1, 'The wise took oil in their vessels with their lamps.', 'Matthew 25:4', 'Parables', 'medium'),
('In the parable of the lost sheep, how many did the shepherd leave to seek the one?', '["Fifty", "Ninety and nine", "One hundred", "Twelve"]'::jsonb, 1, 'He left the ninety and nine to go after that which was lost.', 'Luke 15:4', 'Parables', 'easy'),
('In the parable of the wheat and the tares, when are they separated?', '["Immediately", "At the harvest, the end of the world", "When the servants ask", "At the spring planting"]'::jsonb, 1, '"The harvest is the end of the world."', 'Matthew 13:30, 39', 'Parables', 'medium'),
('What did Jesus compare to a grain of mustard seed?', '["Faith and the kingdom of heaven", "Riches", "The law", "Persecution"]'::jsonb, 0, 'The smallest of seeds becomes the greatest of herbs.', 'Matthew 13:31-32; 17:20', 'Parables', 'medium'),
('In the parable of the unmerciful servant, what did the forgiven servant refuse to do?', '["Work", "Forgive a much smaller debt", "Pay his taxes", "Return home"]'::jsonb, 1, 'He took his fellowservant by the throat over a hundred pence.', 'Matthew 18:28-30', 'Parables', 'medium'),
('What did God say to the rich fool who built bigger barns?', '["Well done", "Thou fool, this night thy soul shall be required of thee", "Go and sell all", "Follow me"]'::jsonb, 1, 'He laid up treasure for himself and was not rich toward God.', 'Luke 12:20', 'Parables', 'medium'),
('In the parable of the Pharisee and the publican, who went home justified?', '["The Pharisee", "The publican", "Both", "Neither"]'::jsonb, 1, '"Every one that exalteth himself shall be abased."', 'Luke 18:14', 'Parables', 'medium'),
('What did the master say to the faithful servant in the parable of the talents?', '["Come up higher", "Well done, thou good and faithful servant", "Depart from me", "Give an account"]'::jsonb, 1, 'He was made ruler over many things and entered into his lord''s joy.', 'Matthew 25:21', 'Parables', 'easy'),

-- ---- Prayer (new category) ------------------------------------------------
('Where did Jesus teach the prayer beginning "Our Father which art in heaven"?', '["In the temple", "In the Sermon on the Mount", "At the Last Supper", "In Gethsemane"]'::jsonb, 1, 'The model prayer was given in the Sermon on the Mount.', 'Matthew 6:9-13', 'Prayer', 'medium'),
('How many times a day did Daniel pray, even when it was forbidden?', '["Once", "Twice", "Three times", "Seven times"]'::jsonb, 2, 'Daniel kneeled three times a day with his windows open toward Jerusalem.', 'Daniel 6:10', 'Prayer', 'easy'),
('What did Jesus pray in Gethsemane?', '["Let this cup pass, nevertheless not my will, but thine, be done", "Father, forgive them", "It is finished", "Why hast thou forsaken me"]'::jsonb, 0, 'He surrendered fully to the Father''s will.', 'Luke 22:42', 'Prayer', 'medium'),
('Where did Jesus often go to pray?', '["The market", "A solitary place or a mountain", "The synagogue only", "The city gate"]'::jsonb, 1, 'Rising up a great while before day, He departed into a solitary place.', 'Mark 1:35', 'Prayer', 'easy'),
('Complete: "The effectual fervent prayer of a righteous man availeth ___."', '["little", "much", "nothing", "sometimes"]'::jsonb, 1, 'James points to Elias as the example of prevailing prayer.', 'James 5:16', 'Prayer', 'medium'),
('According to James, what should we do if we lack wisdom?', '["Ask of God", "Consult the elders", "Wait quietly", "Study harder"]'::jsonb, 0, '"Let him ask of God, that giveth to all men liberally."', 'James 1:5', 'Prayer', 'easy'),
('Whose prayer stopped the rain for three years and six months?', '["Elisha", "Elijah", "Samuel", "Moses"]'::jsonb, 1, 'Elias was a man subject to like passions as we are, and he prayed earnestly.', 'James 5:17', 'Prayer', 'medium'),
('Who prayed and the sun stood still over Gibeon?', '["Moses", "Joshua", "Gideon", "Hezekiah"]'::jsonb, 1, 'The LORD hearkened unto the voice of a man in that day.', 'Joshua 10:12-14', 'Prayer', 'hard'),
('What did Jesus say about praying to be seen by others?', '["It is acceptable", "They have their reward already", "It doubles the blessing", "It is required"]'::jsonb, 1, 'Rather, enter into thy closet and pray to thy Father in secret.', 'Matthew 6:5-6', 'Prayer', 'medium'),
('Complete: "Ask, and it shall be given you; seek, and ye shall ___."', '["wait", "find", "rest", "believe"]'::jsonb, 1, '"Knock, and it shall be opened unto you."', 'Matthew 7:7', 'Prayer', 'easy');

-- Safety net: these batches were written against a bank that already held
-- 158 questions, and seven of them collided with existing rows. Re-running
-- any of these files is now harmless.
delete from public.quiz_questions q
 where q.id > (select min(q2.id) from public.quiz_questions q2
                where q2.question = q.question);
