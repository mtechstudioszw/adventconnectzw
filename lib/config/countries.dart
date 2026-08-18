import 'dart:ui' show PlatformDispatcher;

/// The country table behind the app's global positioning.
///
/// **Codes, not names.** Every country is stored on `profiles.country` (and
/// on churches / events / jobs / products / sellers) as its ISO 3166-1
/// alpha-2 code — `ZW`, `KE`, `US`. Codes are stable when a display name
/// changes, they sort and index cheaply, and they translate: the name here
/// is only ever what we render, never what we compare.
///
/// **No flag assets.** [Country.flag] derives the emoji from the code by
/// mapping each letter to its Unicode regional-indicator symbol, so adding a
/// country costs one row and zero image files.
///
/// **[lat] / [lng] are populated centroids, not geometric ones** — they sit
/// on the country's main population centre, because the only thing that
/// reads them is the Sabbath sundown calculation. A geometric centroid puts
/// Canada in the Arctic and gives a sundown time nobody in Toronto
/// recognises. See `SabbathService`.
class Country {
  const Country(this.code, this.name, this.dialCode, this.lat, this.lng);

  /// ISO 3166-1 alpha-2, uppercase. The value stored in the database.
  final String code;
  final String name;

  /// E.164 prefix including the `+`. Used to turn a locally-typed number
  /// ("0778 092 494") into something `wa.me` will actually open.
  final String dialCode;

  final double lat;
  final double lng;

  /// The flag as an emoji, derived from [code]. 'ZW' → 🇿🇼.
  ///
  /// Regional indicator symbols live at U+1F1E6..U+1F1FF, in the same order
  /// as A..Z, so the code points are just the letters offset into that
  /// block. Returns an empty string for anything that isn't two A–Z
  /// letters, so a bad code renders as nothing rather than tofu.
  String get flag {
    if (code.length != 2) return '';
    const base = 0x1F1E6;
    final a = code.codeUnitAt(0);
    final b = code.codeUnitAt(1);
    if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return '';
    return String.fromCharCodes([base + (a - 0x41), base + (b - 0x41)]);
  }

  /// "🇿🇼  Zimbabwe" — the standard way this app renders a country.
  String get labelWithFlag => '$flag  $name';

  @override
  String toString() => '$code ($name)';
}

/// Lookup helpers over [Countries.all].
abstract final class Countries {
  /// The app's home country and the value every pre-rebrand profile is
  /// backfilled to. Also the fallback whenever detection fails — the entire
  /// existing user base is Zimbabwean, so guessing ZW is right far more
  /// often than guessing nothing.
  static const String defaultCode = 'ZW';

  static Country get fallback => byCode(defaultCode)!;

  static final Map<String, Country> _byCode = {
    for (final c in all) c.code: c,
  };

  /// Case-insensitive lookup. Null for an unknown code, so callers can
  /// decide between falling back and showing nothing.
  static Country? byCode(String? code) {
    if (code == null || code.isEmpty) return null;
    return _byCode[code.toUpperCase()];
  }

  /// The display name for a stored code, or the raw code if we don't know
  /// it. Never returns null — this is for rendering, and a profile that
  /// somehow holds a bad code should still show *something*.
  static String nameOf(String? code) => byCode(code)?.name ?? (code ?? '');

  static String flagOf(String? code) => byCode(code)?.flag ?? '';

  /// Substring match on name or code, for the country picker's search box.
  static List<Country> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return [
      for (final c in all)
        if (c.name.toLowerCase().contains(q) || c.code.toLowerCase() == q) c,
    ];
  }

  /// The ISO 4217 currency a seller in [code] would price in, or null when
  /// we do not know.
  ///
  /// **Null, never a guess.** Defaulting an unknown country to USD would
  /// put the wrong currency on a real listing and a buyer would act on it;
  /// the picker shows USD alone in that case, which is at least honest. Add
  /// a row here rather than inventing one at the call site.
  ///
  /// Africa is covered thoroughly because that is where the members are;
  /// the rest is the diaspora destinations that actually appear. A country
  /// missing from this map is a one-line fix, not a redesign.
  static String? currencyOf(String? code) =>
      code == null ? null : _currencyByCode[code.toUpperCase()];

  static const Map<String, String> _currencyByCode = {
    // --- Africa ---------------------------------------------------------
    'AO': 'AOA', 'BF': 'XOF', 'BI': 'BIF', 'BJ': 'XOF', 'BW': 'BWP',
    'CD': 'CDF', 'CF': 'XAF', 'CG': 'XAF', 'CI': 'XOF', 'CM': 'XAF',
    'CV': 'CVE', 'DJ': 'DJF', 'DZ': 'DZD', 'EG': 'EGP', 'ER': 'ERN',
    'ET': 'ETB', 'GA': 'XAF', 'GH': 'GHS', 'GM': 'GMD', 'GN': 'GNF',
    'GQ': 'XAF', 'GW': 'XOF', 'KE': 'KES', 'KM': 'KMF', 'LR': 'LRD',
    'LS': 'LSL', 'LY': 'LYD', 'MA': 'MAD', 'MG': 'MGA', 'ML': 'XOF',
    'MR': 'MRU', 'MU': 'MUR', 'MW': 'MWK', 'MZ': 'MZN', 'NA': 'NAD',
    'NE': 'XOF', 'NG': 'NGN', 'RW': 'RWF', 'SC': 'SCR', 'SD': 'SDG',
    'SL': 'SLE', 'SN': 'XOF', 'SO': 'SOS', 'SS': 'SSP', 'ST': 'STN',
    'SZ': 'SZL', 'TD': 'XAF', 'TG': 'XOF', 'TN': 'TND', 'TZ': 'TZS',
    'UG': 'UGX', 'ZA': 'ZAR', 'ZM': 'ZMW',
    // Zimbabwe is USD-first in practice; ZWL and ZAR are added alongside
    // it by the marketplace form, which is the only place it matters.
    'ZW': 'USD',
    // --- Diaspora -------------------------------------------------------
    'AE': 'AED', 'AR': 'ARS', 'AT': 'EUR', 'AU': 'AUD', 'BB': 'BBD',
    'BD': 'BDT', 'BE': 'EUR', 'BG': 'BGN', 'BH': 'BHD', 'BR': 'BRL',
    'CA': 'CAD', 'CH': 'CHF', 'CL': 'CLP', 'CN': 'CNY', 'CO': 'COP',
    'CY': 'EUR', 'CZ': 'CZK', 'DE': 'EUR', 'DK': 'DKK', 'EE': 'EUR',
    'ES': 'EUR', 'FI': 'EUR', 'FR': 'EUR', 'GB': 'GBP', 'GR': 'EUR',
    'GY': 'GYD', 'HK': 'HKD', 'HU': 'HUF', 'ID': 'IDR', 'IE': 'EUR',
    'IL': 'ILS', 'IN': 'INR', 'IT': 'EUR', 'JM': 'JMD', 'JP': 'JPY',
    'KR': 'KRW', 'KW': 'KWD', 'LK': 'LKR', 'LT': 'EUR', 'LU': 'EUR',
    'LV': 'EUR', 'MT': 'EUR', 'MX': 'MXN', 'MY': 'MYR', 'NL': 'EUR',
    'NO': 'NOK', 'NZ': 'NZD', 'OM': 'OMR', 'PE': 'PEN', 'PH': 'PHP',
    'PK': 'PKR', 'PL': 'PLN', 'PT': 'EUR', 'QA': 'QAR', 'RO': 'RON',
    'RU': 'RUB', 'SA': 'SAR', 'SE': 'SEK', 'SG': 'SGD', 'SI': 'EUR',
    'SK': 'EUR', 'TH': 'THB', 'TR': 'TRY', 'TT': 'TTD', 'TW': 'TWD',
    'UA': 'UAH', 'US': 'USD', 'VN': 'VND',
  };

  /// The currency codes the marketplace should offer a seller in [code],
  /// best first.
  ///
  /// USD is always present and always last-resort: it is what the whole
  /// existing catalogue is priced in, it is what Zimbabwe actually trades
  /// in, and a diaspora buyer understands it. The local currency leads
  /// where we know it.
  ///
  /// Zimbabwe additionally keeps ZWL and ZAR — the three the form has
  /// always offered, and the two neighbours' currencies people genuinely
  /// quote in. Nowhere else inherits those; a Kenyan seller has no use for
  /// a ZWL option and it only invites a mis-tap.
  static List<String> currencyChoices(String? code) {
    final iso = (code ?? '').toUpperCase();
    if (iso == defaultCode) return const ['USD', 'ZWL', 'ZAR'];
    final local = currencyOf(iso);
    return <String>[
      if (local != null && local != 'USD') local,
      'USD',
    ];
  }

  /// A locally-typed phone number as the digits `wa.me` needs, or null if
  /// there is nothing usable in [raw].
  ///
  /// Every WhatsApp handoff in the app used to do `raw.replaceAll(RegExp(
  /// r'\D'), '')` and hand the result straight to `wa.me`. That silently
  /// required every seller to type a full international number: someone who
  /// wrote their number the way they say it out loud — `0778 092 494` —
  /// produced `wa.me/0778092494`, which opens an error page. It was never a
  /// Zimbabwe-only bug, but it becomes a worse one now that sellers outside
  /// Zimbabwe exist, because there is no single code left to assume.
  ///
  /// [countryCode] is the ISO-2 of whoever owns the number — the seller's
  /// country, not the viewer's. Omit it and national-format numbers are
  /// passed through untouched rather than guessed at: a wrong country code
  /// dials a stranger, which is worse than a link that does not open.
  ///
  /// Handles, in order:
  ///  * `+263 77 …` / `00263 77 …` — already international, kept as-is.
  ///  * `0778 …` with a known country — trunk `0` dropped, dial code added.
  ///  * `263778 …` — already starts with the dial code, left alone.
  ///  * anything else with a known country — dial code prefixed.
  static String? toWhatsAppDigits(String raw, {String? countryCode}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // `00` is the other way of writing `+`, and plenty of people do.
    final isInternational =
        trimmed.startsWith('+') || trimmed.startsWith('00');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    if (isInternational) {
      // Drop the `00` prefix; a leading `+` left no digits behind anyway.
      final out = trimmed.startsWith('00') ? digits.substring(2) : digits;
      return out.isEmpty ? null : out;
    }

    final dial = byCode(countryCode)?.dialCode.replaceAll(RegExp(r'\D'), '');
    // No country to reason with: hand back exactly what the old code did,
    // so this can never make an already-working number worse.
    if (dial == null || dial.isEmpty) return digits;

    if (digits.startsWith('0')) {
      final national = digits.replaceFirst(RegExp(r'^0+'), '');
      return national.isEmpty ? null : '$dial$national';
    }
    if (digits.startsWith(dial)) return digits;
    return '$dial$digits';
  }

  /// The placeholder to show in a "phone number" field for [countryCode] —
  /// `+254 77 123 4567` for Kenya, not the hard-coded `+263` every one of
  /// these fields used to display regardless of who was typing.
  static String phoneHint(String? countryCode) {
    final dial = byCode(countryCode)?.dialCode ?? fallback.dialCode;
    return '$dial 77 123 4567';
  }

  /// Best guess at the user's country from the device locale, used to
  /// pre-select the picker during onboarding so most people just tap
  /// Continue.
  ///
  /// Deliberately NOT geolocation: asking for the location permission
  /// mid-signup costs completions, and the locale is free and already
  /// correct for the overwhelming majority. The user can always change it.
  static Country detect() {
    for (final locale in PlatformDispatcher.instance.locales) {
      final match = byCode(locale.countryCode);
      if (match != null) return match;
    }
    return fallback;
  }

  /// Every country, pre-sorted by name so the picker never has to sort.
  static const List<Country> all = <Country>[
    Country('AF', 'Afghanistan', '+93', 34.53, 69.17),
    Country('AL', 'Albania', '+355', 41.33, 19.82),
    Country('DZ', 'Algeria', '+213', 36.75, 3.06),
    Country('AD', 'Andorra', '+376', 42.51, 1.52),
    Country('AO', 'Angola', '+244', -8.84, 13.23),
    Country('AG', 'Antigua and Barbuda', '+1268', 17.12, -61.85),
    Country('AR', 'Argentina', '+54', -34.60, -58.38),
    Country('AM', 'Armenia', '+374', 40.18, 44.51),
    Country('AW', 'Aruba', '+297', 12.52, -70.04),
    Country('AU', 'Australia', '+61', -33.87, 151.21),
    Country('AT', 'Austria', '+43', 48.21, 16.37),
    Country('AZ', 'Azerbaijan', '+994', 40.41, 49.87),
    Country('BS', 'Bahamas', '+1242', 25.05, -77.35),
    Country('BH', 'Bahrain', '+973', 26.23, 50.59),
    Country('BD', 'Bangladesh', '+880', 23.81, 90.41),
    Country('BB', 'Barbados', '+1246', 13.11, -59.61),
    Country('BY', 'Belarus', '+375', 53.90, 27.57),
    Country('BE', 'Belgium', '+32', 50.85, 4.35),
    Country('BZ', 'Belize', '+501', 17.50, -88.20),
    Country('BJ', 'Benin', '+229', 6.37, 2.39),
    Country('BM', 'Bermuda', '+1441', 32.29, -64.78),
    Country('BT', 'Bhutan', '+975', 27.47, 89.64),
    Country('BO', 'Bolivia', '+591', -16.49, -68.15),
    Country('BA', 'Bosnia and Herzegovina', '+387', 43.86, 18.41),
    Country('BW', 'Botswana', '+267', -24.63, 25.91),
    Country('BR', 'Brazil', '+55', -23.55, -46.63),
    Country('BN', 'Brunei', '+673', 4.89, 114.94),
    Country('BG', 'Bulgaria', '+359', 42.70, 23.32),
    Country('BF', 'Burkina Faso', '+226', 12.37, -1.52),
    Country('BI', 'Burundi', '+257', -3.36, 29.36),
    Country('KH', 'Cambodia', '+855', 11.56, 104.92),
    Country('CM', 'Cameroon', '+237', 3.85, 11.50),
    Country('CA', 'Canada', '+1', 43.65, -79.38),
    Country('CV', 'Cape Verde', '+238', 14.93, -23.51),
    Country('KY', 'Cayman Islands', '+1345', 19.29, -81.38),
    Country('CF', 'Central African Republic', '+236', 4.39, 18.56),
    Country('TD', 'Chad', '+235', 12.13, 15.06),
    Country('CL', 'Chile', '+56', -33.45, -70.67),
    Country('CN', 'China', '+86', 31.23, 121.47),
    Country('CO', 'Colombia', '+57', 4.71, -74.07),
    Country('KM', 'Comoros', '+269', -11.70, 43.26),
    Country('CG', 'Congo (Brazzaville)', '+242', -4.26, 15.24),
    Country('CD', 'Congo (Kinshasa)', '+243', -4.44, 15.27),
    Country('CR', 'Costa Rica', '+506', 9.93, -84.09),
    Country('CI', "Côte d'Ivoire", '+225', 5.36, -4.01),
    Country('HR', 'Croatia', '+385', 45.81, 15.98),
    Country('CU', 'Cuba', '+53', 23.11, -82.37),
    Country('CW', 'Curaçao', '+599', 12.17, -68.99),
    Country('CY', 'Cyprus', '+357', 35.19, 33.38),
    Country('CZ', 'Czechia', '+420', 50.08, 14.44),
    Country('DK', 'Denmark', '+45', 55.68, 12.57),
    Country('DJ', 'Djibouti', '+253', 11.59, 43.15),
    Country('DM', 'Dominica', '+1767', 15.30, -61.39),
    Country('DO', 'Dominican Republic', '+1809', 18.49, -69.93),
    Country('EC', 'Ecuador', '+593', -0.18, -78.47),
    Country('EG', 'Egypt', '+20', 30.04, 31.24),
    Country('SV', 'El Salvador', '+503', 13.69, -89.22),
    Country('GQ', 'Equatorial Guinea', '+240', 3.75, 8.78),
    Country('ER', 'Eritrea', '+291', 15.34, 38.93),
    Country('EE', 'Estonia', '+372', 59.44, 24.75),
    Country('SZ', 'Eswatini', '+268', -26.32, 31.14),
    Country('ET', 'Ethiopia', '+251', 9.03, 38.74),
    Country('FJ', 'Fiji', '+679', -18.14, 178.44),
    Country('FI', 'Finland', '+358', 60.17, 24.94),
    Country('FR', 'France', '+33', 48.86, 2.35),
    Country('PF', 'French Polynesia', '+689', -17.54, -149.57),
    Country('GA', 'Gabon', '+241', 0.42, 9.47),
    Country('GM', 'Gambia', '+220', 13.45, -16.58),
    Country('GE', 'Georgia', '+995', 41.72, 44.83),
    Country('DE', 'Germany', '+49', 52.52, 13.40),
    Country('GH', 'Ghana', '+233', 5.60, -0.19),
    Country('GR', 'Greece', '+30', 37.98, 23.73),
    Country('GD', 'Grenada', '+1473', 12.06, -61.75),
    Country('GP', 'Guadeloupe', '+590', 16.24, -61.53),
    Country('GU', 'Guam', '+1671', 13.44, 144.79),
    Country('GT', 'Guatemala', '+502', 14.63, -90.51),
    Country('GN', 'Guinea', '+224', 9.64, -13.58),
    Country('GW', 'Guinea-Bissau', '+245', 11.86, -15.60),
    Country('GY', 'Guyana', '+592', 6.80, -58.16),
    Country('HT', 'Haiti', '+509', 18.59, -72.31),
    Country('HN', 'Honduras', '+504', 14.07, -87.19),
    Country('HK', 'Hong Kong', '+852', 22.32, 114.17),
    Country('HU', 'Hungary', '+36', 47.50, 19.04),
    Country('IS', 'Iceland', '+354', 64.15, -21.94),
    Country('IN', 'India', '+91', 19.08, 72.88),
    Country('ID', 'Indonesia', '+62', -6.21, 106.85),
    Country('IR', 'Iran', '+98', 35.69, 51.39),
    Country('IQ', 'Iraq', '+964', 33.31, 44.36),
    Country('IE', 'Ireland', '+353', 53.35, -6.26),
    Country('IL', 'Israel', '+972', 31.77, 35.21),
    Country('IT', 'Italy', '+39', 41.90, 12.50),
    Country('JM', 'Jamaica', '+1876', 17.97, -76.79),
    Country('JP', 'Japan', '+81', 35.68, 139.69),
    Country('JO', 'Jordan', '+962', 31.96, 35.94),
    Country('KZ', 'Kazakhstan', '+7', 43.24, 76.89),
    Country('KE', 'Kenya', '+254', -1.29, 36.82),
    Country('KI', 'Kiribati', '+686', 1.33, 172.98),
    Country('KW', 'Kuwait', '+965', 29.38, 47.99),
    Country('KG', 'Kyrgyzstan', '+996', 42.87, 74.59),
    Country('LA', 'Laos', '+856', 17.98, 102.63),
    Country('LV', 'Latvia', '+371', 56.95, 24.11),
    Country('LB', 'Lebanon', '+961', 33.89, 35.50),
    Country('LS', 'Lesotho', '+266', -29.31, 27.48),
    Country('LR', 'Liberia', '+231', 6.30, -10.80),
    Country('LY', 'Libya', '+218', 32.89, 13.19),
    Country('LT', 'Lithuania', '+370', 54.69, 25.28),
    Country('LU', 'Luxembourg', '+352', 49.61, 6.13),
    Country('MO', 'Macao', '+853', 22.20, 113.54),
    Country('MG', 'Madagascar', '+261', -18.88, 47.51),
    Country('MW', 'Malawi', '+265', -13.96, 33.79),
    Country('MY', 'Malaysia', '+60', 3.14, 101.69),
    Country('MV', 'Maldives', '+960', 4.18, 73.51),
    Country('ML', 'Mali', '+223', 12.64, -8.00),
    Country('MT', 'Malta', '+356', 35.90, 14.51),
    Country('MH', 'Marshall Islands', '+692', 7.09, 171.38),
    Country('MQ', 'Martinique', '+596', 14.62, -61.07),
    Country('MR', 'Mauritania', '+222', 18.08, -15.98),
    Country('MU', 'Mauritius', '+230', -20.16, 57.50),
    Country('MX', 'Mexico', '+52', 19.43, -99.13),
    Country('FM', 'Micronesia', '+691', 6.92, 158.16),
    Country('MD', 'Moldova', '+373', 47.01, 28.86),
    Country('MN', 'Mongolia', '+976', 47.89, 106.91),
    Country('ME', 'Montenegro', '+382', 42.44, 19.26),
    Country('MA', 'Morocco', '+212', 33.57, -7.59),
    Country('MZ', 'Mozambique', '+258', -25.97, 32.57),
    Country('MM', 'Myanmar', '+95', 16.87, 96.20),
    Country('NA', 'Namibia', '+264', -22.56, 17.08),
    Country('NP', 'Nepal', '+977', 27.72, 85.32),
    Country('NL', 'Netherlands', '+31', 52.37, 4.90),
    Country('NC', 'New Caledonia', '+687', -22.28, 166.46),
    Country('NZ', 'New Zealand', '+64', -36.85, 174.76),
    Country('NI', 'Nicaragua', '+505', 12.11, -86.24),
    Country('NE', 'Niger', '+227', 13.51, 2.11),
    Country('NG', 'Nigeria', '+234', 6.52, 3.38),
    Country('MK', 'North Macedonia', '+389', 41.998, 21.43),
    Country('NO', 'Norway', '+47', 59.91, 10.75),
    Country('OM', 'Oman', '+968', 23.59, 58.41),
    Country('PK', 'Pakistan', '+92', 24.86, 67.00),
    Country('PW', 'Palau', '+680', 7.50, 134.62),
    Country('PS', 'Palestine', '+970', 31.90, 35.20),
    Country('PA', 'Panama', '+507', 8.98, -79.52),
    Country('PG', 'Papua New Guinea', '+675', -9.44, 147.18),
    Country('PY', 'Paraguay', '+595', -25.26, -57.58),
    Country('PE', 'Peru', '+51', -12.05, -77.04),
    Country('PH', 'Philippines', '+63', 14.60, 120.98),
    Country('PL', 'Poland', '+48', 52.23, 21.01),
    Country('PT', 'Portugal', '+351', 38.72, -9.14),
    Country('PR', 'Puerto Rico', '+1787', 18.47, -66.11),
    Country('QA', 'Qatar', '+974', 25.29, 51.53),
    Country('RE', 'Réunion', '+262', -20.88, 55.45),
    Country('RO', 'Romania', '+40', 44.43, 26.10),
    Country('RU', 'Russia', '+7', 55.76, 37.62),
    Country('RW', 'Rwanda', '+250', -1.95, 30.06),
    Country('WS', 'Samoa', '+685', -13.83, -171.77),
    Country('ST', 'São Tomé and Príncipe', '+239', 0.34, 6.73),
    Country('SA', 'Saudi Arabia', '+966', 24.71, 46.68),
    Country('SN', 'Senegal', '+221', 14.72, -17.47),
    Country('RS', 'Serbia', '+381', 44.79, 20.45),
    Country('SC', 'Seychelles', '+248', -4.62, 55.45),
    Country('SL', 'Sierra Leone', '+232', 8.48, -13.23),
    Country('SG', 'Singapore', '+65', 1.35, 103.82),
    Country('SK', 'Slovakia', '+421', 48.15, 17.11),
    Country('SI', 'Slovenia', '+386', 46.06, 14.51),
    Country('SB', 'Solomon Islands', '+677', -9.43, 159.95),
    Country('SO', 'Somalia', '+252', 2.05, 45.32),
    Country('ZA', 'South Africa', '+27', -26.20, 28.05),
    Country('KR', 'South Korea', '+82', 37.57, 126.98),
    Country('SS', 'South Sudan', '+211', 4.85, 31.58),
    Country('ES', 'Spain', '+34', 40.42, -3.70),
    Country('LK', 'Sri Lanka', '+94', 6.93, 79.86),
    Country('KN', 'St Kitts and Nevis', '+1869', 17.30, -62.72),
    Country('LC', 'St Lucia', '+1758', 14.01, -60.99),
    Country('VC', 'St Vincent and the Grenadines', '+1784', 13.16, -61.22),
    Country('SD', 'Sudan', '+249', 15.50, 32.56),
    Country('SR', 'Suriname', '+597', 5.85, -55.20),
    Country('SE', 'Sweden', '+46', 59.33, 18.07),
    Country('CH', 'Switzerland', '+41', 47.38, 8.54),
    Country('SY', 'Syria', '+963', 33.51, 36.28),
    Country('TW', 'Taiwan', '+886', 25.03, 121.57),
    Country('TJ', 'Tajikistan', '+992', 38.56, 68.79),
    Country('TZ', 'Tanzania', '+255', -6.79, 39.21),
    Country('TH', 'Thailand', '+66', 13.76, 100.50),
    Country('TL', 'Timor-Leste', '+670', -8.56, 125.56),
    Country('TG', 'Togo', '+228', 6.17, 1.23),
    Country('TO', 'Tonga', '+676', -21.14, -175.20),
    Country('TT', 'Trinidad and Tobago', '+1868', 10.65, -61.51),
    Country('TN', 'Tunisia', '+216', 36.81, 10.18),
    Country('TR', 'Türkiye', '+90', 41.01, 28.98),
    Country('TM', 'Turkmenistan', '+993', 37.96, 58.33),
    Country('UG', 'Uganda', '+256', 0.35, 32.58),
    Country('UA', 'Ukraine', '+380', 50.45, 30.52),
    Country('AE', 'United Arab Emirates', '+971', 25.20, 55.27),
    Country('GB', 'United Kingdom', '+44', 51.51, -0.13),
    Country('US', 'United States', '+1', 40.71, -74.01),
    Country('UY', 'Uruguay', '+598', -34.90, -56.16),
    Country('UZ', 'Uzbekistan', '+998', 41.30, 69.24),
    Country('VU', 'Vanuatu', '+678', -17.73, 168.32),
    Country('VE', 'Venezuela', '+58', 10.48, -66.90),
    Country('VN', 'Vietnam', '+84', 21.03, 105.85),
    Country('YE', 'Yemen', '+967', 15.37, 44.19),
    Country('ZM', 'Zambia', '+260', -15.39, 28.32),
    Country('ZW', 'Zimbabwe', '+263', -17.83, 31.05),
  ];
}
