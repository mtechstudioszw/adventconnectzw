// Home caches church events through Event.toJson. It used to drop the
// church join, so a cached official event lost its church's name and logo
// and painted as an anonymous one.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/event_model.dart';

void main() {
  test('church and organizer survive the cache round trip', () {
    final original = Event.fromJson({
      'id': 'e1',
      'title': 'Youth Sabbath',
      'start_date': '2026-11-07',
      'start_time': '09:00',
      'rsvp_count': 4,
      'church_id': 'c1',
      'churches': {
        'name': 'Harare City Central',
        'profile_photo_url': 'https://example.com/logo.png',
      },
      'profiles': {'full_name': 'Pastor Moyo'},
    });

    final cached = Event.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(cached.churchName, 'Harare City Central');
    expect(cached.churchPhotoUrl, 'https://example.com/logo.png');
    expect(cached.organizerName, 'Pastor Moyo');
    expect(cached.churchId, 'c1');
    expect(cached.eventDate, DateTime(2026, 11, 7));
  });

  test('a community event without a church writes no church join', () {
    final e = Event.fromJson({
      'id': 'e2',
      'title': 'Prayer walk',
      'start_date': '2026-11-08',
      'start_time': '06:00',
      'rsvp_count': 0,
    });
    expect(e.toJson().containsKey('churches'), isFalse);
  });
}
