// The jobs table stores salary as `salary_range` text and requirements as
// one TEXT column; the model read salary_min/max and a list, so every job
// said "Negotiable" and showed no requirements. The Sabbath-friendly / SDA
// flags and contact email were saved but never read back.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/job_model.dart';

Job _job(Map<String, Object?> extra) => Job.fromJson({
  'id': 1,
  'poster_id': 'p',
  'title': 'Teacher',
  'company': 'Solusi',
  'created_at': '2026-10-01T00:00:00Z',
  ...extra,
});

void main() {
  test('salary_range is what the card shows', () {
    expect(
      _job({'salary_range': r'$400 – $550'}).formatSalary(),
      r'$400 – $550',
    );
    expect(_job({}).formatSalary(), 'Negotiable');
  });

  test('requirements text splits into lines, bullets stripped', () {
    final j = _job({
      'requirements': '- Degree in Maths\n• 2 years teaching\n\n',
    });
    expect(j.requirements, ['Degree in Maths', '2 years teaching']);
  });

  test('flags and email are read', () {
    final j = _job({
      'sabbath_friendly': true,
      'is_sda_institution': true,
      'contact_email': 'hr@solusi.ac.zw',
    });
    expect(j.sabbathFriendly, isTrue);
    expect(j.isSdaInstitution, isTrue);
    expect(j.contactEmail, 'hr@solusi.ac.zw');
  });

  test('job types read as words, not database keys', () {
    expect(_job({'job_type': 'full_time'}).formatType(), 'Full-time');
    expect(_job({'job_type': 'part_time'}).formatType(), 'Part-time');
    expect(_job({'job_type': 'contract'}).formatType(), 'Contract');
  });

  test('the new fields survive the cache round trip and copyWith', () {
    final j = _job({
      'salary_range': r'$250',
      'sabbath_friendly': true,
      'contact_email': 'a@b.c',
    });
    final back = Job.fromJson(j.toJson()).copyWith(status: 'filled');
    expect(back.salaryRange, r'$250');
    expect(back.sabbathFriendly, isTrue);
    expect(back.contactEmail, 'a@b.c');
    expect(back.status, 'filled');
  });
}
