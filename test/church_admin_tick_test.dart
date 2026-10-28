// Owner, 28 Oct 2026: church admins no longer show the gold tick. The tick
// is for profiles.is_verified only (it becomes a paid badge with an ID
// check later); is_verified_admin keeps its church-admin powers.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/services/user_profile_service.dart';

Map<String, dynamic> _post(Map<String, dynamic> author) => {
  'id': 'p1',
  'author_id': 'u1',
  'body': 'hello',
  'created_at': '2026-10-28T00:00:00Z',
  'profiles': author,
};

void main() {
  test('a church admin alone gets no tick on posts', () {
    final admin = Post.fromJson(
      _post({'id': 'u1', 'full_name': 'A', 'is_verified_admin': true}),
    );
    expect(admin.authorIsVerified, isFalse);
    final verified = Post.fromJson(
      _post({'id': 'u1', 'full_name': 'A', 'is_verified': true}),
    );
    expect(verified.authorIsVerified, isTrue);
  });

  test('a church admin alone gets no tick on their profile', () {
    final p = PublicUserProfile.fromJson({
      'id': 'u1',
      'full_name': 'A',
      'is_verified_admin': true,
    });
    expect(p.isVerifiedAdmin, isTrue, reason: 'admin powers unchanged');
    expect(p.showsVerifiedTick, isFalse);
  });
}
