import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../services/bible_service.dart';
import '../../services/library_reminders.dart';
import '../../services/reading_plan_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/screen_shell.dart';
import 'library_open.dart';

AppBar _flatBar(String title) => AppBar(
  backgroundColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  title: Text(
    title,
    style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
  ),
);

BoxDecoration _card(BuildContext context) => BoxDecoration(
  color: context.palette.card,
  borderRadius: BorderRadius.circular(AppRadius.card),
  boxShadow: AppShadows.card(context),
);

/// Bible reading plans: the ones you are on, and the ones you can start.
class ReadingPlansScreen extends StatelessWidget {
  const ReadingPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _flatBar('Reading plans'),
        body: SafeArea(
          top: false,
          child: ValueListenableBuilder<int>(
            valueListenable: ReadingPlanService.revision,
            builder: (context, _, _) {
              final active = ReadingPlanService.active();
              final all = ReadingPlanService.all();
              final palette = context.palette;
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.sm,
                  AppSpace.lg,
                  AppSpace.xxl,
                ),
                children: [
                  if (active.isNotEmpty) ...[
                    _label(context, 'YOUR PLANS'),
                    for (final (plan, p) in active)
                      _PlanCard(plan: plan, progress: p),
                  ],
                  _label(
                    context,
                    active.isEmpty ? 'CHOOSE A PLAN' : 'MORE PLANS',
                  ),
                  for (final plan in ReadingPlanService.plans)
                    if (!active.any((a) => a.$1.id == plan.id))
                      _PlanCard(
                        plan: plan,
                        finished: all[plan.id]?.finished(plan.days) ?? false,
                      ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    'Plans use the Bible you read in the app. Your progress '
                    'is saved on this phone.',
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
    child: Text(
      text,
      style: AppTextStyles.overline.copyWith(
        color: context.palette.textMuted,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, this.progress, this.finished = false});
  final ReadingPlan plan;
  final PlanProgress? progress;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final p = progress;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ReadingPlanScreen(plan: plan),
            ),
          ),
          child: Ink(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: _card(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.title,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (finished)
                      Icon(
                        Icons.check_circle_rounded,
                        color: palette.brandGreen,
                        size: 20,
                      ),
                    Icon(Icons.chevron_right_rounded, color: palette.textMuted),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  p == null
                      ? '${plan.blurb} ${plan.days} days.'
                      : 'Day ${p.nextDay(plan.days) + 1} of ${plan.days}'
                            '${p.behind(plan.days) > 1 ? ' · ${p.behind(plan.days) - 1} behind' : ''}',
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                if (p != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: p.done.length / plan.days,
                      minHeight: 6,
                      backgroundColor: palette.cardMuted,
                      color: AppColors.primaryBlue,
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

/// One plan: today's chapters, the reminder and every day.
class ReadingPlanScreen extends StatefulWidget {
  const ReadingPlanScreen({super.key, required this.plan});
  final ReadingPlan plan;

  @override
  State<ReadingPlanScreen> createState() => _ReadingPlanScreenState();
}

class _ReadingPlanScreenState extends State<ReadingPlanScreen> {
  List<List<PlanChapter>>? _days;

  @override
  void initState() {
    super.initState();
    BibleService.books().then((books) {
      if (mounted) setState(() => _days = widget.plan.schedule(books));
    });
  }

  ReadingPlan get plan => widget.plan;

  void _start() {
    HapticFeedback.selectionClick();
    ReadingPlanService.start(plan.id);
    LibraryReminders.rearmReading();
  }

  void _toggle(int day, bool value) {
    HapticFeedback.selectionClick();
    ReadingPlanService.setDone(plan.id, day, value);
    LibraryReminders.rearmReading();
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Stop this plan?'),
        content: const Text('Your progress on it will be cleared.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Stop plan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ReadingPlanService.stop(plan.id);
      LibraryReminders.rearmReading();
    }
  }

  Future<void> _pickReminder() async {
    final current = LibraryReminders.readingTime() ?? (7, 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.$1, minute: current.$2),
      helpText: 'Daily reading reminder',
    );
    if (picked == null) return;
    final ok = await LibraryReminders.setReadingTime((
      picked.hour,
      picked.minute,
    ));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Allow notifications in Settings to get reminders.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _flatBar(plan.title),
        body: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              ReadingPlanService.revision,
              LibraryReminders.revision,
            ]),
            builder: (context, _) {
              final days = _days;
              if (days == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final p = ReadingPlanService.progress(plan.id);
              final children = <Widget>[];
              if (p == null) {
                children.addAll([
                  Text(
                    plan.blurb,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '${plan.days} days · about '
                    '${(days.fold<int>(0, (n, d) => n + d.length) / plan.days).toStringAsFixed(1)} '
                    'chapters a day',
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  PrimaryGradientButton(
                    label: 'Start today',
                    icon: Icons.play_arrow_rounded,
                    onTap: _start,
                  ),
                ]);
              } else {
                final today = p.nextDay(plan.days);
                final behind = p.behind(plan.days);
                final finished = p.finished(plan.days);
                children.add(
                  Container(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    decoration: _card(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          finished
                              ? 'PLAN COMPLETE'
                              : 'DAY ${today + 1} OF ${plan.days}',
                          style: AppTextStyles.overline.copyWith(
                            color: palette.brandBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        if (finished)
                          Text(
                            'You read every day of this plan. Well done!',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.text,
                            ),
                          )
                        else ...[
                          Wrap(
                            spacing: AppSpace.sm,
                            runSpacing: AppSpace.sm,
                            children: [
                              for (final c in days[today])
                                ActionChip(
                                  avatar: Icon(
                                    Icons.menu_book_rounded,
                                    size: 16,
                                    color: palette.brandBlue,
                                  ),
                                  label: Text(c.label),
                                  backgroundColor: palette.card,
                                  side: BorderSide(color: palette.divider),
                                  onPressed: () => LibraryOpen.verse(
                                    context,
                                    c.book,
                                    c.chapter,
                                  ),
                                ),
                            ],
                          ),
                          if (behind > 1) ...[
                            const SizedBox(height: AppSpace.sm),
                            Text(
                              "${behind - 1} day${behind == 2 ? '' : 's'} "
                              'behind — no rush, carry on from here.',
                              style: AppTextStyles.caption.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpace.md),
                          PrimaryGradientButton(
                            label: 'Mark day ${today + 1} as read',
                            icon: Icons.check_rounded,
                            onTap: () => _toggle(today, true),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
                final time = LibraryReminders.readingTime();
                children.add(
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.md),
                    child: Container(
                      decoration: _card(context),
                      child: SwitchListTile(
                        value: time != null,
                        onChanged: (on) => on
                            ? _pickReminder()
                            : LibraryReminders.setReadingTime(null),
                        title: Text(
                          'Daily reminder',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          time == null
                              ? 'Off'
                              : 'Every day at ${TimeOfDay(hour: time.$1, minute: time.$2).format(context)} · tap to change',
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        secondary: time == null
                            ? null
                            : IconButton(
                                tooltip: 'Change time',
                                icon: const Icon(Icons.schedule_rounded),
                                onPressed: _pickReminder,
                              ),
                      ),
                    ),
                  ),
                );
              }
              children.add(
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpace.xl,
                    bottom: AppSpace.sm,
                  ),
                  child: Text(
                    'ALL DAYS',
                    style: AppTextStyles.overline.copyWith(
                      color: palette.textMuted,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      AppSpace.sm,
                      AppSpace.lg,
                      0,
                    ),
                    sliver: SliverList.list(children: children),
                  ),
                  SliverList.builder(
                    itemCount: days.length,
                    itemBuilder: (context, i) {
                      final done = p?.done.contains(i) ?? false;
                      return CheckboxListTile(
                        value: done,
                        enabled: p != null,
                        onChanged: p == null
                            ? null
                            : (v) => _toggle(i, v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.primaryBlue,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.md,
                        ),
                        title: Text(
                          'Day ${i + 1}',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          _summary(days[i]),
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      );
                    },
                  ),
                  if (p != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        child: TextButton(
                          onPressed: _stop,
                          child: Text(
                            'Stop this plan',
                            style: TextStyle(color: palette.textMuted),
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpace.xxl),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// "Genesis 1–3" or "Genesis 50, Exodus 1–2".
  static String _summary(List<PlanChapter> day) {
    final parts = <String>[];
    var i = 0;
    while (i < day.length) {
      var j = i;
      while (j + 1 < day.length &&
          day[j + 1].book.index == day[i].book.index &&
          day[j + 1].chapter == day[j].chapter + 1) {
        j++;
      }
      final a = day[i].chapter + 1;
      final b = day[j].chapter + 1;
      parts.add('${day[i].book.name} ${a == b ? '$a' : '$a–$b'}');
      i = j + 1;
    }
    return parts.join(', ');
  }
}
