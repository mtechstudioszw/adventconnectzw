import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/message_model.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Lists every message the user has starred, across all chats. Tap a row
/// to open that conversation.
class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key});

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  bool _loading = true;
  List<Message> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await MessagingService.fetchStarredMessages();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String _preview(Message m) {
    switch (m.messageType) {
      case 'image':
        return '📷 Photo';
      case 'voice':
        return '🎙️ Voice note';
      default:
        return m.content;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkNavy,
        foregroundColor: AppColors.white,
        title: const Text('Starred messages'),
      ),
      body: _loading
          ? const Center(child: BrandSpinner(size: 30))
          : _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_border,
                      size: 56,
                      color: AppColors.goldAccent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No starred messages',
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Long-press any message and tap Star to keep it here '
                      'for quick access.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.palette.divider),
              itemBuilder: (context, i) {
                final m = _items[i];
                return ListTile(
                  leading: const Icon(Icons.star, color: AppColors.goldAccent),
                  title: Text(
                    _preview(m),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => context.pushNamed(
                    'chat',
                    pathParameters: {'id': m.conversationId},
                  ),
                );
              },
            ),
    );
  }
}
