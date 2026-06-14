import 'package:geolocator/geolocator.dart';

/// Approximate centre coordinates for Zimbabwe's main cities/towns.
/// Used to resolve a device GPS fix to the NEAREST city so the Churches
/// "Near me" action can show that city's churches — the church rows
/// themselves have no coordinates, so this is the best "near me" the data
/// supports. Keys match the `city` values in the churches table.
const Map<String, (double, double)> kZimbabweCities = {
  'Harare': (-17.8292, 31.0522),
  'Chitungwiza': (-18.0127, 31.0756),
  'Epworth': (-17.8833, 31.1500),
  'Ruwa': (-17.8897, 31.2456),
  'Norton': (-17.8833, 30.7000),
  'Bulawayo': (-20.1325, 28.6265),
  'Gweru': (-19.4500, 29.8167),
  'Kwekwe': (-18.9281, 29.8149),
  'Redcliff': (-19.0333, 29.7833),
  'Shurugwi': (-19.6667, 30.0000),
  'Zvishavane': (-20.3333, 30.0667),
  'Mberengwa': (-20.5000, 29.9000),
  'Gokwe': (-18.2167, 28.9333),
  'Mutare': (-18.9707, 32.6709),
  'Rusape': (-18.5275, 32.1247),
  'Headlands': (-18.2333, 32.0500),
  'Nyanga': (-18.2167, 32.7500),
  'Chipinge': (-20.1883, 32.6236),
  'Marange': (-18.9167, 32.4167),
  'Buhera': (-19.3167, 31.4333),
  'Chinhoyi': (-17.3667, 30.2000),
  'Karoi': (-16.8167, 29.6833),
  'Banket': (-17.3833, 30.4000),
  'Chegutu': (-18.1333, 30.1500),
  'Kadoma': (-18.3333, 29.9167),
  'Kariba': (-16.5167, 28.8000),
  'Mvurwi': (-17.0333, 30.8500),
  'Marondera': (-18.1853, 31.5519),
  'Chivhu': (-19.0167, 30.8833),
  'Hwedza': (-18.6167, 31.5833),
  'Wedza': (-18.6167, 31.5833),
  'Murewa': (-17.6500, 31.7833),
  'Mutoko': (-17.4167, 32.2167),
  'Bindura': (-17.3019, 31.3306),
  'Shamva': (-17.3167, 31.5667),
  'Mount Darwin': (-16.7667, 31.5833),
  'Masvingo': (-20.0637, 30.8277),
  'Chiredzi': (-21.0500, 31.6667),
  'Triangle': (-21.0333, 31.4833),
  'Beitbridge': (-22.2167, 30.0000),
  'Gwanda': (-20.9333, 29.0000),
  'Plumtree': (-20.4833, 27.8167),
  'Hwange': (-18.3647, 26.4981),
  'Victoria Falls': (-17.9244, 25.8567),
  'Lupane': (-18.9333, 27.8000),
  'Bulilima': (-20.6333, 27.7000),
};

/// Returns the name of the nearest city to [lat]/[lng] from
/// [kZimbabweCities], or null if the table is somehow empty.
String? nearestZimbabweCity(double lat, double lng) {
  String? best;
  double bestMeters = double.infinity;
  kZimbabweCities.forEach((city, coord) {
    final d = Geolocator.distanceBetween(lat, lng, coord.$1, coord.$2);
    if (d < bestMeters) {
      bestMeters = d;
      best = city;
    }
  });
  return best;
}
