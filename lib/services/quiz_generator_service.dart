import 'dart:math';

import '../models/quiz_question_model.dart';
import 'bible_service.dart';

/// Generates Bible questions from the bundled KJV, forever.
///
/// The curated bank in Supabase is ~160 questions — a daily player empties
/// it in a fortnight. This closes that hole: the app already ships the full
/// KJV (`assets/bible/kjv.json`, 66 books / ~31k verses) for the Library, so
/// the same asset can mint verifiable questions offline, at no cost, without
/// anyone writing another one.
///
/// The hard part isn't generating questions — it's not generating *bad*
/// ones. Every template here is gated:
///
/// * **Ambiguity.** A "which book is this from?" verse is skipped if the
///   same text appears in more than one book (Gospel parallels,
///   Kings/Chronicles).
/// * **Fill-in-the-blank** only ever blanks a word from a hand-written
///   [_wordGroups] set, and only when the verse contains *exactly one*
///   member of that group — so the three distractors are always the right
///   kind of word, and never secretly also correct.
/// * **No leaked answers.** The blanked word must occur exactly ONCE in
///   the verse. Without this, "the service of the ___ of the LORD … to
///   repair the house of the LORD" blanks one "house" and leaves the
///   answer printed twice in the same sentence.
/// * **Answerability.** Verse templates only draw from [_wellKnownChapters]
///   — the passages a congregation actually reads. Blanking a word in
///   Ezra's Nethinim roster is a lottery, not a quiz question.
/// * **Junk verses.** Genealogies, census lines and fragments are filtered
///   out before anything is generated.
///
/// Everything is deterministic for a given seed, so the Daily Challenge is
/// still identical for every player.
class QuizGenerator {
  QuizGenerator._();

  /// Prefix on every generated id, so rotation/resume/reporting can tell
  /// generated questions from curated rows.
  static const String idPrefix = 'gen';

  static bool isGenerated(String id) => id.startsWith('$idPrefix:');

  static _Index? _index;
  static Future<_Index>? _building;

  /// Build the index if it isn't built. Call this when the lobby opens so
  /// the cost is paid behind the UI rather than in front of the player.
  static Future<void> warm() => _ensureIndex().then((_) {});

  static bool get isWarm => _index != null;

  static Future<_Index> _ensureIndex() {
    final ready = _index;
    if (ready != null) return Future.value(ready);
    return _building ??= _buildIndex().then((value) {
      _index = value;
      _building = null;
      return value;
    });
  }

  /// Produce [count] questions.
  ///
  /// [seed] makes the output reproducible — the Daily Challenge passes the
  /// date so everyone gets the same questions. [exclude] holds ids the
  /// player has seen recently; the generator simply keeps drawing past them.
  static Future<List<QuizQuestion>> generate({
    required int count,
    int? seed,
    Set<String> exclude = const {},
    String? category,
  }) async {
    if (count <= 0) return const [];
    final index = await _ensureIndex();
    if (!index.usable) return const [];

    final rng = Random(seed ?? DateTime.now().microsecondsSinceEpoch);
    final out = <QuizQuestion>[];
    final used = <String>{};

    // Bounded: templates can decline (a gate rejects the draw), so cap the
    // attempts rather than risk spinning on a thin index.
    final maxAttempts = count * 40;
    for (var attempt = 0; attempt < maxAttempts && out.length < count; attempt++) {
      final template = _pickTemplate(rng, category);
      final question = _build(template, index, rng);
      if (question == null) continue;
      if (used.contains(question.id) || exclude.contains(question.id)) continue;
      if (category != null && question.category != category) continue;
      used.add(question.id);
      out.add(question);
    }
    return out;
  }

  /// Categories this generator can fill, so the lobby can offer them as
  /// topics that never run dry.
  static const List<String> categories = ['Scripture', 'Bible Basics'];

  // ---- Template selection -------------------------------------------------

  static _Template _pickTemplate(Random rng, String? category) {
    // Verse templates carry the round; structural ones add variety.
    const weighted = <_Template>[
      _Template.fillBlank,
      _Template.fillBlank,
      _Template.fillBlank,
      _Template.whichBook,
      _Template.whichBook,
      _Template.whichBook,
      _Template.whereFound,
      _Template.comesFirst,
      _Template.chapterCount,
      _Template.notABook,
      _Template.whichTestament,
    ];
    if (category == 'Bible Basics') {
      const structural = <_Template>[
        _Template.comesFirst,
        _Template.chapterCount,
        _Template.notABook,
        _Template.whichTestament,
      ];
      return structural[rng.nextInt(structural.length)];
    }
    if (category == 'Scripture') {
      const verse = <_Template>[
        _Template.fillBlank,
        _Template.fillBlank,
        _Template.whichBook,
        _Template.whereFound,
      ];
      return verse[rng.nextInt(verse.length)];
    }
    return weighted[rng.nextInt(weighted.length)];
  }

  static QuizQuestion? _build(_Template t, _Index i, Random rng) =>
      switch (t) {
        _Template.fillBlank => _buildFillBlank(i, rng),
        _Template.whichBook => _buildWhichBook(i, rng),
        _Template.whereFound => _buildWhereFound(i, rng),
        _Template.comesFirst => _buildComesFirst(i, rng),
        _Template.chapterCount => _buildChapterCount(i, rng),
        _Template.notABook => _buildNotABook(i, rng),
        _Template.whichTestament => _buildWhichTestament(i, rng),
      };

  // ---- Templates ----------------------------------------------------------

  /// "Blessed are the ______ in heart: for they shall see God."
  static QuizQuestion? _buildFillBlank(_Index i, Random rng) {
    if (i.fillCandidates.isEmpty) return null;
    final pick = i.fillCandidates[rng.nextInt(i.fillCandidates.length)];
    final group = _wordGroups[pick.groupIndex];
    final answer = group[pick.wordIndex];

    final book = i.books[pick.bookIndex];
    if (pick.chapter >= book.chapters.length) return null;
    final verses = book.chapters[pick.chapter];
    if (pick.verse >= verses.length) return null;
    final text = BibleService.cleanVerse(verses[pick.verse]);

    // Blank the word, preserving the original casing pattern of the line.
    final pattern = RegExp(r'\b' + RegExp.escape(answer) + r'\b',
        caseSensitive: false);
    if (!pattern.hasMatch(text)) return null;
    final blanked = text.replaceFirst(pattern, '______');

    final options = _distinctOptions(
      correct: answer,
      pool: group,
      rng: rng,
      exclude: (candidate) => pattern.hasMatch(candidate)
          ? false
          : RegExp(r'\b' + RegExp.escape(candidate) + r'\b',
                  caseSensitive: false)
              .hasMatch(text),
    );
    if (options == null) return null;

    final reference = '${book.name} ${pick.chapter + 1}:${pick.verse + 1}';
    final famous = i.famousKeys.contains(pick.code);
    return QuizQuestion(
      id: '$idPrefix:fill:${pick.code}:${pick.groupIndex}',
      question: 'Complete the verse:\n\n"$blanked"',
      options: options.options,
      correctIndex: options.correctIndex,
      category: 'Scripture',
      difficulty: famous ? 'easy' : 'medium',
      explanation: '"$text"',
      reference: reference,
    );
  }

  /// "Which book of the Bible is this verse from?"
  static QuizQuestion? _buildWhichBook(_Index i, Random rng) {
    if (i.bookCandidates.isEmpty) return null;
    final code = i.bookCandidates[rng.nextInt(i.bookCandidates.length)];
    final bookIndex = _bookOf(code);
    final chapter = _chapterOf(code);
    final verse = _verseOf(code);
    final book = i.books[bookIndex];
    if (chapter >= book.chapters.length) return null;
    final verses = book.chapters[chapter];
    if (verse >= verses.length) return null;
    final text = BibleService.cleanVerse(verses[verse]);

    final distractors = _bookDistractors(i, bookIndex, rng);
    if (distractors == null) return null;

    final options = <String>[book.name, ...distractors]..shuffle(rng);
    final famous = i.famousKeys.contains(code);
    return QuizQuestion(
      id: '$idPrefix:book:$code',
      question: 'Which book of the Bible is this verse from?\n\n"$text"',
      options: options,
      correctIndex: options.indexOf(book.name),
      category: 'Scripture',
      // Every candidate now comes from a well-known chapter, so these are
      // fair rather than obscure — 'hard' would misrepresent them.
      difficulty: famous ? 'easy' : 'medium',
      explanation:
          'It comes from ${book.name} ${chapter + 1}:${verse + 1}.',
      reference: '${book.name} ${chapter + 1}:${verse + 1}',
    );
  }

  /// "Where is this verse found?" — famous verses only, otherwise it's
  /// unanswerable trivia rather than a quiz question.
  static QuizQuestion? _buildWhereFound(_Index i, Random rng) {
    if (i.famous.length < 4) return null;
    final code = i.famous[rng.nextInt(i.famous.length)];
    final bookIndex = _bookOf(code);
    final chapter = _chapterOf(code);
    final verse = _verseOf(code);
    final book = i.books[bookIndex];
    if (chapter >= book.chapters.length) return null;
    final verses = book.chapters[chapter];
    if (verse >= verses.length) return null;
    final text = BibleService.cleanVerse(verses[verse]);
    final correct = '${book.name} ${chapter + 1}:${verse + 1}';

    // One near-miss in the same book, two from other famous verses — a
    // spread that rewards actually knowing the reference.
    final options = <String>{correct};
    final chapterCount = book.chapters.length;
    if (chapterCount > 1) {
      var other = chapter;
      for (var tries = 0; tries < 8 && other == chapter; tries++) {
        other = rng.nextInt(chapterCount);
      }
      if (other != chapter) {
        final maxVerse = book.chapters[other].length;
        options.add('${book.name} ${other + 1}:${rng.nextInt(maxVerse) + 1}');
      }
    }
    for (var tries = 0; tries < 24 && options.length < 4; tries++) {
      final alt = i.famous[rng.nextInt(i.famous.length)];
      if (_bookOf(alt) == bookIndex) continue;
      final altBook = i.books[_bookOf(alt)];
      options.add(
          '${altBook.name} ${_chapterOf(alt) + 1}:${_verseOf(alt) + 1}');
    }
    if (options.length < 4) return null;

    final list = options.toList()..shuffle(rng);
    return QuizQuestion(
      id: '$idPrefix:where:$code',
      question: 'Where is this verse found?\n\n"$text"',
      options: list,
      correctIndex: list.indexOf(correct),
      category: 'Scripture',
      difficulty: 'medium',
      explanation: 'This is $correct.',
      reference: correct,
    );
  }

  /// "Which of these books comes FIRST in the Bible?"
  static QuizQuestion? _buildComesFirst(_Index i, Random rng) {
    final picks = <int>{};
    for (var tries = 0; tries < 40 && picks.length < 4; tries++) {
      picks.add(rng.nextInt(i.books.length));
    }
    if (picks.length < 4) return null;
    final ordered = picks.toList()..sort();
    // Too-close a spread makes it a coin flip; require real separation.
    if (ordered.last - ordered.first < 6) return null;

    final correct = i.books[ordered.first].name;
    final options = [for (final b in picks) i.books[b].name]..shuffle(rng);
    final key = (picks.toList()..sort()).join('-');
    return QuizQuestion(
      id: '$idPrefix:first:$key',
      question: 'Which of these books comes FIRST in the Bible?',
      options: options,
      correctIndex: options.indexOf(correct),
      category: 'Bible Basics',
      difficulty: ordered[1] - ordered[0] < 10 ? 'hard' : 'medium',
      explanation:
          '$correct is book ${ordered.first + 1} of 66; the others come later.',
      reference: '-',
    );
  }

  /// "How many chapters are in the book of Daniel?"
  static QuizQuestion? _buildChapterCount(_Index i, Random rng) {
    final bookIndex = rng.nextInt(i.books.length);
    final book = i.books[bookIndex];
    final count = book.chapters.length;
    if (count <= 0) return null;

    final numbers = <int>{count};
    for (var tries = 0; tries < 40 && numbers.length < 4; tries++) {
      final delta = 1 + rng.nextInt(count <= 5 ? 4 : (count ~/ 3).clamp(2, 12));
      final candidate = rng.nextBool() ? count + delta : count - delta;
      if (candidate > 0) numbers.add(candidate);
    }
    if (numbers.length < 4) return null;

    final options = numbers.map((n) => '$n').toList()..shuffle(rng);
    return QuizQuestion(
      id: '$idPrefix:chapters:$bookIndex',
      question: 'How many chapters are in the book of ${book.name}?',
      options: options,
      correctIndex: options.indexOf('$count'),
      category: 'Bible Basics',
      difficulty: count == 1 ? 'medium' : 'hard',
      explanation: '${book.name} has $count '
          '${count == 1 ? 'chapter' : 'chapters'}.',
      reference: '-',
    );
  }

  /// "Which of these is NOT a book of the Bible?"
  static QuizQuestion? _buildNotABook(_Index i, Random rng) {
    final fake = _notBooks[rng.nextInt(_notBooks.length)];
    final real = <String>{};
    for (var tries = 0; tries < 40 && real.length < 3; tries++) {
      real.add(i.books[rng.nextInt(i.books.length)].name);
    }
    if (real.length < 3) return null;

    final options = <String>[fake, ...real]..shuffle(rng);
    return QuizQuestion(
      id: '$idPrefix:notbook:$fake:${(real.toList()..sort()).join("|")}',
      question: 'Which of these is NOT a book of the Bible?',
      options: options,
      correctIndex: options.indexOf(fake),
      category: 'Bible Basics',
      difficulty: 'medium',
      explanation: 'There is no book of $fake in the Bible. '
          'The other three are among the 66.',
      reference: '-',
    );
  }

  /// "Which of these books is in the New Testament?"
  static QuizQuestion? _buildWhichTestament(_Index i, Random rng) {
    const firstNt = 39;
    final newTestament = i.books[firstNt + rng.nextInt(i.books.length - firstNt)];
    final old = <String>{};
    for (var tries = 0; tries < 40 && old.length < 3; tries++) {
      old.add(i.books[rng.nextInt(firstNt)].name);
    }
    if (old.length < 3) return null;

    final options = <String>[newTestament.name, ...old]..shuffle(rng);
    return QuizQuestion(
      id: '$idPrefix:testament:${newTestament.name}:'
          '${(old.toList()..sort()).join("|")}',
      question: 'Which of these books is in the NEW Testament?',
      options: options,
      correctIndex: options.indexOf(newTestament.name),
      category: 'Bible Basics',
      difficulty: 'easy',
      explanation:
          '${newTestament.name} is in the New Testament; the other three '
          'are in the Old.',
      reference: '-',
    );
  }

  // ---- Option helpers -----------------------------------------------------

  /// Four distinct options built from [pool], with [correct] among them.
  /// [exclude] rejects a distractor (used to drop words already in the verse).
  static _Options? _distinctOptions({
    required String correct,
    required List<String> pool,
    required Random rng,
    bool Function(String candidate)? exclude,
  }) {
    final chosen = <String>{correct};
    for (var tries = 0; tries < 60 && chosen.length < 4; tries++) {
      final candidate = pool[rng.nextInt(pool.length)];
      if (candidate == correct) continue;
      if (exclude != null && exclude(candidate)) continue;
      chosen.add(candidate);
    }
    if (chosen.length < 4) return null;
    final list = chosen.toList()..shuffle(rng);
    return _Options(list, list.indexOf(correct));
  }

  /// Three wrong books, preferring the same genre so the question tests
  /// knowledge rather than letting the odd-one-out give it away.
  static List<String>? _bookDistractors(_Index i, int bookIndex, Random rng) {
    final genre = _genreOf(bookIndex);
    final sameGenre = [
      for (var b = genre.$1; b <= genre.$2; b++)
        if (b != bookIndex) b,
    ];
    final sameTestament = [
      for (var b = bookIndex < 39 ? 0 : 39;
          b < (bookIndex < 39 ? 39 : i.books.length);
          b++)
        if (b != bookIndex) b,
    ];

    final chosen = <int>{};
    for (var tries = 0; tries < 30 && chosen.length < 3; tries++) {
      if (sameGenre.isNotEmpty) {
        chosen.add(sameGenre[rng.nextInt(sameGenre.length)]);
      }
    }
    for (var tries = 0; tries < 30 && chosen.length < 3; tries++) {
      if (sameTestament.isNotEmpty) {
        chosen.add(sameTestament[rng.nextInt(sameTestament.length)]);
      }
    }
    if (chosen.length < 3) return null;
    return [for (final b in chosen.take(3)) i.books[b].name];
  }

  /// (firstIndex, lastIndex) of the genre block a book belongs to.
  static (int, int) _genreOf(int index) {
    if (index <= 4) return (0, 4); // Law
    if (index <= 16) return (5, 16); // History
    if (index <= 21) return (17, 21); // Poetry / Wisdom
    if (index <= 26) return (22, 26); // Major Prophets
    if (index <= 38) return (27, 38); // Minor Prophets
    if (index <= 43) return (39, 43); // Gospels + Acts
    if (index <= 56) return (44, 56); // Pauline Epistles
    if (index <= 64) return (57, 64); // General Epistles
    return (57, 65); // Revelation sits with the general epistles as a block
  }

  // ---- Index --------------------------------------------------------------

  static Future<_Index> _buildIndex() async {
    final books = await BibleService.books();
    if (books.isEmpty) return _Index.empty();

    final bookByName = <String, int>{
      for (var i = 0; i < books.length; i++) books[i].name: i,
    };

    // Famous verses drive the easy end and the "where is this found?"
    // template. Codes, not names, so lookups stay cheap.
    final famous = <int>[];
    for (final entry in _famous) {
      final index = bookByName[entry.$1];
      if (index == null) continue;
      final chapter = entry.$2 - 1;
      final verse = entry.$3 - 1;
      if (chapter < 0 || chapter >= books[index].chapters.length) continue;
      if (verse < 0 || verse >= books[index].chapters[chapter].length) continue;
      famous.add(_code(index, chapter, verse));
    }
    final famousKeys = famous.toSet();

    // Pass 1: find verse texts that occur in more than one book, so
    // "which book is this from?" never has two right answers. Hashed to
    // ints — a hash collision costs us one usable verse, nothing worse.
    final seenTextBook = <int, int>{};
    final duplicateTexts = <int>{};
    for (var b = 0; b < books.length; b++) {
      for (final chapter in books[b].chapters) {
        for (final raw in chapter) {
          final hash = _normalise(raw).hashCode;
          final previous = seenTextBook[hash];
          if (previous == null) {
            seenTextBook[hash] = b;
          } else if (previous != b) {
            duplicateTexts.add(hash);
          }
        }
      }
    }

    // Which (book, chapter) pairs the verse templates may draw from.
    final knownChapters = <int>{};
    for (final entry in _wellKnownChapters.entries) {
      final index = bookByName[entry.key];
      if (index == null) continue;
      for (final chapter in entry.value) {
        knownChapters.add(index * 1000 + (chapter - 1));
      }
    }

    // Pass 2: gather the two candidate pools, well-known passages only.
    final fillCandidates = <_FillCandidate>[];
    final bookCandidates = <int>[];

    for (var b = 0; b < books.length; b++) {
      final chapters = books[b].chapters;
      for (var c = 0; c < chapters.length; c++) {
        if (!knownChapters.contains(b * 1000 + c)) continue;
        final verses = chapters[c];
        for (var v = 0; v < verses.length; v++) {
          final text = BibleService.cleanVerse(verses[v]);
          if (!_isUsableVerse(text)) continue;
          final code = _code(b, c, v);

          if (!duplicateTexts.contains(_normalise(verses[v]).hashCode) &&
              text.length >= 60) {
            bookCandidates.add(code);
          }

          // Tokenise once, then test every word group against the set.
          final words = _tokenise(text);
          if (words.length < 8) continue;
          for (var g = 0; g < _wordGroups.length; g++) {
            final group = _wordGroups[g];
            var matchIndex = -1;
            var matches = 0;
            for (var w = 0; w < group.length; w++) {
              if (words.contains(group[w])) {
                matches++;
                if (matches > 1) break;
                matchIndex = w;
              }
            }
            // Exactly one DISTINCT member present → the three distractors
            // can never also be sitting in the verse.
            if (matches != 1 || matchIndex < 0) continue;
            // …and that member must occur exactly once, or blanking the
            // first hit leaves the answer visible later in the verse.
            if (_countWord(group[matchIndex], text) != 1) continue;
            fillCandidates.add(_FillCandidate(b, c, v, code, g, matchIndex));
          }
        }
      }
    }

    return _Index(
      books: books,
      fillCandidates: fillCandidates,
      bookCandidates: bookCandidates,
      famous: famous,
      famousKeys: famousKeys,
    );
  }

  /// Rejects verses that make bad questions: fragments, genealogies,
  /// census lines, and anything too long to read on a phone.
  static bool _isUsableVerse(String text) {
    if (text.length < 45 || text.length > 240) return false;
    final lower = text.toLowerCase();
    for (final marker in _junkMarkers) {
      if (lower.contains(marker)) return false;
    }
    // Verses that are mostly names/numbers (genealogies, tribal censuses).
    final digits = RegExp(r'\d').allMatches(text).length;
    if (digits > 6) return false;
    return true;
  }

  /// How many times [word] appears in [text] as a whole word.
  static int _countWord(String word, String text) =>
      RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false)
          .allMatches(text)
          .length;

  /// Lowercased word set for a verse.
  static Set<String> _tokenise(String text) => text
      .toLowerCase()
      .split(RegExp(r"[^a-z']+"))
      .where((w) => w.length > 1)
      .toSet();

  /// Normalised form used only for duplicate detection.
  static String _normalise(String raw) => BibleService.cleanVerse(raw)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Verse coordinates packed into one int: book * 200000 + chapter * 200
  // + verse. Psalms has 150 chapters and Psalm 119 has 176 verses, so 200
  // clears both with room to spare.
  static int _code(int book, int chapter, int verse) =>
      book * 200000 + chapter * 200 + verse;
  static int _bookOf(int code) => code ~/ 200000;
  static int _chapterOf(int code) => (code % 200000) ~/ 200;
  static int _verseOf(int code) => code % 200;
}

enum _Template {
  fillBlank,
  whichBook,
  whereFound,
  comesFirst,
  chapterCount,
  notABook,
  whichTestament,
}

class _Options {
  const _Options(this.options, this.correctIndex);
  final List<String> options;
  final int correctIndex;
}

class _FillCandidate {
  const _FillCandidate(
    this.bookIndex,
    this.chapter,
    this.verse,
    this.code,
    this.groupIndex,
    this.wordIndex,
  );
  final int bookIndex, chapter, verse, code, groupIndex, wordIndex;
}

class _Index {
  const _Index({
    required this.books,
    required this.fillCandidates,
    required this.bookCandidates,
    required this.famous,
    required this.famousKeys,
  });

  factory _Index.empty() => const _Index(
        books: [],
        fillCandidates: [],
        bookCandidates: [],
        famous: [],
        famousKeys: {},
      );

  final List<BibleBook> books;
  final List<_FillCandidate> fillCandidates;
  final List<int> bookCandidates;
  final List<int> famous;
  final Set<int> famousKeys;

  bool get usable => books.length == 66 && bookCandidates.isNotEmpty;
}

/// Phrases that mark a verse as a poor question source.
const List<String> _junkMarkers = [
  'begat',
  'the son of',
  'sons of',
  'were numbered',
  'according to their families',
  'by their generations',
  'the children of israel, after their families',
];

/// Word groups for fill-in-the-blank. Members must be words the KJV
/// actually uses, and every member of a group must be interchangeable
/// enough to look plausible in the blank — that's what stops the answer
/// being guessable by elimination.
const List<List<String>> _wordGroups = [
  // Virtues / graces
  ['faith', 'hope', 'charity', 'mercy', 'grace', 'truth', 'peace', 'joy'],
  // Numbers
  ['three', 'four', 'five', 'six', 'seven', 'ten', 'twelve', 'forty'],
  // Body
  ['heart', 'soul', 'hand', 'mouth', 'head', 'tongue', 'flesh', 'blood'],
  // Family
  ['father', 'mother', 'son', 'daughter', 'brother', 'sister', 'wife'],
  // Creation / places
  ['heaven', 'earth', 'sea', 'mountain', 'river', 'wilderness', 'field'],
  // Light and time
  ['light', 'darkness', 'morning', 'evening', 'shadow', 'noonday'],
  // Creatures
  ['lamb', 'lion', 'sheep', 'serpent', 'dove', 'eagle', 'horse', 'goat'],
  // Offices
  ['king', 'priest', 'prophet', 'servant', 'shepherd', 'angel', 'judge'],
  // Structures
  ['house', 'temple', 'tabernacle', 'city', 'tower', 'gate', 'altar', 'throne'],
  // Materials
  ['gold', 'silver', 'brass', 'iron', 'stone', 'oil', 'wine', 'bread'],
  // Moral vocabulary
  ['sin', 'righteousness', 'iniquity', 'wickedness', 'judgment', 'salvation'],
  // Words of covenant
  ['word', 'voice', 'name', 'commandment', 'law', 'covenant', 'testimony'],
  // Time
  ['sabbath', 'generation', 'year', 'month', 'week', 'season'],
];

/// Plausible-sounding names that are NOT books of the Bible. Several are
/// real biblical *people* (or a book the Bible merely mentions, like
/// Jasher) — which is exactly what makes the question worth asking.
const List<String> _notBooks = [
  'Hezekiah',
  'Jasher',
  'Enoch',
  'Barnabas',
  'Thaddeus',
  'Gideon',
  'Elijah',
  'Miriam',
  'Caleb',
  'Silas',
  'Abednego',
  'Cornelius',
  'Lazarus',
  'Nicodemus',
  'Deborah',
];

/// The passages the verse templates are allowed to draw from, 1-based.
///
/// This is the single most important quality gate in the file. Without it
/// the generator happily asks you to complete a word in a Nethinim roster
/// in Ezra 8 — technically a valid question, useless as a quiz. Restricting
/// to chapters a congregation actually reads still leaves ~3,600 blank
/// candidates over ~2,700 verses and ~5,400 which-book verses, which is
/// hundreds of rounds before anything repeats — and every one of them is
/// fair to a player who knows their Bible.
const Map<String, List<int>> _wellKnownChapters = {
  'Genesis': [1, 2, 3, 6, 7, 12, 22, 37, 39, 41],
  'Exodus': [3, 12, 14, 20, 32],
  'Leviticus': [23],
  'Deuteronomy': [6, 28, 30],
  'Joshua': [1, 6, 24],
  'Judges': [6, 7, 16],
  'Ruth': [1],
  '1 Samuel': [3, 16, 17],
  '2 Samuel': [11, 12],
  '1 Kings': [3, 17, 18, 19],
  '2 Kings': [2, 5],
  'Nehemiah': [8],
  'Esther': [4],
  'Job': [1, 2, 38, 42],
  'Psalms': [
    1, 8, 19, 23, 24, 27, 34, 37, 42, 46, 51, 63, 84, 91, 100, 103, 119,
    121, 127, 133, 139, 150,
  ],
  'Proverbs': [1, 3, 4, 10, 15, 16, 22, 31],
  'Ecclesiastes': [3, 12],
  'Isaiah': [1, 6, 9, 11, 40, 53, 55, 58, 61, 66],
  'Jeremiah': [1, 29, 31],
  'Ezekiel': [34, 36, 37],
  'Daniel': [1, 2, 3, 6, 7, 8, 9, 12],
  'Joel': [2],
  'Jonah': [1, 2, 3, 4],
  'Micah': [6],
  'Malachi': [3, 4],
  'Matthew': [1, 2, 4, 5, 6, 7, 13, 18, 24, 25, 26, 27, 28],
  'Mark': [1, 4, 16],
  'Luke': [1, 2, 10, 15, 16, 23, 24],
  'John': [1, 3, 4, 6, 10, 11, 13, 14, 15, 17, 20, 21],
  'Acts': [1, 2, 3, 9, 16, 17, 26],
  'Romans': [1, 3, 5, 6, 8, 10, 12],
  '1 Corinthians': [10, 11, 12, 13, 15],
  '2 Corinthians': [5, 9, 12],
  'Galatians': [2, 5, 6],
  'Ephesians': [1, 2, 4, 5, 6],
  'Philippians': [2, 3, 4],
  'Colossians': [3],
  '1 Thessalonians': [4, 5],
  '2 Thessalonians': [2],
  '1 Timothy': [2, 3, 6],
  '2 Timothy': [2, 3, 4],
  'Titus': [2],
  'Hebrews': [4, 8, 9, 10, 11, 12, 13],
  'James': [1, 2, 4, 5],
  '1 Peter': [1, 2, 3, 5],
  '2 Peter': [1, 3],
  '1 John': [1, 2, 3, 4, 5],
  'Jude': [1],
  'Revelation': [1, 2, 3, 7, 12, 13, 14, 19, 20, 21, 22],
};

/// Well-known verses: (book name, chapter, verse), 1-based. These mark the
/// easy end of the verse templates and are the only pool "where is this
/// found?" draws from.
const List<(String, int, int)> _famous = [
  ('Genesis', 1, 1),
  ('Genesis', 1, 27),
  ('Exodus', 20, 8),
  ('Deuteronomy', 6, 5),
  ('Joshua', 1, 9),
  ('1 Samuel', 16, 7),
  ('Psalms', 23, 1),
  ('Psalms', 46, 10),
  ('Psalms', 119, 105),
  ('Proverbs', 3, 5),
  ('Ecclesiastes', 12, 13),
  ('Isaiah', 40, 31),
  ('Isaiah', 53, 5),
  ('Jeremiah', 29, 11),
  ('Daniel', 8, 14),
  ('Micah', 6, 8),
  ('Malachi', 3, 10),
  ('Matthew', 6, 33),
  ('Matthew', 11, 28),
  ('Matthew', 28, 19),
  ('Mark', 16, 15),
  ('Luke', 2, 11),
  ('John', 1, 1),
  ('John', 3, 16),
  ('John', 11, 35),
  ('John', 14, 6),
  ('Acts', 1, 8),
  ('Acts', 4, 12),
  ('Romans', 3, 23),
  ('Romans', 6, 23),
  ('Romans', 8, 28),
  ('Romans', 12, 2),
  ('1 Corinthians', 10, 31),
  ('1 Corinthians', 13, 13),
  ('2 Corinthians', 5, 17),
  ('Galatians', 2, 20),
  ('Galatians', 5, 22),
  ('Ephesians', 2, 8),
  ('Ephesians', 6, 11),
  ('Philippians', 4, 6),
  ('Philippians', 4, 13),
  ('Colossians', 3, 2),
  ('1 Thessalonians', 4, 16),
  ('2 Timothy', 3, 16),
  ('Hebrews', 4, 12),
  ('Hebrews', 11, 1),
  ('James', 1, 5),
  ('James', 4, 7),
  ('1 Peter', 5, 7),
  ('1 John', 1, 9),
  ('Revelation', 1, 7),
  ('Revelation', 14, 12),
  ('Revelation', 21, 4),
  ('Revelation', 22, 12),
];
