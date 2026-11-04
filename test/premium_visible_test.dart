import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/utils/premium_flag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final future = DateTime.now().add(const Duration(days: 20)).toIso8601String();
  final past = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();

  test('premiumActive', () {
    expect(premiumActive(future), isTrue);
    expect(premiumActive(past), isFalse);
    expect(premiumActive(null), isFalse);
    expect(premiumActive('nonsense'), isFalse);
  });

  test('post author premium survives the cache round trip', () {
    final post = Post.fromJson({
      'id': 'p1',
      'author_id': 'a',
      'created_at': DateTime.now().toIso8601String(),
      'profiles': {'full_name': 'Ann', 'is_verified': true, 'premium_until': future},
    });
    expect(post.authorIsPremium, isTrue);
    final again = Post.fromJson(post.toJson());
    expect(again.authorIsPremium, isTrue);
    // The verified tick used to be lost from cached posts.
    expect(again.authorIsVerified, isTrue);
  });
}
