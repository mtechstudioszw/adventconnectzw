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

/// The tappable "Country" row used on the account screens (onboarding step
/// 1, Edit profile). Paints its own box on `palette.inputFill`.
///
/// For a *post* form — add product, post job, open a store, suggest a church
/// — use [CountryFormField] instead: those columns are `InputDecoration`
/// fields with a border and a blue leading icon, and this plain box reads as
/// a different kind of control next to them.
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

/// The "Country" row for the listing forms, drawn inside the caller's own
/// [decoration] so it matches the fields above and below it exactly.
///
/// Every post form builds its inputs from a local decoration helper
/// (`postFormFilledDecoration`, `_filledDecoration`, `_dec`) and they do not
/// agree — some fill with `palette.inputFill`, others with
/// `AppColors.surfaceMuted`. Rather than pick one and look wrong on three
/// screens, this takes the decoration as a parameter and renders through
/// `InputDecorator`, the same way `DropdownButtonFormField` does. Pass the
/// screen's own helper and the country row is indistinguishable from a text
/// field.
///
/// [onChanged] fires only on an actual selection — dismissing the sheet
/// leaves the current value alone, it never clears it.
class CountryFormField extends StatelessWidget {
  const CountryFormField({
    super.key,
    required this.code,
    required this.decoration,
    required this.onChanged,
    this.enabled = true,
  });

  final String? code;
  final InputDecoration decoration;
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
      child: InputDecorator(
        decoration: decoration,
        // Lets the caller's own `hintText` show through while nothing is
        // picked, exactly like the province dropdown this sits above.
        isEmpty: country == null,
        child: Row(
          children: [
            if (country != null) ...[
              Text(country.flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                // Empty rather than absent when unknown: the Text still
                // occupies its line height, so the row doesn't shrink and
                // jump when a country is chosen.
                country?.name ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              ),
            ),
            Icon(Icons.expand_more, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}
