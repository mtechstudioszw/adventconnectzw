/// A single Bible-quiz question (patch_147 `quiz_questions`).
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.category,
    required this.difficulty,
    this.explanation,
    this.reference,
  });

  final String id;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String category;
  final String difficulty;
  final String? explanation;
  final String? reference;

  bool isCorrect(int chosen) => chosen == correctIndex;

  /// Round-trips a question through local storage.
  ///
  /// Needed because "Fix Your Mistakes" has to replay questions the player
  /// got wrong, and a generated question has no row in Supabase to look up
  /// again — so the whole thing is cached locally when it's missed. Keys
  /// match the `quiz_questions` column names so [fromJson] reads both.
  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'options': options,
        'correct_index': correctIndex,
        'category': category,
        'difficulty': difficulty,
        'explanation': explanation,
        'reference': reference,
      };

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final raw = json['options'];
    final opts = raw is List
        ? raw.map((e) => e.toString()).toList()
        : <String>[];
    return QuizQuestion(
      id: json['id'].toString(),
      question: (json['question'] ?? '').toString(),
      options: opts,
      correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
      category: (json['category'] ?? 'General').toString(),
      difficulty: (json['difficulty'] ?? 'medium').toString(),
      explanation: json['explanation'] as String?,
      reference: json['reference'] as String?,
    );
  }
}
