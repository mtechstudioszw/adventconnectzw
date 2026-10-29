/// The 28 Fundamental Beliefs of the Seventh-day Adventist Church.
///
/// Owner, 29 Oct 2026: "our own summaries plus a link to adventist.org".
/// The official wording belongs to the General Conference, so it is NOT
/// copied here. Each [summary] is a short plain-language summary written
/// for this app, and the screen always links to the official statement.
/// Titles and numbering follow the official list (2015 revision).
///
/// [texts] are a few key passages for each belief — not the official
/// statement's full reference list. Each must resolve through
/// `BibleService.resolveReference` (a test checks this), so they are
/// written with full book names.
///
/// Content review: these summaries should be read by a pastor or the
/// owner before wide release. Correct wording here, not in the screen.
class FundamentalBelief {
  const FundamentalBelief({
    required this.number,
    required this.title,
    required this.group,
    required this.summary,
    required this.texts,
  });

  final int number;
  final String title;

  /// The six headings the official list is grouped under.
  final String group;
  final String summary;
  final List<String> texts;
}

/// Where the official statement lives.
const String kBeliefsOfficialUrl = 'https://www.adventist.org/beliefs/';

const String _god = 'The Doctrine of God';
const String _humanity = 'The Doctrine of Humanity';
const String _salvation = 'The Doctrine of Salvation';
const String _church = 'The Doctrine of the Church';
const String _life = 'The Doctrine of the Christian Life';
const String _lastThings = 'The Doctrine of Last Things';

const List<FundamentalBelief> kFundamentalBeliefs = [
  FundamentalBelief(
    number: 1,
    title: 'The Holy Scriptures',
    group: _god,
    summary:
        'The Old and New Testaments are the written Word of God, given by '
        'inspiration through people moved by the Holy Spirit. They are the '
        'standard by which all teaching and experience are tested, and the '
        'trustworthy record of God\'s acts in history.',
    texts: [
      '2 Timothy 3:16',
      '2 Peter 1:20',
      'Psalm 119:105',
      'Hebrews 4:12',
    ],
  ),
  FundamentalBelief(
    number: 2,
    title: 'The Trinity',
    group: _god,
    summary:
        'There is one God: Father, Son and Holy Spirit, a unity of three '
        'eternal Persons. God is all-powerful, all-knowing and ever present, '
        'and is worthy of worship and service by all creation.',
    texts: [
      'Deuteronomy 6:4',
      'Matthew 28:19',
      '2 Corinthians 13:14',
      'Ephesians 4:4',
    ],
  ),
  FundamentalBelief(
    number: 3,
    title: 'The Father',
    group: _god,
    summary:
        'God the eternal Father is Creator, Source, Sustainer and Ruler of '
        'all creation. He is just and holy, merciful and gracious, slow to '
        'anger and abounding in steadfast love. The love shown in the Son '
        'and the Spirit is the Father\'s love.',
    texts: [
      'Genesis 1:1',
      'Exodus 34:6',
      'John 3:16',
      '1 John 4:8',
    ],
  ),
  FundamentalBelief(
    number: 4,
    title: 'The Son',
    group: _god,
    summary:
        'God the eternal Son became truly human in Jesus Christ. Through Him '
        'all things were created and God\'s character is revealed. He lived '
        'without sin, died for our sins, rose from the dead and ascended to '
        'minister for us, and He will come again.',
    texts: [
      'John 1:1',
      'John 1:14',
      'Colossians 1:15',
      'Philippians 2:5',
      'Hebrews 4:15',
    ],
  ),
  FundamentalBelief(
    number: 5,
    title: 'The Holy Spirit',
    group: _god,
    summary:
        'God the eternal Spirit was active in creation, in the incarnation '
        'and in the inspiration of Scripture. He draws people to God, '
        'convicts of sin, renews those who respond, gives gifts to the '
        'church and guides into all truth.',
    texts: [
      'Genesis 1:2',
      'John 14:16',
      'John 16:7',
      'Acts 1:8',
    ],
  ),
  FundamentalBelief(
    number: 6,
    title: 'Creation',
    group: _humanity,
    summary:
        'God is Creator of all things, and Scripture gives the authentic '
        'account of His work. In a recent six-day creation the Lord made the '
        'heavens and the earth and all living things, and rested on the '
        'seventh day as a memorial of His finished work.',
    texts: [
      'Genesis 1:1',
      'Genesis 2:1',
      'Exodus 20:11',
      'Psalm 33:6',
      'Hebrews 11:3',
    ],
  ),
  FundamentalBelief(
    number: 7,
    title: 'The Nature of Humanity',
    group: _humanity,
    summary:
        'Man and woman were made in the image of God, each a whole being of '
        'body, mind and spirit, free to think and act, and dependent on God '
        'for life. When our first parents disobeyed, sin and death came to '
        'all; God in Christ reconciles us to Himself and restores His image.',
    texts: [
      'Genesis 1:26',
      'Genesis 2:7',
      'Psalm 8:4',
      'Romans 5:12',
    ],
  ),
  FundamentalBelief(
    number: 8,
    title: 'The Great Controversy',
    group: _humanity,
    summary:
        'All humanity is caught up in a great conflict between Christ and '
        'Satan over God\'s character, His law and His rule. It began in '
        'heaven when a created being rebelled, and it came to earth through '
        'the Fall. Christ\'s victory at the cross decides its outcome.',
    texts: [
      'Revelation 12:7',
      'Isaiah 14:12',
      'Ezekiel 28:12',
      'Genesis 3:1',
    ],
  ),
  FundamentalBelief(
    number: 9,
    title: 'The Life, Death, and Resurrection of Christ',
    group: _salvation,
    summary:
        'In Christ\'s life of perfect obedience, His suffering, death and '
        'resurrection, God provided the only means of atonement for sin. '
        'Those who accept it by faith have eternal life. His resurrection '
        'proclaims God\'s victory over sin and death.',
    texts: [
      'John 3:16',
      'Isaiah 53:4',
      '1 Corinthians 15:3',
      '2 Corinthians 5:21',
    ],
  ),
  FundamentalBelief(
    number: 10,
    title: 'The Experience of Salvation',
    group: _salvation,
    summary:
        'In love and mercy God made Christ, who knew no sin, to be sin for '
        'us, so that in Him we might be made righteous. Led by the Spirit we '
        'repent, trust Jesus as Saviour and Lord, and are forgiven, '
        'adopted as God\'s children and born again — by grace, through faith.',
    texts: [
      'Ephesians 2:8',
      'John 3:3',
      'Romans 3:21',
      '2 Corinthians 5:17',
    ],
  ),
  FundamentalBelief(
    number: 11,
    title: 'Growing in Christ',
    group: _salvation,
    summary:
        'By His death Jesus triumphed over the forces of evil. In Him we are '
        'set free to live in peace and joy, growing day by day through '
        'prayer, Scripture, worship, fellowship and service, as the Spirit '
        'shapes us into His likeness.',
    texts: [
      'Colossians 2:6',
      'Galatians 5:22',
      '1 John 4:4',
      '2 Peter 3:18',
    ],
  ),
  FundamentalBelief(
    number: 12,
    title: 'The Church',
    group: _church,
    summary:
        'The church is the community of believers who confess Jesus Christ '
        'as Lord and Saviour. It meets for worship, fellowship, instruction '
        'in the Word and the Lord\'s Supper, for service to humanity and to '
        'proclaim the gospel to all the world.',
    texts: [
      'Matthew 16:18',
      'Acts 2:42',
      'Ephesians 1:22',
      '1 Peter 2:9',
    ],
  ),
  FundamentalBelief(
    number: 13,
    title: 'The Remnant and Its Mission',
    group: _church,
    summary:
        'In the last days, when many have turned from God, a remnant is '
        'called to keep God\'s commandments and the faith of Jesus. It '
        'announces the hour of judgment, proclaims salvation through Christ '
        'and the three angels\' messages, and heralds His soon return.',
    texts: [
      'Revelation 12:17',
      'Revelation 14:6',
      'Revelation 18:1',
      '2 Corinthians 5:10',
    ],
  ),
  FundamentalBelief(
    number: 14,
    title: 'Unity in the Body of Christ',
    group: _church,
    summary:
        'The church is one body with many members from every nation, race, '
        'language and people. In Christ, distinctions of race, culture, '
        'status and gender must not divide us; we are equal in Him and '
        'united in His service.',
    texts: [
      'Psalm 133:1',
      'John 17:20',
      'Galatians 3:27',
      '1 Corinthians 12:12',
    ],
  ),
  FundamentalBelief(
    number: 15,
    title: 'Baptism',
    group: _church,
    summary:
        'By baptism we confess our faith in the death and resurrection of '
        'Jesus and testify that we have died to sin and been raised to walk '
        'in newness of life. It is by immersion, follows instruction in the '
        'Scriptures and acceptance of their teachings, and welcomes us into '
        'the church.',
    texts: [
      'Matthew 28:19',
      'Acts 2:38',
      'Romans 6:3',
      'Colossians 2:12',
    ],
  ),
  FundamentalBelief(
    number: 16,
    title: 'The Lord\'s Supper',
    group: _church,
    summary:
        'The Lord\'s Supper shares in the emblems of Jesus\' body and blood '
        'as an expression of faith in Him. It remembers His death and looks '
        'forward to His return. The service of foot-washing that prepares '
        'for it signifies renewed cleansing and humble service. It is open '
        'to all believing Christians.',
    texts: [
      '1 Corinthians 11:23',
      'Matthew 26:26',
      'John 13:14',
      '1 Corinthians 10:16',
    ],
  ),
  FundamentalBelief(
    number: 17,
    title: 'Spiritual Gifts and Ministries',
    group: _church,
    summary:
        'God gives every member of the church spiritual gifts to use in '
        'loving ministry for the common good. The Spirit distributes them '
        'as He wills, so that the church may be built up in faith and love '
        'and fulfil its mission.',
    texts: [
      'Romans 12:4',
      '1 Corinthians 12:7',
      'Ephesians 4:11',
      '1 Peter 4:10',
    ],
  ),
  FundamentalBelief(
    number: 18,
    title: 'The Gift of Prophecy',
    group: _church,
    summary:
        'Prophecy is one of the gifts of the Holy Spirit and an identifying '
        'mark of the remnant church. Adventists believe it was shown in the '
        'ministry of Ellen G. White, whose writings give comfort, guidance '
        'and correction. The Bible remains the standard by which all '
        'teaching and experience must be tested.',
    texts: [
      'Joel 2:28',
      'Acts 2:17',
      'Revelation 19:10',
      '1 Thessalonians 5:20',
    ],
  ),
  FundamentalBelief(
    number: 19,
    title: 'The Law of God',
    group: _life,
    summary:
        'The Ten Commandments express God\'s love, will and purposes, and '
        'are binding on all people in every age. Obedience is not a way to '
        'earn salvation but the fruit of it — a response of love to the God '
        'who saves us.',
    texts: [
      'Exodus 20:1',
      'Matthew 5:17',
      'John 14:15',
      'Romans 8:3',
    ],
  ),
  FundamentalBelief(
    number: 20,
    title: 'The Sabbath',
    group: _life,
    summary:
        'The Creator rested on the seventh day and set it apart as a '
        'memorial of creation. The fourth commandment calls us to keep the '
        'seventh-day Sabbath, from sunset Friday to sunset Saturday, as a '
        'day of rest, worship and joyful fellowship with God and one another.',
    texts: [
      'Genesis 2:2',
      'Exodus 20:8',
      'Mark 2:27',
      'Isaiah 58:13',
    ],
  ),
  FundamentalBelief(
    number: 21,
    title: 'Stewardship',
    group: _life,
    summary:
        'We are God\'s stewards, trusted with time, abilities, possessions, '
        'the earth and its resources. We acknowledge His ownership through '
        'faithful service and by returning tithes and giving offerings for '
        'the proclamation of the gospel.',
    texts: [
      'Genesis 1:26',
      'Malachi 3:10',
      '1 Corinthians 4:2',
      '2 Corinthians 9:7',
    ],
  ),
  FundamentalBelief(
    number: 22,
    title: 'Christian Behavior',
    group: _life,
    summary:
        'We are called to think, feel and act in harmony with heaven. That '
        'touches what we watch, read and listen to, how we dress and what we '
        'eat and drink. Because the body is the temple of the Holy Spirit, '
        'we care for it wisely and avoid what harms it.',
    texts: [
      'Romans 12:1',
      '1 Corinthians 6:19',
      'Philippians 4:8',
      '1 Corinthians 10:31',
    ],
  ),
  FundamentalBelief(
    number: 23,
    title: 'Marriage and the Family',
    group: _life,
    summary:
        'Marriage was established by God in Eden as a lifelong union between '
        'a man and a woman in loving companionship. Families are to grow in '
        'love, respect and faithfulness, and parents are to bring up their '
        'children to love and obey the Lord.',
    texts: [
      'Genesis 2:18',
      'Matthew 19:4',
      'Ephesians 5:21',
      'Deuteronomy 6:6',
    ],
  ),
  FundamentalBelief(
    number: 24,
    title: 'Christ\'s Ministry in the Heavenly Sanctuary',
    group: _lastThings,
    summary:
        'There is a sanctuary in heaven where Christ ministers on our '
        'behalf, applying the benefits of His sacrifice. Adventists believe '
        'that in 1844, at the end of the 2300-day prophecy, He entered the '
        'second phase of that ministry — a work of judgment that prepares '
        'for His return.',
    texts: [
      'Hebrews 8:1',
      'Hebrews 4:14',
      'Daniel 8:14',
      'Hebrews 9:24',
    ],
  ),
  FundamentalBelief(
    number: 25,
    title: 'The Second Coming of Christ',
    group: _lastThings,
    summary:
        'The second coming of Christ is the blessed hope of the church. His '
        'return will be literal, personal, visible and worldwide. The '
        'righteous dead will be raised and, with the righteous living, taken '
        'to heaven. Fulfilled prophecy shows His coming is near.',
    texts: [
      'Titus 2:13',
      'John 14:1',
      'Acts 1:11',
      '1 Thessalonians 4:16',
    ],
  ),
  FundamentalBelief(
    number: 26,
    title: 'Death and Resurrection',
    group: _lastThings,
    summary:
        'The wages of sin is death, but God, who alone is immortal, gives '
        'eternal life to the redeemed. Until that day death is an '
        'unconscious state for all who have died. When Christ returns, the '
        'righteous dead will be raised and given immortality.',
    texts: [
      'Romans 6:23',
      'Ecclesiastes 9:5',
      'John 5:28',
      '1 Timothy 6:16',
    ],
  ),
  FundamentalBelief(
    number: 27,
    title: 'The Millennium and the End of Sin',
    group: _lastThings,
    summary:
        'The millennium is the thousand-year reign of Christ with His saints '
        'in heaven between the first and second resurrections. At its close '
        'Christ, His people and the Holy City descend to earth, the wicked '
        'are raised, and fire from God ends sin and sinners for ever.',
    texts: [
      'Revelation 20:1',
      '1 Corinthians 6:2',
      'Jeremiah 4:23',
      'Malachi 4:1',
    ],
  ),
  FundamentalBelief(
    number: 28,
    title: 'The New Earth',
    group: _lastThings,
    summary:
        'On the new earth, where righteousness dwells, God will make an '
        'eternal home for the redeemed. Pain and death will have passed '
        'away, and God Himself will live with His people. The great '
        'controversy will be ended, and the whole universe will declare '
        'that God is love.',
    texts: [
      '2 Peter 3:13',
      'Isaiah 65:17',
      'Revelation 21:1',
      'Revelation 22:1',
    ],
  ),
];
