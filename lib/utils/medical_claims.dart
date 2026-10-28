/// Words that turn a wellness listing into a medical claim.
///
/// Added 28 Oct 2026 after listings like "Genital warts: there is hope" and
/// "Diabetes support kit" went live. Herbal products are welcome; claiming
/// they treat a disease is not — it can lead someone to skip real
/// treatment, and Apple (1.4.1) and Google Play remove apps that carry such
/// claims.
///
/// Deliberately a list of conditions, not of verbs: "treat", "heal" and
/// "support" appear in perfectly good listings ("a treat for the kids",
/// "healing hymns"). Words that are too common in harmless text — "aids"
/// (hearing aids), "stroke" (brush stroke), "cured" (cured meat) — are left
/// out. A determined seller can still word around this; the Report button
/// and the moderators' Hide are the backstop.
const _conditions = <String>[
  'cure',
  'cures',
  'diabetes',
  'diabetic',
  'blood sugar',
  'hypertension',
  'high blood pressure',
  'cancer',
  'tumor',
  'tumour',
  'hiv',
  'warts',
  'genital',
  'std',
  'stds',
  'sti',
  'stis',
  'herpes',
  'syphilis',
  'gonorrhea',
  'gonorrhoea',
  'covid',
  'malaria',
  'tuberculosis',
  'asthma',
  'arthritis',
  'infertility',
  'erectile',
  'impotence',
  'ulcer',
  'ulcers',
  'epilepsy',
  'hepatitis',
  'kidney disease',
  'heart disease',
  'cholesterol',
];

final _pattern = RegExp(
  r'\b(' + _conditions.map(RegExp.escape).join('|') + r')\b',
  caseSensitive: false,
);

/// The distinct condition words found in [texts], lower-cased, in the order
/// they first appear. Empty when the listing makes no medical claim.
List<String> findMedicalClaims(Iterable<String?> texts) {
  final found = <String>[];
  for (final t in texts) {
    if (t == null || t.isEmpty) continue;
    for (final m in _pattern.allMatches(t)) {
      final w = m.group(0)!.toLowerCase();
      if (!found.contains(w)) found.add(w);
    }
  }
  return found;
}
