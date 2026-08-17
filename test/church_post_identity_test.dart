// A church update must go out as the CHURCH, not as the admin who typed it.
//
// The feed always got this right: PostCard checks `isChurchPost` and renders
// the church's name and photo. The PREVIEW did not — `showPostPreview`
// accepted churchName/churchPhotoUrl and the composer simply never passed
// them, so a church admin was shown their own name and face on the card they
// were about to publish.
//
// That is the worse way round for this bug to happen. The preview is the
// screen you check precisely because you want to know what everyone else
// will see, so it being the one that lies makes the admin trust a wrong
// answer. Pinned at the model boundary, which is where the identity is
// actually decided.
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/post_model.dart';

Post _post({String? churchName, String? churchPhotoUrl}) => Post(
      id: 'preview',
      authorId: 'admin-1',
      authorName: 'Tanatswa Michael Mikuwa',
      authorPhotoUrl: 'https://example.test/admin.jpg',
      createdAt: DateTime(2026, 8, 17),
      body: 'Divine service starts at 9am.',
      visibility: PostVisibility.public,
      churchName: churchName,
      churchPhotoUrl: churchPhotoUrl,
    );

void main() {
  test('a post carrying a church name is a church post', () {
    final p = _post(
      churchName: 'Harare City Centre SDA',
      churchPhotoUrl: 'https://example.test/church.jpg',
    );
    expect(p.isChurchPost, isTrue);
    // The card renders churchName/churchPhotoUrl for these — so carrying
    // them is the whole of "post as the church".
    expect(p.churchName, 'Harare City Centre SDA');
    expect(p.churchPhotoUrl, isNotNull);
  });

  test('a personal post is unaffected', () {
    final p = _post();
    expect(p.isChurchPost, isFalse);
    expect(p.authorName, 'Tanatswa Michael Mikuwa');
  });

  test('a blank church name does NOT make it a church post', () {
    // The preview used to pass nothing at all; an empty string arriving
    // from a half-loaded church row must degrade the same safe way rather
    // than producing a nameless church header.
    expect(_post(churchName: '').isChurchPost, isFalse);
    expect(_post(churchName: '   ').isChurchPost, isFalse);
  });

  test('a church post without a photo is still a church post', () {
    // Not every church has uploaded a logo. The name alone must still
    // rebrand the card, or an unphotographed church silently posts under
    // the admin's identity.
    final p = _post(churchName: 'Mabvuku SDA');
    expect(p.isChurchPost, isTrue);
    expect(p.churchPhotoUrl, isNull);
  });
}
