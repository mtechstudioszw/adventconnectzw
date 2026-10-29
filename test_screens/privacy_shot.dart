import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/messaging/chat_privacy_screen.dart';
import 'package:advent_connect_zw/services/follow_service.dart';

import 'shot.dart';

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    testWidgets('privacy ${dark ? 'dark' : 'light'}', (t) async {
      await pumpShot(
        t,
        const ChatPrivacyScreen(
          autoLoad: false,
          initialWhoCanFollow: WhoCanFollow.nobody,
        ),
        dark: dark,
        size: const Size(412, 1500),
      );
      await saveShot(t, 'privacy_${dark ? 'dark' : 'light'}');
    });
  }
}
