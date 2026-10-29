import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/follow_service.dart';
import 'package:advent_connect_zw/widgets/profile/followers_status_card.dart';

import 'shot.dart';

void main() {
  setUpAll(loadShotFonts);

  testWidgets('followers card', (t) async {
    await pumpShot(
      t,
      Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FollowersStatusCard(
                current: WhoCanFollow.nobody,
                announcement: true,
                onChanged: (_) {},
                onDismiss: () {},
              ),
              const SizedBox(height: 16),
              FollowersStatusCard(
                current: WhoCanFollow.nobody,
                onChanged: (_) {},
                onDismiss: () {},
              ),
              const SizedBox(height: 16),
              FollowersStatusCard(
                current: WhoCanFollow.everyone,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
      dark: false,
    );
    await saveShot(t, 'followers_cards');
  });
}
