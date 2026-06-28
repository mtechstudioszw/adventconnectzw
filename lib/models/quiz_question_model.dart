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
