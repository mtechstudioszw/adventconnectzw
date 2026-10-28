// Listings like "Genital warts: there is hope" and "Diabetes support kit"
// went live on the marketplace. These are the founder's real examples.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/utils/medical_claims.dart';

void main() {
  test('the live examples are caught', () {
    expect(findMedicalClaims(['GENITAL WARTS KIT']), ['genital', 'warts']);
    expect(findMedicalClaims(['SUGAR DIABETES KIT']), ['diabetes']);
    expect(
      findMedicalClaims(['Kit', 'Natural support for High Blood Pressure']),
      ['high blood pressure'],
    );
    expect(findMedicalClaims(['Herbal tea that cures colds']), ['cures']);
  });

  test('ordinary listings pass', () {
    expect(
      findMedicalClaims(['Neem capsules', '60 capsules, dietary supplement']),
      isEmpty,
    );
    expect(
      findMedicalClaims(['Hearing aids', 'Teaching aids for Sabbath School']),
      isEmpty,
    );
    expect(
      findMedicalClaims(['A treat for the kids', 'Healing hymns CD']),
      isEmpty,
    );
    expect(
      findMedicalClaims(['Brush stroke art', 'Cured wood frame']),
      isEmpty,
    );
    expect(findMedicalClaims([null, '']), isEmpty);
  });

  test('words inside other words do not count', () {
    expect(findMedicalClaims(['Sticker pack', 'Securely packed']), isEmpty);
  });
}
