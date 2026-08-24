import 'package:flutter/material.dart';

import '../../models/fundraiser_model.dart';
import '../../services/fundraiser_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/screen_shell.dart';

/// Super-admin queue for the iPhone fundraiser.
///
/// This screen is the ONLY thing in the app that can move the progress bar,
/// and it moves it by asking the server to — `fundraiser_confirm_contribution`
/// is `SECURITY DEFINER` and re-checks `is_super_admin()` itself, so nothing
/// here is a security boundary. Opening this screen with an ordinary account
/// shows an error and no rows; there is nothing to bypass.
///
/// ## The workflow it exists to serve
///
/// Money arrives on the EcoCash line, outside the app. A member taps "I have
/// sent my contribution", which files a PENDING row. The founder checks the
/// line, and either confirms it — in the amount that actually arrived, which
/// is not always the amount pledged — or rejects it. Only then does the total
/// on the home card change.
///
/// Mirrors NewsApprovalsScreen's structure so the two admin queues behave the
/// same way under the thumb.
class FundraiserApprovalsScreen extends StatefulWidget {
  const FundraiserApprovalsScreen({super.key});

  @override
  State<FundraiserApprovalsScreen> createState() =>
      _FundraiserApprovalsScreenState();
}

class _FundraiserApprovalsScreenState extends State<FundraiserApprovalsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pending = const [];
  final Set<int> _busyIds = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await FundraiserService.listPending();
      // Refresh the campaign too, so the header total on this screen is
      // the same number members are seeing.
      await FundraiserService.refresh(force: true);
      if (!mounted) return;
      setState(() {
        _pending = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('super admin only')
            ? 'Only super admins can review contributions.'
            : 'Could not load contributions. Pull to retry.';
      });
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          msg,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  int _idOf(Map<String, dynamic> row) =>
      int.tryParse((row['id'] ?? '').toString()) ?? -1;

  Future<void> _confirm(Map<String, dynamic> row) async {
    final id = _idOf(row);
    if (id < 0 || _busyIds.contains(id)) return;

    final pledged = int.tryParse((row['amount_cents'] ?? '').toString()) ?? 0;
    final actual = await _askAmount(pledged);
    if (actual == null) return;

    setState(() => _busyIds.add(id));
    try {
      await FundraiserService.confirmContribution(id, amountCents: actual);
      if (!mounted) return;
      setState(() => _pending.removeWhere((x) => _idOf(x) == id));
      _snack('Confirmed — the total has moved.', AppColors.successGreen);
    } catch (_) {
      if (!mounted) return;
      _snack('Could not confirm. Try again.', AppColors.red);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _reject(Map<String, dynamic> row) async {
    final id = _idOf(row);
    if (id < 0 || _busyIds.contains(id)) return;

    final note = await _askNote();
    if (note == null) return;

    setState(() => _busyIds.add(id));
    try {
      await FundraiserService.rejectContribution(id, note: note);
      if (!mounted) return;
      setState(() => _pending.removeWhere((x) => _idOf(x) == id));
      _snack('Marked as not received.', AppColors.red);
    } catch (_) {
      if (!mounted) return;
      _snack('Could not update it. Try again.', AppColors.red);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  /// Confirm in the amount that ARRIVED, pre-filled with what was pledged.
  /// The two differ often enough that assuming they match would slowly put
  /// the public total out of step with the actual balance.
  Future<int?> _askAmount(int pledgedCents) {
    final controller = TextEditingController(
      text: (pledgedCents / 100).toStringAsFixed(2),
    );
    return showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('How much actually arrived?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Only confirm what you can see on the line. This is the number '
              'that gets added to the public total.',
              style: AppTextStyles.bodySmall.copyWith(
                color: ctx.palette.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: r'$ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.successGreen),
            onPressed: () {
              final cents =
                  FundraiserCampaign.parseAmountToCents(controller.text);
              if (cents == null) return; // Keeps the dialog open.
              Navigator.pop(ctx, cents);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<String?> _askNote() {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Nothing arrived?'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 240,
          decoration: InputDecoration(
            hintText: 'Note for your own records (optional)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Not received'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const ScreenHero(
                title: 'iPhone contributions',
                tagline: 'Super admin',
                subtitle:
                    'Match what members say they sent against the EcoCash '
                    'line. Only what you confirm here counts.',
                fallbackRoute: 'admin_dashboard',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<FundraiserCampaign?>(
          valueListenable: FundraiserService.campaign,
          builder: (context, campaign, _) => campaign == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.lg),
                  child: _TotalStrip(campaign: campaign),
                ),
        ),
        if (_pending.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    size: 48,
                    color: AppColors.successGreen,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nothing waiting to be checked',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (final row in _pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PendingCard(
                row: row,
                busy: _busyIds.contains(_idOf(row)),
                onConfirm: () => _confirm(row),
                onReject: () => _reject(row),
              ),
            ),
      ],
    );
  }
}

/// The live total, so the founder can see the effect of a confirmation
/// without leaving the queue.
class _TotalStrip extends StatelessWidget {
  const _TotalStrip({required this.campaign});
  final FundraiserCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONFIRMED SO FAR',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${campaign.raisedLabel} of ${campaign.goalLabel}',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _StatusPill(state: campaign.state),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});
  final FundraiserState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      FundraiserState.active => ('Active', AppColors.primaryBlue),
      FundraiserState.paused => ('Paused', context.palette.textMuted),
      FundraiserState.completed => ('Funded', AppColors.successGreen),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.row,
    required this.busy,
    required this.onConfirm,
    required this.onReject,
  });

  final Map<String, dynamic> row;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cents = int.tryParse((row['amount_cents'] ?? '').toString()) ?? 0;
    final name = (row['full_name'] as String?)?.trim();
    final reference = (row['reference'] as String?)?.trim();
    final method = (row['method'] ?? 'ecocash').toString();

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.divider),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // Dollars, formatted here rather than through a campaign
                  // instance: the queue must render even if the campaign
                  // fetch failed.
                  cents % 100 == 0
                      ? '\$${cents ~/ 100}'
                      : '\$${(cents / 100).toStringAsFixed(2)}',
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                method == 'ecocash' ? 'EcoCash' : 'Other',
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            name == null || name.isEmpty ? 'A member' : name,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.textMuted,
            ),
          ),
          if (reference != null && reference.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: palette.cardMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                reference,
                style: AppTextStyles.bodySmall.copyWith(color: palette.text),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: BorderSide(color: palette.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: const Text('Not received'),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.successGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
