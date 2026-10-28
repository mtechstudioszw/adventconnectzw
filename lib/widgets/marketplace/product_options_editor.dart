import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// State for the product form's "Sizes, stock & specs" section (patch_280).
///
/// Kept apart from the widget so the form can validate and save it without
/// reaching into widget state.
class ProductOptionsController extends ChangeNotifier {
  ProductOptionsController({Product? initial}) {
    if (initial == null) return;
    countStock = initial.stockQuantity != null;
    stock.text = initial.stockQuantity?.toString() ?? '';
    groups = [
      for (final g in initial.optionGroups)
        ProductOptionGroup(name: g.name, values: [...g.values]),
    ];
    specs = [
      for (final r in initial.specs)
        SpecRowDraft(
          TextEditingController(text: r.label),
          TextEditingController(text: r.value),
        ),
    ];
  }

  static const maxGroups = 2;
  static const maxValues = 12;
  static const maxCombinations = 50;
  static const maxSpecs = 20;

  bool countStock = false;
  final stock = TextEditingController();
  List<ProductOptionGroup> groups = [];
  List<SpecRowDraft> specs = [];

  /// Per-combination inputs, keyed by label ("M / Black").
  final Map<String, VariantRowDraft> _rows = {};

  /// Combinations loaded from the server when editing.
  void loadVariants(List<ProductVariant> saved) {
    for (final v in saved) {
      final row = _rowFor(v.label);
      row.stock.text = v.stock?.toString() ?? '';
      row.price.text = v.price == null ? '' : _num(v.price!);
      row.id = v.id;
    }
    if (saved.any((v) => v.stock != null)) countStock = true;
    notifyListeners();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  VariantRowDraft _rowFor(String label) =>
      _rows.putIfAbsent(label, () => VariantRowDraft());

  List<ProductVariant> get combinations => ProductVariant.combinations([
    for (final g in groups)
      if (g.values.isNotEmpty) g,
  ]);

  void setCountStock(bool v) {
    countStock = v;
    notifyListeners();
  }

  void addGroup(String name, [List<String> values = const []]) {
    if (groups.length >= maxGroups) return;
    final clean = name.trim();
    if (clean.isEmpty || groups.any((g) => g.name == clean)) return;
    groups = [
      ...groups,
      ProductOptionGroup(name: clean, values: values.take(maxValues).toList()),
    ];
    notifyListeners();
  }

  void removeGroup(int i) {
    groups = [...groups]..removeAt(i);
    notifyListeners();
  }

  void addValue(int i, String value) {
    final v = value.trim();
    final g = groups[i];
    if (v.isEmpty || g.values.contains(v) || g.values.length >= maxValues) {
      return;
    }
    _replace(i, ProductOptionGroup(name: g.name, values: [...g.values, v]));
  }

  void removeValue(int i, String value) {
    final g = groups[i];
    _replace(
      i,
      ProductOptionGroup(
        name: g.name,
        values: g.values.where((x) => x != value).toList(),
      ),
    );
  }

  void _replace(int i, ProductOptionGroup g) {
    groups = [...groups]..[i] = g;
    notifyListeners();
  }

  void addSpec([String label = '']) {
    if (specs.length >= maxSpecs) return;
    specs = [
      ...specs,
      SpecRowDraft(TextEditingController(text: label), TextEditingController()),
    ];
    notifyListeners();
  }

  void removeSpec(int i) {
    specs[i].dispose();
    specs = [...specs]..removeAt(i);
    notifyListeners();
  }

  /// A problem to show the seller, or null when it can be saved.
  String? validate() {
    final combos = combinations;
    if (combos.length > maxCombinations) {
      return 'That makes ${combos.length} combinations — the most is '
          '$maxCombinations. Remove a few sizes or colours.';
    }
    if (groups.any((g) => g.values.isEmpty)) {
      return 'Add at least one choice to each option, or remove it.';
    }
    if (countStock && combos.isEmpty) {
      final n = int.tryParse(stock.text.trim());
      if (n == null || n < 0) return 'Enter how many you have in stock.';
    }
    for (final c in combos) {
      final row = _rowFor(c.label);
      if (countStock) {
        final n = int.tryParse(row.stock.text.trim());
        if (n == null || n < 0) return 'Enter the stock for ${c.label}.';
      }
      final p = row.price.text.trim();
      if (p.isNotEmpty && (double.tryParse(p) ?? 0) <= 0) {
        return 'The price for ${c.label} must be more than 0.';
      }
    }
    return null;
  }

  int? get stockQuantity => countStock && combinations.isEmpty
      ? int.tryParse(stock.text.trim())
      : null;

  List<ProductOptionGroup> get cleanGroups => [
    for (final g in groups)
      if (g.values.isNotEmpty) g,
  ];

  List<ProductSpec> get cleanSpecs => [
    for (final r in specs)
      if (r.label.text.trim().isNotEmpty && r.value.text.trim().isNotEmpty)
        ProductSpec(label: r.label.text.trim(), value: r.value.text.trim()),
  ];

  List<ProductVariant> get variants => [
    for (final c in combinations)
      ProductVariant(
        label: c.label,
        options: c.options,
        sort: c.sort,
        stock: countStock
            ? int.tryParse(_rowFor(c.label).stock.text.trim())
            : null,
        price: double.tryParse(_rowFor(c.label).price.text.trim()),
      ),
  ];

  @override
  void dispose() {
    stock.dispose();
    for (final r in specs) {
      r.dispose();
    }
    for (final r in _rows.values) {
      r.dispose();
    }
    super.dispose();
  }
}

class VariantRowDraft {
  final stock = TextEditingController();
  final price = TextEditingController();
  String? id;
  void dispose() {
    stock.dispose();
    price.dispose();
  }
}

class SpecRowDraft {
  SpecRowDraft(this.label, this.value);
  final TextEditingController label;
  final TextEditingController value;
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

/// Quick-start option sets.
const _presets = <String, List<String>>{
  'Size': ['XS', 'S', 'M', 'L', 'XL', 'XXL'],
  'Shoe size': ['36', '37', '38', '39', '40', '41', '42', '43', '44', '45'],
  'Colour': ['Black', 'White', 'Navy', 'Grey', 'Brown', 'Blue', 'Red'],
};

/// Spec labels worth suggesting per marketplace category.
const _specSuggestions = <String, List<String>>{
  'books': ['Author', 'Version', 'Language', 'Pages', 'Cover'],
  'clothing': ['Material', 'Fit', 'Care'],
  'electronics': ['Brand', 'Model', 'Storage', 'Warranty'],
  'food': ['Weight', 'Ingredients', 'Best before'],
  'furniture': ['Material', 'Dimensions', 'Colour'],
  'services': ['Duration', 'Area covered'],
  'other': ['Brand', 'Size', 'Weight'],
};

/// The "Sizes, stock & specs" section of the product form.
class ProductOptionsEditor extends StatelessWidget {
  const ProductOptionsEditor({
    super.key,
    required this.controller,
    required this.category,
    required this.currencySymbol,
  });

  final ProductOptionsController controller;
  final String category;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context, 'Stock'),
          _StockToggle(controller: controller),
          if (controller.countStock && controller.combinations.isEmpty) ...[
            const SizedBox(height: 10),
            _field(
              context,
              controller.stock,
              'How many do you have?',
              Icons.inventory_2_outlined,
              number: true,
            ),
          ],
          const SizedBox(height: 22),
          _title(context, 'Sizes, colours & other options'),
          Text(
            'Buyers pick one before adding to the basket. Each combination '
            'can have its own stock and price.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < controller.groups.length; i++)
            _GroupEditor(controller: controller, index: i),
          if (controller.groups.length < ProductOptionsController.maxGroups)
            _AddGroupRow(controller: controller),
          if (controller.combinations.isNotEmpty) ...[
            const SizedBox(height: 16),
            _CombinationTable(
              controller: controller,
              currencySymbol: currencySymbol,
            ),
          ],
          const SizedBox(height: 22),
          _title(context, 'Specifications'),
          Text(
            'Facts buyers ask about — shown as a table on the listing.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < controller.specs.length; i++)
            _SpecEditor(controller: controller, index: i),
          _SpecSuggestions(controller: controller, category: category),
        ],
      ),
    );
  }

  static Widget _title(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: AppTextStyles.titleSmall.copyWith(
        color: context.palette.text,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

InputDecoration _decoration(
  BuildContext context,
  String hint, {
  IconData? icon,
  String? prefix,
}) {
  final palette = context.palette;
  return InputDecoration(
    hintText: hint,
    isDense: true,
    prefixText: prefix,
    prefixIcon: icon == null
        ? null
        : Icon(icon, size: 18, color: AppColors.primaryBlue),
    filled: true,
    fillColor: palette.cardMuted,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

Widget _field(
  BuildContext context,
  TextEditingController c,
  String hint,
  IconData icon, {
  bool number = false,
}) {
  return TextField(
    controller: c,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    maxLength: number ? 6 : 60,
    style: AppTextStyles.bodyMedium.copyWith(color: context.palette.text),
    decoration: _decoration(context, hint, icon: icon),
  );
}

class _StockToggle extends StatelessWidget {
  const _StockToggle({required this.controller});
  final ProductOptionsController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Count my stock',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Buyers see "Only 3 left" and can\'t order more than you '
                'have. Cancelled orders put it back.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: controller.countStock,
          onChanged: controller.setCountStock,
          activeThumbColor: AppColors.white,
          activeTrackColor: AppColors.primaryBlue,
        ),
      ],
    );
  }
}

class _GroupEditor extends StatefulWidget {
  const _GroupEditor({required this.controller, required this.index});
  final ProductOptionsController controller;
  final int index;

  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    widget.controller.addValue(widget.index, _input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final g = widget.controller.groups[widget.index];
    final preset = _presets[g.name] ?? const <String>[];
    final suggestions = preset.where((v) => !g.values.contains(v)).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  g.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove ${g.name}',
                icon: Icon(Icons.close_rounded, color: palette.textMuted),
                onPressed: () => widget.controller.removeGroup(widget.index),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in g.values)
                  InputChip(
                    label: Text(v),
                    onDeleted: () =>
                        widget.controller.removeValue(widget.index, v),
                    backgroundColor: AppColors.primaryBlue.withValues(
                      alpha: 0.10,
                    ),
                    labelStyle: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide.none,
                  ),
                for (final v in suggestions.take(8))
                  ActionChip(
                    label: Text('+ $v'),
                    onPressed: () =>
                        widget.controller.addValue(widget.index, v),
                    labelStyle: AppTextStyles.labelMedium.copyWith(
                      color: palette.textMuted,
                    ),
                    side: BorderSide(color: palette.divider),
                    backgroundColor: palette.card,
                  ),
              ],
            ),
          ),
          if (g.values.length < ProductOptionsController.maxValues) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: _input,
                maxLength: 30,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _add(),
                style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
                decoration:
                    _decoration(
                      context,
                      'Add a ${g.name.toLowerCase()}',
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip: 'Add',
                        icon: const Icon(
                          Icons.add_circle_rounded,
                          color: AppColors.primaryBlue,
                        ),
                        onPressed: _add,
                      ),
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddGroupRow extends StatelessWidget {
  const _AddGroupRow({required this.controller});
  final ProductOptionsController controller;

  Future<void> _custom(BuildContext context) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Option name'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Style, Flavour'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    c.dispose();
    if (name != null) controller.addGroup(name);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final taken = {for (final g in controller.groups) g.name};
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final name in _presets.keys)
          if (!taken.contains(name))
            ActionChip(
              avatar: const Icon(
                Icons.add_rounded,
                size: 16,
                color: AppColors.primaryBlue,
              ),
              label: Text(name),
              onPressed: () => controller.addGroup(name),
              labelStyle: AppTextStyles.labelMedium.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(color: palette.divider),
              backgroundColor: palette.card,
            ),
        ActionChip(
          avatar: const Icon(
            Icons.add_rounded,
            size: 16,
            color: AppColors.primaryBlue,
          ),
          label: const Text('Other option'),
          onPressed: () => _custom(context),
          labelStyle: AppTextStyles.labelMedium.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(color: palette.divider),
          backgroundColor: palette.card,
        ),
      ],
    );
  }
}

class _CombinationTable extends StatelessWidget {
  const _CombinationTable({
    required this.controller,
    required this.currencySymbol,
  });
  final ProductOptionsController controller;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final combos = controller.combinations;
    final head = AppTextStyles.labelSmall.copyWith(
      color: palette.textMuted,
      fontWeight: FontWeight.w600,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(flex: 4, child: Text('COMBINATION', style: head)),
            if (controller.countStock)
              Expanded(flex: 3, child: Text('IN STOCK', style: head)),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: Text('OWN PRICE', style: head)),
          ],
        ),
        const SizedBox(height: 6),
        for (final c in combos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    c.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (controller.countStock)
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: controller._rowFor(c.label).stock,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.text,
                      ),
                      decoration: _decoration(context, '0'),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: controller._rowFor(c.label).price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    maxLength: 10,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                    ),
                    decoration: _decoration(
                      context,
                      'Same',
                      prefix: currencySymbol,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (combos.length > ProductOptionsController.maxCombinations)
          Text(
            '${combos.length} combinations — the most is '
            '${ProductOptionsController.maxCombinations}.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
          ),
      ],
    );
  }
}

class _SpecEditor extends StatelessWidget {
  const _SpecEditor({required this.controller, required this.index});
  final ProductOptionsController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final r = controller.specs[index];
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: TextField(
              controller: r.label,
              maxLength: 30,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w600,
              ),
              decoration: _decoration(context, 'Label'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: TextField(
              controller: r.value,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
              decoration: _decoration(context, 'Value'),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close_rounded, color: palette.textMuted),
            onPressed: () => controller.removeSpec(index),
          ),
        ],
      ),
    );
  }
}

class _SpecSuggestions extends StatelessWidget {
  const _SpecSuggestions({required this.controller, required this.category});
  final ProductOptionsController controller;
  final String category;

  @override
  Widget build(BuildContext context) {
    if (controller.specs.length >= ProductOptionsController.maxSpecs) {
      return const SizedBox.shrink();
    }
    final palette = context.palette;
    final used = {for (final r in controller.specs) r.label.text.trim()};
    final labels = (_specSuggestions[category] ?? _specSuggestions['other']!)
        .where((l) => !used.contains(l));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final l in labels)
          ActionChip(
            label: Text('+ $l'),
            onPressed: () => controller.addSpec(l),
            labelStyle: AppTextStyles.labelMedium.copyWith(color: palette.text),
            side: BorderSide(color: palette.divider),
            backgroundColor: palette.card,
          ),
        ActionChip(
          avatar: const Icon(
            Icons.add_rounded,
            size: 16,
            color: AppColors.primaryBlue,
          ),
          label: const Text('Add specification'),
          onPressed: () => controller.addSpec(),
          labelStyle: AppTextStyles.labelMedium.copyWith(
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide.none,
          backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.08),
        ),
      ],
    );
  }
}
