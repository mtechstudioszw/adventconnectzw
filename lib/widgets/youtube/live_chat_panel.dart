import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Embedded YouTube LIVE CHAT for a live stream, via the official
/// `live_chat` embed in a WebView. YouTube's embed checks `embed_domain`
/// against a real domain we control. If it can't render in-app (some
/// devices/regions block the embed), the "Open chat in YouTube" fallback
/// always works.
class LiveChatPanel extends StatefulWidget {
  const LiveChatPanel({super.key, required this.videoId});
  final String videoId;

  @override
  State<LiveChatPanel> createState() => _LiveChatPanelState();
}

class _LiveChatPanelState extends State<LiveChatPanel> {
  // A domain we own (GitHub Pages legal site) for the embed referrer.
  static const _embedDomain = 'mtechstudioszw.github.io';

  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(
        'https://www.youtube.com/live_chat'
        '?v=${widget.videoId}&embed_domain=$_embedDomain',
      ));
  }

  Future<void> _openExternal() async {
    await launchUrl(
      Uri.parse('https://www.youtube.com/watch?v=${widget.videoId}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      children: [
        Expanded(child: WebViewWidget(controller: _controller)),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.card,
            border: Border(top: BorderSide(color: palette.divider)),
          ),
          child: TextButton.icon(
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              'Chat not loading? Open in YouTube',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.primaryBlue),
            ),
          ),
        ),
      ],
    );
  }
}
