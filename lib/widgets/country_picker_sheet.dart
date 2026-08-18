import 'package:flutter/material.dart';

import '../config/countries.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// The one country picker in the app. Onboarding step 1 and Edit profile
/// both open this, so "where are you" looks and behaves identically whether
/// you are signing up or changing it later.
///
/// Returns the selected [Country], or null if the sheet was dismissed —
/// callers must treat null as "leave it as it was", never as "clear it".
Future<Country?> showCountryPicker(
  BuildContext context, {
  String? selectedCode,
}) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CountryPickerSheet(selectedCode: selectedCode),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.selectedCode});

  final String? selectedCode;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _search = TextEditingController();
  List<Country> _results = Countries.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() => _results = Countries.search(_search.text));
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolved inside build, not captured at call time — a sheet that
    // reads its colours once paints the old theme after a light/dark flip.
    final palette = context.palette;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.sheet,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Row(
                  children: [
                    Text(
                      'Select your country',
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: TextField(
                  controller: _search,
                  autofocus: false,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.text,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search countries',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: palette.textMuted,
                    ),
                    prefixIcon: Icon(Icons.search, color: palette.textMuted),
                    filled: true,
                    fillColor: palette.inputFill,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          'No country matches that.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final c = _results[i];
                          final selected = c.code == widget.selectedCode;
                          return ListTile(
                            onTap: () => Navigator.of(context).pop(c),
                            leading: Text(
                              c.flag,
                              style: const TextStyle(fontSize: 26),
                            ),
                            title: Text(
                              c.name,
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: palette.text,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              c.dialCode,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                            trailing: selected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: AppColors.primaryBlue,
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The tappable "Country" row used on forms. Mirrors the look of the
/// surrounding text fields so it doesn't read as a different kind of input.
class CountryField extends StatelessWidget {
  const CountryField({
    super.key,
    required this.code,
    required this.onChanged,
    this.enabled = true,
  });

  final String? code;
  final ValueChanged<Country> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final country = Countries.byCode(code);

    return InkWell(
      onTap: enabled
          ? () async {
              final picked = await showCountryPicker(
                context,
                selectedCode: code,
              );
              if (picked != null) onChanged(picked);
            }
          : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: palette.inputFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (country == null)
              Icon(Icons.public, size: 20, color: palette.textMuted)
            else
              Text(country.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                country?.name ?? 'Select your country',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: country == null ? palette.textMuted : palette.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.expand_more, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}
