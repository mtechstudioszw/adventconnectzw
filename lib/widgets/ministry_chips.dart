import 'package:flutter/material.dart';

import '../models/ministry_tag_model.dart';
import '../services/ministry_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'motion/pressable.dart';

/// Ministry involvement + spiritual gifts, rendered as two labelled chip
/// groups (patch_168).
///
/// Shows on both profiles. On your own it carries an "+ Add" affordance
/// that opens the picker; on someone else's it is read-only and the whole
/// section disappears when they have claimed nothing — an empty "Ministry"
/// heading on a stranger's profile is just noise.
class MinistrySection extends StatelessWidget {
  const MinistrySection({
    super.key,
    required this.tags,
    required this.isOwn,
    this.onEdit,
  });

  final List<MinistryTag> tags;
  final bool isOwn;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final ministries =
        tags.where((t) => t.kind == MinistryTagKind.ministry).toList();
    final gifts = tags.where((t) => t.kind == MinistryTagKind.gift).toList();

    // Nothing to say and no way to say it → render nothing.
    if (tags.isEmpty && !isOwn) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ministries.isNotEmpty || isOwn)
          _group(
            context,
            label: MinistryTagKind.ministry.sectionLabel,
            tags: ministries,
            tint: AppColors.primaryBlue,
            // The add affordance lives on the first group only, so an
            // empty profile shows one invitation rather than two.
            showAdd: isOwn,
            emptyHint: 'Add what you serve in',
          ),
        if (gifts.isNotEmpty || isOwn) ...[
          const SizedBox(height: 14),
          _group(
            context,
            label: MinistryTagKind.gift.sectionLabel,
            tags: gifts,
            tint: AppColors.goldAccent,
            showAdd: isOwn && ministries.isNotEmpty,
            emptyHint: 'Add how you serve',
          ),
        ],
      ],
    );
  }

  Widget _group(
    BuildContext context, {
    required String label,
    required List<MinistryTag> tags,
    required Color tint,
    required bool showAdd,
    required String emptyHint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final t in tags) _Chip(label: t.label, tint: tint),
            if (tags.isEmpty && isOwn)
              _AddChip(label: emptyHint, onTap: onEdit)
            else if (showAdd)
              _AddChip(label: 'Edit', onTap: onEdit),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tint});
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelMedium.copyWith(
          color: context.palette.text,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: context.palette.textMuted.withValues(alpha: 0.5),
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 13, color: context.palette.textMuted),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Multi-select picker for ministries and gifts. Returns the chosen tag
/// ids, or null if dismissed without saving.
Future<Set<int>?> showMinistryPicker(
  BuildContext context, {
  required Set<int> selected,
}) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MinistryPickerSheet(initial: selected),
  );
}

class _MinistryPickerSheet extends StatefulWidget {
  const _MinistryPickerSheet({required this.initial});
  final Set<int> initial;

  @override
  State<_MinistryPickerSheet> createState() => _MinistryPickerSheetState();
}

class _MinistryPickerSheetState extends State<_MinistryPickerSheet> {
  late final Set<int> _selected = {...widget.initial};
  List<MinistryTag> _vocab = const [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final vocab = await MinistryService.fetchVocabulary();
      if (!mounted) return;
      setState(() {
        _vocab = vocab;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await MinistryService.saveMine(_selected);
      if (!mounted) return;
      Navigator.pop(context, _selected);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not save. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ministry & gifts',
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This is how people find someone who can help. Pick what '
                    'you serve in, and the gifts you bring.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        for (final kind in MinistryTagKind.values) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10, top: 6),
                            child: Text(
                              kind.sectionLabel.toUpperCase(),
                              style: AppTextStyles.labelSmall.copyWith(
                                color: palette.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final t
                                  in _vocab.where((t) => t.kind == kind))
                                _SelectableChip(
                                  label: t.label,
                                  selected: _selected.contains(t.id),
                                  tint: kind == MinistryTagKind.ministry
                                      ? AppColors.primaryBlue
                                      : AppColors.goldAccent,
                                  onTap: () => setState(() {
                                    if (!_selected.remove(t.id)) {
                                      _selected.add(t.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            _selected.isEmpty
                                ? 'Save'
                                : 'Save ${_selected.length}',
                            style: AppTextStyles.buttonText.copyWith(
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? tint : tint.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected ? tint : tint.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check, size: 13, color: AppColors.white),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? AppColors.white : context.palette.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
