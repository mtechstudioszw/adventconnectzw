import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../models/seller_model.dart';
import '../../services/market_ranking.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// The marketplace filter sheet: price range, condition, place and shop.
/// Returns the new filters, or null when dismissed. Applied server-side by
/// MarketplaceService.fetchCatalog.
Future<MarketFilters?> showMarketFilterSheet(
  BuildContext context, {
  required MarketFilters current,
  required List<Seller> shops,
}) {
  return showModalBottomSheet<MarketFilters>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _FilterSheet(current: current, shops: shops),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.current, required this.shops});
  final MarketFilters current;
  final List<Seller> shops;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final _min = TextEditingController(text: _fmt(widget.current.minPrice));
  late final _max = TextEditingController(text: _fmt(widget.current.maxPrice));
  late final _place = TextEditingController(text: widget.current.location);
  late String? _condition = widget.current.condition;
  late String? _sellerId = widget.current.sellerId;
  String? _error;

  static String _fmt(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : '$v');

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    _place.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', ''));
  }

  void _apply() {
    final min = _num(_min);
    final max = _num(_max);
    if ((_min.text.trim().isNotEmpty && min == null) ||
        (_max.text.trim().isNotEmpty && max == null)) {
      setState(() => _error = 'Prices must be numbers.');
      return;
    }
    if (min != null && max != null && min > max) {
      setState(() => _error = 'The lowest price is above the highest.');
      return;
    }
    final seller = widget.shops.where((s) => s.authUserId == _sellerId);
    Navigator.pop(
      context,
      MarketFilters(
        minPrice: min,
        maxPrice: max,
        condition: _condition,
        location: _place.text.trim().isEmpty ? null : _place.text.trim(),
        sellerId: _sellerId,
        sellerName: seller.isEmpty ? null : seller.first.businessName,
        sort: widget.current.sort,
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      t,
      style: AppTextStyles.labelLarge.copyWith(
        color: context.palette.text,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + inset),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filters',
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      MarketFilters(sort: widget.current.sort),
                    ),
                    child: const Text('Reset'),
                  ),
                ],
              ),
              _label('Price'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _min,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Lowest',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _max,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Highest',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              _label('Condition'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Any'),
                    selected: _condition == null,
                    onSelected: (_) => setState(() => _condition = null),
                  ),
                  for (final e in Product.conditionLabels.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _condition == e.key,
                      onSelected: (_) => setState(() => _condition = e.key),
                    ),
                ],
              ),
              _label('Town or province'),
              TextField(
                controller: _place,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. Harare',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.shops.isNotEmpty) ...[
                _label('Shop'),
                DropdownButtonFormField<String?>(
                  initialValue: _sellerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Any shop'),
                    ),
                    for (final s in widget.shops)
                      DropdownMenuItem(
                        value: s.authUserId,
                        child: Text(
                          s.businessName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _sellerId = v),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.red,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Show results'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
