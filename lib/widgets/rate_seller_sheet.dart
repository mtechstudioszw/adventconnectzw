import 'package:flutter/material.dart';

import '../services/seller_rating_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Bottom-sheet composer for rating a seller (1-5 stars + optional
/// review). Upserts via `SellerRatingService.rate` so a returning user
/// is editing their existing review rather than creating a duplicate.
class RateSellerSheet extends StatefulWidget {
  const RateSellerSheet({
    super.key,
    required this.sellerId,
    required this.sellerName,
    this.existing,
  });

  /// The `sellers.id` BIGSERIAL — *not* the seller's auth user id.
  final String sellerId;
  final String sellerName;

  /// If the signed-in user has already rated, pass it so the form
  /// pre-populates with the previous stars + review text.
  final SellerRating? existing;

  @override
  State<RateSellerSheet> createState() => _RateSellerSheetState();
}

class _RateSellerSheetState extends State<RateSellerSheet> {
  late int _stars = widget.existing?.rating ?? 0;
  late final _reviewController = TextEditingController(
    text: widget.existing?.review ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await SellerRatingService.rate(
        sellerId: widget.sellerId,
        rating: _stars,
        review: _reviewController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop<SellerRating>(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not submit. Please try again.';
      });
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SellerRatingService.deleteMine(widget.sellerId);
      if (!mounted) return;
      Navigator.of(context).pop<SellerRating?>(null);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not remove your rating.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        // Scrollable, because this sheet is taller than the space left
        // once the keyboard is up: handle + title + blurb + a 44dp star
        // row + a 3-to-6-line field + the submit button don't fit above a
        // raised keyboard on an ordinary phone, and the column had no way
        // to give.
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isEditing
                      ? 'Update your review'
                      : 'Rate ${widget.sellerName}',
                  style: AppTextStyles.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Honest reviews help other buyers and reward good sellers.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 22),
                _StarPicker(
                  value: _stars,
                  onChanged: (v) => setState(() => _stars = v),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _reviewController,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText:
                        'Optional: what stood out? Communication, quality, delivery…',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: context.palette.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.red,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _SubmitButton(
                  label: isEditing ? 'Save changes' : 'Submit review',
                  enabled: _stars > 0 && !_busy,
                  busy: _busy,
                  onTap: _submit,
                ),
                if (isEditing) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy ? null : _remove,
                    style: TextButton.styleFrom(foregroundColor: AppColors.red),
                    child: Text(
                      'Remove my review',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StarPicker extends StatelessWidget {
  const _StarPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // Five 44dp stars plus their gaps is a fixed 260dp — wider than the
    // content area on the narrowest phones once the sheet's own padding
    // is taken off. Scaling down beats clipping a star.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) {
          final star = i + 1;
          final filled = star <= value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkResponse(
              onTap: () => onChanged(star),
              radius: 28,
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: filled ? AppColors.goldAccent : AppColors.textMuted,
                size: 44,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppColors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Text(
                        label,
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 14.5,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
