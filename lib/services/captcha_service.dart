import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Bot check on sign-up / sign-in / password reset (Cloudflare Turnstile).
///
/// Owner, 4 Nov 2026: CAPTCHA "for extra protection against bot accounts".
///
/// ## Off until the owner turns it on
///
/// [token] returns null — and every auth call behaves exactly as before —
/// until `app_config.captcha_site_key` holds a Turnstile site key. Then
/// each sign-in style call first gets a one-time token from a small
/// Turnstile web view and hands it to Supabase as `captchaToken`.
///
/// Turnstile is "managed": most people see a spinner for a second and
/// nothing else; only traffic Cloudflare finds suspicious gets a checkbox.
///
/// ## The order matters (docs/SECURITY_HANDOVER.md)
///
/// Switching CAPTCHA on in the SUPABASE dashboard makes Supabase REQUIRE a
/// token on every sign-up, sign-in (password, Google, Apple), reset and
/// code re-send. Any app version older than this one sends none, so its
/// users could not sign in. Only enable it in Supabase after this version
/// is live and the minimum build forces everyone onto it.
class CaptchaService {
  CaptchaService._();

  /// Set from main.dart — the sheet needs a context to appear in, and
  /// AuthService (which asks for tokens) has none.
  static GlobalKey<NavigatorState>? navigatorKey;

  static String? _siteKey;
  static String _host = 'adventconnectzw.com';
  static DateTime? _loadedAt;

  static Future<void> _load() async {
    if (_loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 10)) {
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('app_config')
          .select('key, value')
          .inFilter('key', ['captcha_site_key', 'captcha_host'])
          .timeout(const Duration(seconds: 6));
      String? key;
      for (final r in rows as List) {
        final k = r['key'] as String?;
        final v = (r['value'] as String?)?.trim() ?? '';
        if (k == 'captcha_site_key') key = v.isEmpty ? null : v;
        if (k == 'captcha_host' && v.isNotEmpty) _host = v;
      }
      _siteKey = key;
      _loadedAt = DateTime.now();
    } catch (_) {
      // Can't ask: keep whatever we knew (null = off).
    }
  }

  /// A fresh one-time token, or null when CAPTCHA is off or could not be
  /// completed (Supabase then answers with its own error, shown by
  /// [AuthService] as a normal message).
  static Future<String?> token() async {
    await _load();
    final key = _siteKey;
    final nav = navigatorKey?.currentState;
    if (key == null || nav == null || !nav.mounted) return null;
    return showModalBottomSheet<String>(
      useRootNavigator: true,
      context: nav.context,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CaptchaSheet(siteKey: key, host: _host),
    );
  }

  /// The page the web view loads. Public for the test.
  @visibleForTesting
  static String pageFor(String siteKey) => '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=go&render=explicit" async defer></script>
<style>html,body{margin:0;height:100%;background:transparent}
body{display:flex;align-items:center;justify-content:center}</style>
</head><body><div id="w"></div><script>
function go(){turnstile.render('#w',{sitekey:${jsonEncode(siteKey).replaceAll('<', r'\u003c')},
callback:function(t){Captcha.postMessage(t)},
'error-callback':function(){Captcha.postMessage('__error')},
'expired-callback':function(){Captcha.postMessage('__expired')}});}
</script></body></html>''';
}

class _CaptchaSheet extends StatefulWidget {
  const _CaptchaSheet({required this.siteKey, required this.host});

  final String siteKey;
  final String host;

  @override
  State<_CaptchaSheet> createState() => _CaptchaSheetState();
}

class _CaptchaSheetState extends State<_CaptchaSheet> {
  late final WebViewController _web;
  Timer? _timeout;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('Captcha', onMessageReceived: _onMessage)
      // The base URL must be a hostname listed on the Turnstile widget in
      // Cloudflare, or Turnstile refuses to issue a token.
      ..loadHtmlString(
        CaptchaService.pageFor(widget.siteKey),
        baseUrl: 'https://${widget.host}/',
      );
    _timeout = Timer(const Duration(seconds: 45), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _onMessage(JavaScriptMessage m) {
    if (!mounted) return;
    if (m.message == '__error' || m.message == '__expired') {
      setState(() => _problem =
          'The check didn\'t work. Check your connection and try again.');
      return;
    }
    _timeout?.cancel();
    Navigator.of(context).pop(m.message);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Quick security check', style: AppTextStyles.titleMedium),
              const SizedBox(height: 4),
              Text(
                _problem ?? 'Making sure you\'re a person, not a bot.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall
                    .copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 80,
                width: 320,
                child: WebViewWidget(controller: _web),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
