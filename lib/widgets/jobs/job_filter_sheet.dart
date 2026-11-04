import 'package:flutter/material.dart';

import '../../models/job_model.dart';
import '../../services/job_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Jobs filters (applied in the query): start now, employment type,
/// experience, work arrangement, Sabbath-friendly, Adventist employers.
/// [hire] words it for an employer browsing people available for work.
Future<JobFilters?> showJobFilterSheet(
  BuildContext context, {
  required JobFilters current,
  bool hire = false,
}) {
  return showModalBottomSheet<JobFilters>(
      useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _JobFilterSheet(current: current, hire: hire),
  );
}

class _JobFilterSheet extends StatefulWidget {
  const _JobFilterSheet({required this.current, required this.hire});
  final JobFilters current;
  final bool hire;

  @override
  State<_JobFilterSheet> createState() => _JobFilterSheetState();
}

class _JobFilterSheetState extends State<_JobFilterSheet> {
  late bool _urgent = widget.current.urgent;
  late String? _jobType = widget.current.jobType;
  late String? _level = widget.current.level;
  late String? _arrangement = widget.current.workArrangement;
  late bool _sabbath = widget.current.sabbathFriendly;
  late bool _sda = widget.current.sdaInstitution;

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

  Widget _choices(
    Map<String?, String> options,
    String? value,
    ValueChanged<String?> onPick,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: value == e.key,
            onSelected: (_) => onPick(e.key),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    onPressed: () => Navigator.pop(context, JobFilters.none),
                    child: const Text('Reset'),
                  ),
                ],
              ),
              _label('Type'),
              _choices(
                {
                  null: 'Any',
                  for (final e in jobTypes.entries)
                    if (e.key != 'casual' || JobService.redesignAvailable)
                      e.key: e.value,
                },
                _jobType,
                (v) => setState(() => _jobType = v),
              ),
              _label(widget.hire ? 'Experience' : 'Experience needed'),
              _choices(
                {null: 'Any', for (final l in JobLevel.all) l.id: l.label},
                _level,
                (v) => setState(() => _level = v),
              ),
              // Only once the listing has that field (patch_278).
              if (JobService.redesignAvailable) ...[
                _label('Where'),
                _choices(
                  {null: 'Any', ...workArrangements},
                  _arrangement,
                  (v) => setState(() => _arrangement = v),
                ),
              ],
              const SizedBox(height: 8),
              if (JobService.redesignAvailable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.primaryBlue,
                  value: _urgent,
                  onChanged: (v) => setState(() => _urgent = v),
                  title: Text(widget.hire ? 'Available now' : 'Start now'),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.primaryBlue,
                value: _sabbath,
                onChanged: (v) => setState(() => _sabbath = v),
                title: Text(
                  widget.hire ? 'Keeps the Sabbath' : 'Sabbath-friendly hours',
                ),
              ),
              if (!widget.hire)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.primaryBlue,
                  value: _sda,
                  onChanged: (v) => setState(() => _sda = v),
                  title: const Text('Adventist institutions'),
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    JobFilters(
                      urgent: _urgent,
                      jobType: _jobType,
                      level: _level,
                      workArrangement: _arrangement,
                      sabbathFriendly: _sabbath,
                      sdaInstitution: _sda,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(widget.hire ? 'Show people' : 'Show jobs'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
