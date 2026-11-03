/// The Seventh-day Adventist world divisions (owner, 3 Nov 2026: "put the
/// division you are from … it will also be listed in the profile").
///
/// Divisions are drawn by country, so the division is DERIVED from the
/// member's country rather than asked for — nothing extra to fill in, and
/// it can never disagree with where they said they live.
///
/// Only countries whose division is clear are listed. A country missing
/// here (several are attached directly to the General Conference, or
/// moved between divisions recently) shows no division rather than a
/// wrong one.
class SdaDivisions {
  SdaDivisions._();

  static const String ecd = 'East-Central Africa Division';
  static const String esd = 'Euro-Asia Division';
  static const String iad = 'Inter-American Division';
  static const String eud = 'Inter-European Division';
  static const String nad = 'North American Division';
  static const String nsd = 'Northern Asia-Pacific Division';
  static const String sad = 'South American Division';
  static const String spd = 'South Pacific Division';
  static const String sid = 'Southern Africa-Indian Ocean Division';
  static const String sud = 'Southern Asia Division';
  static const String ssd = 'Southern Asia-Pacific Division';
  static const String ted = 'Trans-European Division';
  static const String wad = 'West-Central Africa Division';

  static const Map<String, String> _byCountry = {
    // East-Central Africa
    'BI': ecd, 'CD': ecd, 'DJ': ecd, 'ER': ecd, 'ET': ecd, 'KE': ecd,
    'RW': ecd, 'SO': ecd, 'SS': ecd, 'TZ': ecd, 'UG': ecd,
    // Euro-Asia
    'RU': esd, 'UA': esd, 'BY': esd, 'MD': esd, 'AM': esd, 'GE': esd,
    'AZ': esd, 'KZ': esd, 'KG': esd, 'TJ': esd, 'TM': esd, 'UZ': esd,
    // Inter-American
    'MX': iad, 'BZ': iad, 'GT': iad, 'HN': iad, 'SV': iad, 'NI': iad,
    'CR': iad, 'PA': iad, 'CU': iad, 'HT': iad, 'DO': iad, 'JM': iad,
    'BS': iad, 'PR': iad, 'TT': iad, 'BB': iad, 'GP': iad, 'MQ': iad,
    'CO': iad, 'VE': iad, 'GY': iad, 'SR': iad, 'GF': iad, 'AG': iad,
    'DM': iad, 'GD': iad, 'KN': iad, 'LC': iad, 'VC': iad, 'AW': iad,
    'CW': iad, 'KY': iad, 'TC': iad, 'VG': iad, 'VI': iad,
    // Inter-European
    'AT': eud, 'BE': eud, 'BG': eud, 'CZ': eud, 'FR': eud, 'DE': eud,
    'IT': eud, 'NL': eud, 'PT': eud, 'RO': eud, 'SK': eud, 'ES': eud,
    'CH': eud, 'LU': eud, 'AD': eud, 'MC': eud, 'SM': eud,
    // North American
    'US': nad, 'CA': nad, 'BM': nad,
    // Northern Asia-Pacific
    'CN': nsd, 'HK': nsd, 'MO': nsd, 'TW': nsd, 'JP': nsd, 'MN': nsd,
    'KR': nsd, 'KP': nsd,
    // South American
    'AR': sad, 'BO': sad, 'BR': sad, 'CL': sad, 'EC': sad, 'PY': sad,
    'PE': sad, 'UY': sad,
    // South Pacific
    'AU': spd, 'NZ': spd, 'PG': spd, 'FJ': spd, 'WS': spd, 'TO': spd,
    'VU': spd, 'SB': spd, 'KI': spd, 'TV': spd, 'NR': spd, 'CK': spd,
    'NC': spd, 'PF': spd,
    // Southern Africa-Indian Ocean
    'AO': sid, 'BW': sid, 'SZ': sid, 'LS': sid, 'MG': sid, 'MW': sid,
    'MU': sid, 'MZ': sid, 'NA': sid, 'ZA': sid, 'ZM': sid, 'ZW': sid,
    'KM': sid, 'SC': sid, 'RE': sid, 'YT': sid,
    // Southern Asia
    'IN': sud, 'NP': sud, 'BT': sud,
    // Southern Asia-Pacific
    'BD': ssd, 'BN': ssd, 'KH': ssd, 'ID': ssd, 'LA': ssd, 'MY': ssd,
    'MM': ssd, 'PH': ssd, 'SG': ssd, 'LK': ssd, 'TH': ssd, 'TL': ssd,
    'VN': ssd,
    // Trans-European
    'GB': ted, 'IE': ted, 'DK': ted, 'FI': ted, 'IS': ted, 'NO': ted,
    'SE': ted, 'EE': ted, 'LV': ted, 'LT': ted, 'PL': ted, 'HU': ted,
    'HR': ted, 'RS': ted, 'SI': ted, 'BA': ted, 'ME': ted, 'MK': ted,
    'AL': ted, 'GR': ted, 'CY': ted,
    // West-Central Africa
    'BJ': wad, 'BF': wad, 'CM': wad, 'CV': wad, 'CF': wad, 'TD': wad,
    'CG': wad, 'CI': wad, 'GQ': wad, 'GA': wad, 'GM': wad, 'GH': wad,
    'GN': wad, 'GW': wad, 'LR': wad, 'ML': wad, 'MR': wad, 'NE': wad,
    'NG': wad, 'ST': wad, 'SN': wad, 'SL': wad, 'TG': wad,
  };

  /// The division for an ISO country code, or null when it isn't clear.
  static String? forCountry(String? code) {
    if (code == null || code.isEmpty) return null;
    return _byCountry[code.toUpperCase()];
  }
}
