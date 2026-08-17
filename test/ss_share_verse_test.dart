// Sharing a Sabbath School verse as a branded image.
//
// The founder asked for "the same for sabbath school" as the Bible
// (17 Aug): a shareable card carrying the app logo. A whole day's reading
// is far too long for a card, but the day already ships its scripture in
// `SsDayContent.bible`, and a verse is exactly the shape the card was
// built for.
//
// What is pinned here is the text conversion. The `bible` map holds HTML,
// and a shared image is seen by everyone the member sends it to — raw
// `<p>` tags or a stray `&mdash;` on a WhatsApp status is not a bug you
// get to fix quietly afterwards.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/library/widgets/ss_html_text.dart';

void main() {
  group('verse HTML becomes clean text', () {
    test('strips tags', () {
      expect(
        ssPlainText('<p>For God so loved the world.</p>'),
        'For God so loved the world.',
      );
    });

    test('decodes named entities a naive strip would leave behind', () {
      // The lesson feed uses these constantly. "&mdash;" printed literally
      // in the middle of a shared verse is the failure this guards.
      expect(ssPlainText('grace&mdash;and truth'), 'grace—and truth');
      expect(ssPlainText('Moses&#39; rod'), "Moses' rod");
      expect(ssPlainText('a&nbsp;b'), 'a b');
      expect(ssPlainText('Shadrach &amp; Meshach'), 'Shadrach & Meshach');
    });

    test('collapses the feed line-wrapping into single spaces', () {
      expect(
        ssPlainText('<p>In the\n  beginning\tGod</p>'),
        'In the beginning God',
      );
    });

    test('handles nested markup and attributes', () {
      expect(
        ssPlainText('<p class="x"><em>Trust</em> in <b>Him</b>.</p>'),
        'Trust in Him.',
      );
    });

    test('an empty or tag-only verse yields empty, not markup', () {
      // The share path checks for empty and declines rather than opening a
      // card with a blank body.
      expect(ssPlainText(''), '');
      expect(ssPlainText('<p></p>'), '');
      expect(ssPlainText('   <br/>  '), '');
    });
  });
}
