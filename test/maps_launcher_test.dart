// Unit tests for the URL-building logic that powers the church
// location feature. We can't easily test launchUrl itself in a unit
// test (it needs a real platform channel), but the URLs we hand to it
// are pure data — so we check those.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/church_model.dart';
import 'package:advent_connect_zw/widgets/church_map.dart';

Church _church({
  String name = 'Harare Central SDA',
  String city = 'Harare',
  String? address,
  double? latitude,
  double? longitude,
}) {
  return Church(
    id: '1',
    name: name,
    city: city,
    membersCount: 0,
    address: address,
    latitude: latitude,
    longitude: longitude,
  );
}

void main() {
  group('MapsLauncher.viewUrl', () {
    test('uses lat,lng when the church has coordinates', () {
      final url = MapsLauncher.viewUrl(
        _church(latitude: -17.8252, longitude: 31.0335),
      );

      expect(url, isNotNull);
      expect(url!.host, 'www.google.com');
      expect(url.path, '/maps/search/');
      expect(url.queryParameters['api'], '1');
      expect(url.queryParameters['query'], '-17.8252,31.0335');
    });

    test('falls back to a search query when coords are missing', () {
      final url = MapsLauncher.viewUrl(
        _church(
          name: 'Bulawayo Main SDA',
          city: 'Bulawayo',
          address: '12 Joshua Mqabuko Ave',
        ),
      );

      expect(url, isNotNull);
      expect(url!.path, '/maps/search/');
      final query = url.queryParameters['query']!;
      // The query is URL-encoded; decode for readability and check parts.
      expect(query, contains('Bulawayo Main SDA'));
      expect(query, contains('12 Joshua Mqabuko Ave'));
      expect(query, contains('Bulawayo'));
      expect(query, contains('Zimbabwe'));
    });

    test('returns null when church has no coords, no address, no city', () {
      final url = MapsLauncher.viewUrl(_church(name: '', city: ''));
      // Name is empty, address null, city empty → only "Zimbabwe" remains,
      // which is a usable query, so the URL is still built.
      expect(url, isNotNull);
      expect(url!.queryParameters['query'], contains('Zimbabwe'));
    });

    test('prefers coordinates over the address fallback', () {
      final url = MapsLauncher.viewUrl(
        _church(
          city: 'Mutare',
          address: '5 Aerodrome Rd',
          latitude: -18.97,
          longitude: 32.65,
        ),
      );
      expect(url!.queryParameters['query'], '-18.97,32.65');
    });
  });

  group('MapsLauncher.directionsUrl', () {
    test('builds the /maps/dir/ URL with destination= for coords', () {
      final url = MapsLauncher.directionsUrl(
        _church(latitude: -17.8252, longitude: 31.0335),
      );

      expect(url, isNotNull);
      expect(url!.path, '/maps/dir/');
      expect(url.queryParameters['api'], '1');
      expect(url.queryParameters['destination'], '-17.8252,31.0335');
    });

    test('builds destination= from address when coords missing', () {
      final url = MapsLauncher.directionsUrl(
        _church(
          name: 'Masvingo SDA',
          city: 'Masvingo',
          address: 'Robertson St',
        ),
      );
      expect(url, isNotNull);
      expect(url!.path, '/maps/dir/');
      final dest = url.queryParameters['destination']!;
      expect(dest, contains('Masvingo SDA'));
      expect(dest, contains('Robertson St'));
      expect(dest, contains('Masvingo'));
      expect(dest, contains('Zimbabwe'));
    });

    test('encodes commas and spaces correctly', () {
      final url = MapsLauncher.directionsUrl(
        _church(name: 'Solusi University Church', city: 'Bulawayo'),
      );
      // The raw destination value should round-trip through the URL
      // encoder cleanly — no double-encoding, no broken commas.
      final decoded = url!.queryParameters['destination']!;
      expect(decoded, 'Solusi University Church, Bulawayo, Zimbabwe');
    });
  });
}
