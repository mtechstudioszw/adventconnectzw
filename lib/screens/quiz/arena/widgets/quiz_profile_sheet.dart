import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../services/quiz_match_service.dart';
import '../../../../theme/app_text_styles.dart';
import '../arena_theme.dart';

/// Creating the quiz identity.
///
/// The founder's call: a quiz profile is **optional for solo play** and
/// **required for the leaderboard and challenges**. So this is never shown
/// on the way into a solo round — only at the moment someone reaches for
/// something public, where the reason for asking is self-evident.
///
/// It defaults the name from the member's real profile, so the common case
/// is one tap.
class QuizProfileSheet extends StatefulWidget {
  const QuizProfileSheet({super.key, this.initialName});

  final String? initialName;

  /// Returns true when a profile now exists.
  static Future<bool?> show(BuildContext context, {String? initialName}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuizProfileSheet(initialName: initialName),
    );
  }

  @override
  State<QuizProfileSheet> createState() => _QuizProfileSheetState();
}

class _QuizProfileSheetState extends State<QuizProfileSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName ?? _suggestedName());
  bool _saving = false;
  String? _error;

  /// Seeded from the member's real name so the usual path is Save.
  String _suggestedName() {
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    final raw = (meta?['full_name'] ?? meta?['name'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    // First name only: a leaderboard row is short, and a full name is both
    // more than is needed and more than some members want shown.
    final first = raw.split(RegExp(r'\s+')).first;
    return first.length > 24 ? first.substring(0, 24) : first;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Use at least 2 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await QuizMatchService.saveProfile(displayName: name);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          gradient: ArenaTheme.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ArenaTheme.glassBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Pick your player name',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium.copyWith(
                  color: ArenaTheme.textOnNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This is the name other players and the leaderboard see. '
                'Solo rounds never need one.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: ArenaTheme.textMutedOnNavy,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                style: AppTextStyles.titleSmall
                    .copyWith(color: ArenaTheme.textOnNavy),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  hintText: 'Player name',
                  hintStyle: AppTextStyles.titleSmall
                      .copyWith(color: ArenaTheme.textFaintOnNavy),
                  counterStyle: AppTextStyles.bodySmall
                      .copyWith(color: ArenaTheme.textFaintOnNavy),
                  errorText: _error,
                  filled: true,
                  fillColor: ArenaTheme.glass,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: ArenaTheme.tileRadius,
                    borderSide: const BorderSide(color: ArenaTheme.glassBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: ArenaTheme.tileRadius,
                    borderSide:
                        const BorderSide(color: ArenaTheme.glassBorderActive),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: ArenaTheme.tileRadius,
                    borderSide: const BorderSide(color: ArenaTheme.glassBorder),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: ArenaTheme.actionGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextButton(
                  onPressed: _saving ? null : _save,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save and play',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
