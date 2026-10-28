import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/countries.dart';
import '../../models/job_model.dart';
import '../../models/org_page_model.dart';
import '../../services/ads/interstitial_ad_manager.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/job_service.dart';
import '../../services/page_service.dart';
import '../../services/post_limit_error.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/country_picker_sheet.dart';
import '../../widgets/job_card.dart';
import '../../widgets/pages/page_tile.dart';
import '../widgets/post_form_widgets.dart';

/// Post or edit a job — a stepped flow (redesign, 28 Oct 2026, brief §15):
///
///   1. Hiring or looking for work
///   2. The role — title, employer (optionally the poster's own Page),
///      field
///   3. Type, experience, arrangement, where
///   4. The detail — description, requirements, pay, Sabbath / Adventist
///   5. How to apply
///   6. Review, then submit → "Waiting for review"
///
/// New posts keep a local draft as they go (user-scoped key, so sign-out
/// clears it — CLAUDE.md). Edits don't: the job itself is the record.
class PostJobScreen extends StatefulWidget {
  const PostJobScreen({
    super.key,
    this.existing,
    this.initialPostType,
    this.initialCategory,
    this.initialRole,
  });

  /// When non-null, the flow edits [existing] and saves with
  /// JobService.updateJob.
  final Job? existing;

  /// 'hiring' or 'seeking' — preselected from the Jobs empty state.
  final String? initialPostType;

  /// A role template picked on the Jobs screen ("Gardener" under
  /// domestic_caregiving) — the flow opens with it filled in.
  final String? initialCategory;
  final String? initialRole;

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  static const draftKey = 'job_post_draft_v1';
  static const _steps = [
    'Listing',
    'The role',
    'Where & how',
    'Details',
    'How to apply',
    'Review',
  ];

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _companyController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _requirementsController = TextEditingController();
  final _salaryController = TextEditingController();
  final _payMinController = TextEditingController();
  final _payMaxController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _applyUrlController = TextEditingController();
  final _applyInstructionsController = TextEditingController();

  /// Free-text region for non-ZW postings. Shares the `province` column
  /// with [_province]; see [_regionValue].
  final _regionController = TextEditingController();

  int _step = 0;
  String _payPeriod = 'month';
  String _payCurrency = 'USD';
  bool _urgent = false;
  JobKind _templateKind = JobKind.everyday;

  /// patch_278 has run: casual work, the new fields, structured pay and
  /// "Start now" are offered. Before it, the form is what it was.
  bool _redesign = JobService.redesignAvailable;
  String _category = 'other';
  String _jobType = 'full_time';
  String _postType = 'hiring';
  String _level = 'mid';
  String? _arrangement;
  String? _pageId;
  List<OrgPage> _myPages = const [];

  /// ISO 3166-1 alpha-2. Seeded from the job being edited, else the
  /// poster's own profile.
  String? _country;
  String? _province;
  bool _sabbathFriendly = false;
  bool _isSdaInstitution = false;
  bool _saving = false;
  bool _draftRestored = false;
  bool _submitted = false;
  String? _error;

  static const _provinces = [
    'Harare',
    'Bulawayo',
    'Manicaland',
    'Mashonaland Central',
    'Mashonaland East',
    'Mashonaland West',
    'Masvingo',
    'Matabeleland North',
    'Matabeleland South',
    'Midlands',
  ];

  bool get _isEdit => widget.existing != null;
  bool get _hiring => _postType == 'hiring';

  List<TextEditingController> get _controllers => [
    _titleController,
    _companyController,
    _descriptionController,
    _requirementsController,
    _salaryController,
    _payMinController,
    _payMaxController,
    _locationController,
    _phoneController,
    _emailController,
    _applyUrlController,
    _applyInstructionsController,
    _regionController,
  ];

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _titleController.text = ex.title;
      _companyController.text = ex.company;
      _descriptionController.text = ex.description ?? '';
      _requirementsController.text = ex.requirements.join('\n');
      // Salary, the two flags and the email were never pre-filled, so
      // saving an edit wiped them.
      _salaryController.text =
          ex.salaryRange ??
          (ex.salaryMin != null || ex.salaryMax != null
              ? ex.formatSalary()
              : '');
      _locationController.text = ex.location ?? '';
      _phoneController.text = ex.contactPhone ?? '';
      _emailController.text = ex.contactEmail ?? '';
      _applyUrlController.text = ex.applyUrl ?? '';
      _applyInstructionsController.text = ex.applyInstructions ?? '';
      _sabbathFriendly = ex.sabbathFriendly;
      _isSdaInstitution = ex.isSdaInstitution;
      _category = JobCategory.byId(ex.category)?.id ?? 'other';
      _jobType = ex.type ?? 'full_time';
      _postType = ex.postType;
      _level = ex.level;
      _arrangement = ex.workArrangement;
      _pageId = ex.pageId;
      _urgent = ex.isUrgent;
      _payPeriod = ex.payPeriod ?? 'month';
      _payCurrency = ex.payCurrency ?? 'USD';
      if (ex.payMin != null || ex.payMax != null) {
        _payMinController.text = _num(ex.payMin ?? ex.payMax);
        if (ex.payMax != null && ex.payMax != ex.payMin) {
          _payMaxController.text = _num(ex.payMax);
        }
      } else {
        _seedPayFromText(ex.salaryRange);
      }
      // Edits open on the role; the listing kind rarely changes.
      _step = 1;
    } else {
      if (widget.initialPostType == 'seeking') _postType = 'seeking';
      _restoreDraft();
      final cat = JobCategory.byId(widget.initialCategory);
      final role = cat?.roles
          .where((r) => r.title == widget.initialRole)
          .firstOrNull;
      if (cat != null && role != null && !_draftRestored) {
        _applyRole(cat, role);
        _step = 1;
      }
    }
    // Country first, then the province/region hanging off it.
    _country ??= ex?.country ?? AuthService.currentCountry();
    if (ex != null) {
      if (_isZimbabwe) {
        _province = ex.province;
      } else {
        _regionController.text = ex.province ?? '';
      }
    }
    final local = Countries.currencyOf(_country);
    if (ex == null && !_draftRestored && local != null) {
      // USD leads where it's what people are paid in (ZW); else local.
      _payCurrency = Countries.currencyChoices(_country).first;
    }
    _loadPages();
    JobService.probeRedesign().then((ok) {
      if (mounted && ok != _redesign) setState(() => _redesign = ok);
    });
  }

  static String _num(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  /// An older job's free-text pay ("\$400 – \$550 / month") pre-fills the
  /// amount boxes when the numbers are clear; otherwise it stays as typed.
  void _seedPayFromText(String? text) {
    final t = (text ?? '').toLowerCase();
    final nums = RegExp(r'\d[\d,]*(?:\.\d+)?')
        .allMatches(t)
        .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '')))
        .whereType<double>()
        .toList();
    if (nums.isEmpty || nums.length > 2) return;
    _payMinController.text = _num(nums.first);
    if (nums.length == 2) _payMaxController.text = _num(nums.last);
    for (final e in payPeriods.keys) {
      if (t.contains(e)) _payPeriod = e;
    }
    if (t.contains('/ hr') || t.contains('/hr')) _payPeriod = 'hour';
  }

  /// Fills the form from a role template. Never overwrites what the poster
  /// already wrote.
  void _applyRole(JobCategory cat, JobRole role) {
    _category = cat.id;
    _titleController.text = role.title;
    _jobType = role.type == 'casual' && !_redesign ? 'contract' : role.type;
    _level = role.level;
    _payPeriod = role.period;
    if (_descriptionController.text.trim().isEmpty &&
        role.description.isNotEmpty) {
      _descriptionController.text = _hiring
          ? role.description
          : 'I am looking for work as a ${role.title.toLowerCase()}. ';
    }
    if (_requirementsController.text.trim().isEmpty &&
        role.requirements.isNotEmpty &&
        _hiring) {
      _requirementsController.text = role.requirements;
    }
  }

  double? _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', ''));

  double? get _payMin => _parse(_payMinController);
  double? get _payMax => _parse(_payMaxController) ?? _payMin;
  bool get _hasPay => _payMin != null;

  /// What the pay reads as — also written to salary_range so older app
  /// versions still show it.
  String? get _payText => _redesign
      ? (_hasPay
            ? Job.formatPay(
                min: _payMin,
                max: _payMax,
                period: _payPeriod,
                currency: _payCurrency,
              )
            : null)
      : _orNull(_salaryController);

  Future<void> _loadPages() async {
    try {
      final pages = await PageService.mine();
      if (mounted) setState(() => _myPages = pages);
    } catch (_) {}
  }

  // Draft ---------------------------------------------------------------------

  Map<String, dynamic> _draftJson() => {
    'step': _step,
    'post_type': _postType,
    'category': _category,
    'job_type': _jobType,
    'level': _level,
    'arrangement': _arrangement,
    'page_id': _pageId,
    'country': _country,
    'province': _province,
    'sabbath': _sabbathFriendly,
    'sda': _isSdaInstitution,
    'title': _titleController.text,
    'company': _companyController.text,
    'description': _descriptionController.text,
    'requirements': _requirementsController.text,
    'salary': _salaryController.text,
    'pay_min': _payMinController.text,
    'pay_max': _payMaxController.text,
    'pay_period': _payPeriod,
    'pay_currency': _payCurrency,
    'urgent': _urgent,
    'location': _locationController.text,
    'phone': _phoneController.text,
    'email': _emailController.text,
    'apply_url': _applyUrlController.text,
    'apply_instructions': _applyInstructionsController.text,
    'region': _regionController.text,
  };

  void _restoreDraft() {
    try {
      final raw = CacheService.readStringStale(draftKey);
      if (raw == null) return;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      if ((d['title'] as String? ?? '').trim().isEmpty &&
          (d['description'] as String? ?? '').trim().isEmpty) {
        return;
      }
      String t(String k) => d[k] as String? ?? '';
      _postType = d['post_type'] == 'seeking' ? 'seeking' : 'hiring';
      _category = JobCategory.byId(d['category'] as String?)?.id ?? 'other';
      _jobType = jobTypes.containsKey(d['job_type'])
          ? d['job_type'] as String
          : 'full_time';
      _level = d['level'] as String? ?? 'mid';
      _arrangement = workArrangements.containsKey(d['arrangement'])
          ? d['arrangement'] as String
          : null;
      _pageId = d['page_id'] as String?;
      _country = d['country'] as String?;
      _province = d['province'] as String?;
      _sabbathFriendly = d['sabbath'] == true;
      _isSdaInstitution = d['sda'] == true;
      _titleController.text = t('title');
      _companyController.text = t('company');
      _descriptionController.text = t('description');
      _requirementsController.text = t('requirements');
      _salaryController.text = t('salary');
      _payMinController.text = t('pay_min');
      _payMaxController.text = t('pay_max');
      _payPeriod = payPeriods.containsKey(d['pay_period'])
          ? d['pay_period'] as String
          : 'month';
      _payCurrency = d['pay_currency'] as String? ?? 'USD';
      _urgent = d['urgent'] == true;
      _locationController.text = t('location');
      _phoneController.text = t('phone');
      _emailController.text = t('email');
      _applyUrlController.text = t('apply_url');
      _applyInstructionsController.text = t('apply_instructions');
      _regionController.text = t('region');
      _step = ((d['step'] as num?)?.toInt() ?? 0).clamp(0, _steps.length - 1);
      _draftRestored = true;
    } catch (_) {}
  }

  Future<void> _saveDraft() async {
    if (_isEdit || _submitted) return;
    try {
      // No `pref:` prefix on purpose: sign-out clears it, so the next
      // person on a shared phone doesn't inherit a half-written listing.
      await CacheService.writeString(draftKey, jsonEncode(_draftJson()));
    } catch (_) {}
  }

  Future<void> _discardDraft() async {
    try {
      await CacheService.invalidate(draftKey);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      for (final c in _controllers) {
        c.clear();
      }
      _step = 0;
      _postType = 'hiring';
      _category = 'other';
      _jobType = 'full_time';
      _level = 'mid';
      _arrangement = null;
      _pageId = null;
      _province = null;
      _country = AuthService.currentCountry();
      _sabbathFriendly = false;
      _isSdaInstitution = false;
      _urgent = false;
      _payPeriod = 'month';
      _draftRestored = false;
    });
  }

  /// Zimbabwe is the one country with a real province list in this app.
  bool get _isZimbabwe => _country == 'ZW';

  String? get _regionValue {
    if (_isZimbabwe) return _province;
    final typed = _regionController.text.trim();
    return typed.isEmpty ? null : typed;
  }

  void _onCountryPicked(Country picked) {
    setState(() {
      _country = picked.code;
      _province = null;
      _regionController.clear();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  // Navigation ----------------------------------------------------------------

  String? _stepProblem() {
    switch (_step) {
      case 2:
        if (_isZimbabwe && _province == null) return 'Select a province.';
      case 3:
        if (_redesign) {
          final min = _parse(_payMinController);
          final max = _parse(_payMaxController);
          final minText = _payMinController.text.trim();
          if (minText.isNotEmpty && min == null) {
            return 'Enter pay as a number.';
          }
          if (_payMaxController.text.trim().isNotEmpty && max == null) {
            return 'Enter the top of the range as a number.';
          }
          if (min == null && max != null) return 'Add the starting amount.';
          if (min != null && max != null && max < min) {
            return 'The top of the range is lower than the start.';
          }
        }
      case 4:
        final any = [
          _phoneController,
          _emailController,
          _applyUrlController,
        ].any((c) => c.text.trim().isNotEmpty);
        if (_hiring && !any) {
          return 'Add at least one way to apply — a phone number, an email '
              'or an application link.';
        }
    }
    return null;
  }

  void _next() {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final problem = _stepProblem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step++);
    _saveDraft();
  }

  void _back() {
    if (_step == 0 || (_isEdit && _step == 1)) {
      context.pop();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step--;
    });
  }

  String? _orNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final ex = widget.existing;
      if (ex == null) {
        await JobService.postJob(
          title: _titleController.text,
          description: _descriptionController.text,
          category: _category,
          country: _country,
          province: _regionValue,
          location: _locationController.text,
          company: _orNull(_companyController),
          requirements: _orNull(_requirementsController),
          jobType: _jobType,
          postType: _postType,
          level: _level,
          salaryRange: _payText,
          payMin: _redesign && _hasPay ? _payMin : null,
          payMax: _redesign && _hasPay ? _payMax : null,
          payPeriod: _redesign && _hasPay ? _payPeriod : null,
          payCurrency: _redesign && _hasPay ? _payCurrency : null,
          isUrgent: _redesign && _urgent,
          sabbathFriendly: _sabbathFriendly,
          isSdaInstitution: _isSdaInstitution,
          contactPhone: _orNull(_phoneController),
          contactEmail: _orNull(_emailController),
          workArrangement: _arrangement,
          applyInstructions: _orNull(_applyInstructionsController),
          applyUrl: _hiring ? _orNull(_applyUrlController) : null,
          pageId: _hiring ? _pageId : null,
        );
        try {
          await CacheService.invalidate(draftKey);
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _saving = false;
          _submitted = true;
        });
        unawaited(InterstitialAdManager.maybeShow());
        return;
      }
      await JobService.updateJob(
        jobId: ex.id,
        title: _titleController.text,
        company: _companyController.text,
        description: _descriptionController.text,
        requirements: _requirementsController.text,
        category: _category,
        jobType: _jobType,
        postType: _postType,
        level: _level,
        salaryRange: _payText ?? '',
        payMin: _hasPay ? _payMin : null,
        payMax: _hasPay ? _payMax : null,
        payPeriod: _redesign ? (_hasPay ? _payPeriod : '') : null,
        payCurrency: _hasPay ? _payCurrency : null,
        isUrgent: _redesign ? _urgent : null,
        country: _country,
        province: _regionValue,
        location: _locationController.text,
        sabbathFriendly: _sabbathFriendly,
        isSdaInstitution: _isSdaInstitution,
        contactPhone: _phoneController.text,
        contactEmail: _emailController.text,
        workArrangement: _arrangement,
        applyInstructions: _applyInstructionsController.text,
        applyUrl: _hiring ? _applyUrlController.text : '',
        pageId: _hiring ? (_pageId ?? '') : '',
      );
      if (!mounted) return;
      // Honest about what the server does: changing who's hiring, how to
      // reach them or the pay sends a live job back for review (patch_278).
      final wasOpen = ex.status == 'open';
      final identityChanged =
          ex.title != _titleController.text.trim() ||
          ex.company != _companyController.text.trim() ||
          (ex.contactPhone ?? '') != _phoneController.text.trim() ||
          (ex.contactEmail ?? '') != _emailController.text.trim() ||
          (ex.applyUrl ?? '') != _applyUrlController.text.trim() ||
          (ex.payLabel ?? '') != (_payText ?? '') ||
          ex.pageId != _pageId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasOpen && identityChanged && JobService.redesignAvailable
                ? 'Saved. Because the employer, contact or pay changed, '
                      'it goes back for a quick review.'
                : 'Job updated.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = PostLimitError.messageFor(
            e,
            fallback: _isEdit
                ? 'Could not save changes. Please try again.'
                : 'Could not post the job. Please try again.',
          );
        });
      }
    }
  }

  // Build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildSubmitted();
    final palette = context.palette;
    final last = _step == _steps.length - 1;
    return PopScope(
      canPop: _step == 0 || (_isEdit && _step == 1),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              _buildProgress(),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      if (_draftRestored && _step < _steps.length - 1)
                        _DraftBanner(onDiscard: _discardDraft),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0.04, 0),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: _buildStep(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        PostFormErrorBanner(message: _error!),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                decoration: BoxDecoration(
                  color: palette.scaffoldBg,
                  border: Border(top: BorderSide(color: palette.divider)),
                ),
                child: last
                    ? PostFormSaveButton(
                        label: _isEdit
                            ? 'Save changes'
                            : _hiring
                            ? 'Submit vacancy'
                            : 'Submit listing',
                        busy: _saving,
                        onTap: _saving ? null : _submit,
                      )
                    : SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _step == _steps.length - 2 ? 'Review' : 'Continue',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                            ),
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

  Widget _buildTopBar() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: _back,
            icon: Icon(
              _step == 0 || (_isEdit && _step == 1)
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
              color: palette.text,
            ),
          ),
          Expanded(
            child: Text(
              _isEdit ? 'Edit job' : 'Post a job',
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'Step ${_step + 1} of ${_steps.length}',
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? AppColors.primaryBlue
                          : palette.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _steps[_step],
            style: AppTextStyles.headlineSmall.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
    0 => _buildKindStep(),
    1 => _buildRoleStep(),
    2 => _buildWhereStep(),
    3 => _buildDetailStep(),
    4 => _buildApplyStep(),
    _ => _buildReviewStep(),
  };

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: AppTextStyles.bodyMedium.copyWith(
        color: context.palette.textMuted,
        height: 1.45,
      ),
    ),
  );

  Widget _buildKindStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hint(
          'Listings are checked by a moderator before they go live, and '
          'stay up for 30 days.',
        ),
        _KindCard(
          icon: Icons.business_center_outlined,
          title: "I'm hiring",
          subtitle: 'Advertise a vacancy, contract or volunteer role.',
          selected: _hiring,
          onTap: () => setState(() => _postType = 'hiring'),
        ),
        const SizedBox(height: 12),
        _KindCard(
          icon: Icons.person_search_outlined,
          title: "I'm looking for work",
          subtitle: 'Tell employers what you do and how to reach you.',
          selected: !_hiring,
          onTap: () => setState(() => _postType = 'seeking'),
        ),
        if (!_isEdit) ..._buildTemplates(),
      ],
    );
  }

  /// "Start from a common role" — one tap fills the title, field, type and
  /// a first draft, then moves on. Covers a gardener as well as a doctor.
  List<Widget> _buildTemplates() {
    final palette = context.palette;
    final cats = [
      for (final c in JobCategory.ofKind(_templateKind))
        if (c.roles.isNotEmpty && (_redesign || !c.needsPatch)) c,
    ];
    return [
      const SizedBox(height: 26),
      Text(
        _hiring ? 'Start from a common role' : 'What work do you do?',
        style: AppTextStyles.titleMedium.copyWith(
          color: palette.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Tap one and we fill in the basics — you can change anything.',
        style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final k in JobKind.values) ...[
            if (k != JobKind.everyday) const SizedBox(width: 8),
            Expanded(
              child: _choice(
                label: switch (k) {
                  JobKind.everyday => 'Everyday',
                  JobKind.skilled => 'Skilled',
                  JobKind.professional => 'Professional',
                },
                selected: _templateKind == k,
                onTap: () => setState(() => _templateKind = k),
                expand: true,
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 14),
      for (final c in cats) ...[
        Row(
          children: [
            Icon(c.icon, size: 16, color: AppColors.primaryBlue),
            const SizedBox(width: 6),
            Text(
              c.label,
              style: AppTextStyles.labelLarge.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in c.roles)
              ActionChip(
                label: Text(r.title),
                onPressed: () {
                  setState(() {
                    _applyRole(c, r);
                    _step = 1;
                  });
                  _saveDraft();
                },
                labelStyle: AppTextStyles.labelMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: palette.card,
                side: BorderSide(color: palette.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  Widget _buildRoleStep() {
    return PostFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PostFormLabeledField(
            label: _hiring ? 'Job title' : 'The work you do',
            child: TextFormField(
              controller: _titleController,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Title is required';
                if (v.trim().length < 3) return 'Title is too short';
                return null;
              },
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.work_outline,
                hint: _hiring
                    ? 'e.g. Mathematics Teacher'
                    : 'e.g. Electrician, bookkeeper, tutor',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: _hiring ? 'Employer' : 'Your business (optional)',
            child: TextFormField(
              controller: _companyController,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              validator: (v) => _hiring && (v == null || v.trim().isEmpty)
                  ? 'Who is hiring?'
                  : null,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.business_outlined,
                hint: 'e.g. Solusi Adventist High School',
              ),
            ),
          ),
          if (_hiring && _myPages.isNotEmpty && JobService.redesignAvailable)
            ..._buildPagePicker(),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Field',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final k in JobKind.values) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      k.label,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in [
                        ...JobCategory.ofKind(k),
                        if (k == JobKind.professional)
                          JobCategory.byId('other')!,
                      ])
                        if (_redesign || !c.needsPatch || _category == c.id)
                          _choice(
                            label: c.label,
                            icon: c.icon,
                            selected: _category == c.id,
                            onTap: () => setState(() => _category = c.id),
                          ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPagePicker() {
    final palette = context.palette;
    return [
      const SizedBox(height: 6),
      Text(
        'Post as one of your Pages',
        style: AppTextStyles.labelLarge.copyWith(
          color: palette.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Applicants see the Page as the employer — and its verified tick, '
        'if it has one.',
        style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
      ),
      const SizedBox(height: 10),
      for (final p in _myPages)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: _pageId == p.id
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : palette.cardMuted,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() {
                if (_pageId == p.id) {
                  _pageId = null;
                } else {
                  _pageId = p.id;
                  _companyController.text = p.name;
                }
              }),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    PageLogo(page: p, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (p.isVerified)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: AppColors.goldAccent,
                        ),
                      ),
                    Icon(
                      _pageId == p.id
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: _pageId == p.id
                          ? AppColors.primaryBlue
                          : palette.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    bool expand = false,
  }) {
    final palette = context.palette;
    if (expand) {
      return Material(
        color: selected
            ? AppColors.primaryBlue.withValues(alpha: 0.12)
            : palette.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : palette.divider,
              ),
            ),
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: selected ? AppColors.primaryBlue : palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }
    return ChoiceChip(
      avatar: icon == null
          ? null
          : Icon(
              icon,
              size: 16,
              color: selected ? AppColors.primaryBlue : palette.textMuted,
            ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryBlue.withValues(alpha: 0.14),
      labelStyle: AppTextStyles.labelMedium.copyWith(
        color: selected ? AppColors.primaryBlue : palette.text,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.primaryBlue : palette.divider,
        ),
      ),
    );
  }

  Widget _buildWhereStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PostFormCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PostFormLabeledField(
                label: 'Type',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in jobTypes.entries)
                      if (e.key != 'casual' || _redesign || _jobType == e.key)
                        _choice(
                          label: e.value,
                          selected: _jobType == e.key,
                          onTap: () => setState(() => _jobType = e.key),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              PostFormLabeledField(
                label: _hiring ? 'Experience needed' : 'Your experience',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final l in JobLevel.all)
                          _choice(
                            label: l.label,
                            selected: _level == l.id,
                            onTap: () => setState(() => _level = l.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      JobLevel.byId(_level).helper,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                        height: 1.4,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (JobService.redesignAvailable) ...[
                const SizedBox(height: 18),
                PostFormLabeledField(
                  label: 'Where the work happens',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in workArrangements.entries)
                        _choice(
                          label: e.value,
                          selected: _arrangement == e.key,
                          onTap: () => setState(
                            () => _arrangement = _arrangement == e.key
                                ? null
                                : e.key,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_redesign) ...[
          const SizedBox(height: 16),
          PostFormCard(
            child: _ToggleRow(
              icon: Icons.bolt_rounded,
              iconColor: AppColors.red,
              iconBg: AppColors.red.withValues(alpha: 0.10),
              title: _hiring ? 'Start now' : 'Available now',
              subtitle: _hiring
                  ? 'You need someone urgently. Shown in the "Start now" row.'
                  : 'You can start straight away.',
              value: _urgent,
              onChanged: (v) => setState(() => _urgent = v),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildLocationCard(),
      ],
    );
  }

  Widget _buildLocationCard() {
    return PostFormCard(
      child: Column(
        children: [
          PostFormLabeledField(
            label: 'Country',
            child: CountryFormField(
              code: _country,
              decoration: postFormFilledDecoration(
                icon: Icons.public,
                hint: 'Choose a country',
              ),
              onChanged: _onCountryPicked,
            ),
          ),
          const SizedBox(height: 18),
          // Province is a Zimbabwean administrative unit — offer the list
          // only where it means something, free text everywhere else.
          if (_isZimbabwe)
            PostFormLabeledField(
              label: 'Province',
              child: _Dropdown<String?>(
                icon: Icons.map_outlined,
                hint: 'Choose a province',
                value: _province,
                items: [
                  for (final p in _provinces)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() => _province = v),
              ),
            )
          else
            PostFormLabeledField(
              label: 'State or region (optional)',
              child: TextFormField(
                controller: _regionController,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                decoration: postFormFilledDecoration(
                  icon: Icons.map_outlined,
                  hint: 'e.g. Nairobi County',
                ),
              ),
            ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Town or city',
            child: TextFormField(
              controller: _locationController,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Location required';
                return null;
              },
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.location_on_outlined,
                hint: 'e.g. Harare, Nairobi, London',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PostFormCard(
          child: Column(
            children: [
              PostFormLabeledField(
                label: _hiring ? 'About the role' : 'About you',
                child: TextFormField(
                  controller: _descriptionController,
                  maxLength: 4000,
                  minLines: 5,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Description is required';
                    }
                    if (v.trim().length < 20) return 'Tell people a bit more';
                    return null;
                  },
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                  decoration: postFormFilledDecoration(
                    icon: Icons.notes_outlined,
                    hint: _hiring
                        ? 'Day-to-day responsibilities and who you need'
                        : 'What you do, where you have worked, what you want',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PostFormLabeledField(
                label: _hiring ? 'Requirements' : 'Skills & qualifications',
                child: TextFormField(
                  controller: _requirementsController,
                  maxLength: 2000,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                  decoration: postFormFilledDecoration(
                    icon: Icons.checklist,
                    hint: 'One per line',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PostFormLabeledField(
                label: _hiring ? 'Pay (optional)' : 'Rate you ask (optional)',
                child: _redesign
                    ? _buildPayFields()
                    : TextFormField(
                        controller: _salaryController,
                        maxLength: 60,
                        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                        decoration: postFormFilledDecoration(
                          icon: Icons.payments_outlined,
                          hint: 'e.g. USD 600–900 / month',
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PostFormCard(
          child: Column(
            children: [
              _ToggleRow(
                icon: Icons.brightness_2_outlined,
                iconColor: AppColors.goldAccent,
                iconBg: AppColors.goldAccent.withValues(alpha: 0.12),
                title: 'Sabbath-friendly',
                subtitle: _hiring
                    ? 'No work from Friday sundown to Saturday sundown.'
                    : 'You keep the Sabbath free.',
                value: _sabbathFriendly,
                onChanged: (v) => setState(() => _sabbathFriendly = v),
              ),
              if (_hiring) ...[
                const SizedBox(height: 14),
                _ToggleRow(
                  icon: Icons.church_outlined,
                  iconColor: AppColors.primaryBlue,
                  iconBg: AppColors.primaryBlue.withValues(alpha: 0.10),
                  title: 'Adventist institution',
                  subtitle: 'School, hospital or office of the SDA church.',
                  value: _isSdaInstitution,
                  onChanged: (v) => setState(() => _isSdaInstitution = v),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Amount (or a range), the period and the currency — so a day's work
  /// reads "\$15 / day" and a salary "\$900–1,200 / month".
  Widget _buildPayFields() {
    final palette = context.palette;
    final currencies = {
      ...Countries.currencyChoices(_country),
      _payCurrency,
    }.toList();
    InputDecoration dec(String hint) => postFormFilledDecoration(
      icon: Icons.payments_outlined,
      hint: hint,
    ).copyWith(counterText: '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _payMinController,
                maxLength: 12,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                decoration: dec('Amount'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('–', style: TextStyle(color: palette.textMuted)),
            ),
            Expanded(
              child: TextFormField(
                controller: _payMaxController,
                maxLength: 12,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                decoration: dec('Up to (optional)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in payPeriods.entries)
              _choice(
                label: e.value.label,
                selected: _payPeriod == e.key,
                onTap: () => setState(() => _payPeriod = e.key),
              ),
          ],
        ),
        if (currencies.length > 1) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final c in currencies)
                _choice(
                  label: c,
                  selected: _payCurrency == c,
                  onTap: () => setState(() => _payCurrency = c),
                ),
            ],
          ),
        ],
        if (_payText != null) ...[
          const SizedBox(height: 10),
          Text(
            'Shows as  ${_payText!}',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            'Jobs that show pay get more replies. Leave blank to agree it '
            'with the person.',
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
        ],
      ],
    );
  }

  /// What the listing will look like in the list, from the form as it is.
  Job _previewJob() => Job(
    id: 'preview',
    posterId: '',
    title: _titleController.text.trim().isEmpty
        ? 'Job title'
        : _titleController.text.trim(),
    company: _companyController.text.trim(),
    createdAt: DateTime.now(),
    country: _country,
    province: _regionValue,
    location: _locationController.text.trim(),
    type: _jobType,
    description: _descriptionController.text.trim(),
    category: _category,
    postType: _postType,
    level: _level,
    salaryRange: _redesign ? null : _orNull(_salaryController),
    payMin: _redesign && _hasPay ? _payMin : null,
    payMax: _redesign && _hasPay ? _payMax : null,
    payPeriod: _payPeriod,
    payCurrency: _payCurrency,
    isUrgent: _redesign && _urgent,
    sabbathFriendly: _sabbathFriendly,
    isSdaInstitution: _isSdaInstitution,
    workArrangement: _arrangement,
  );

  Widget _buildApplyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hint(
          _hiring
              ? 'Applicants use these from the listing. Members can also '
                    'message you in the app.'
              : 'Employers use these from your listing. They can also '
                    'message you in the app.',
        ),
        PostFormCard(
          child: Column(
            children: [
              PostFormLabeledField(
                label: 'Phone or WhatsApp',
                child: TextFormField(
                  controller: _phoneController,
                  maxLength: 20,
                  keyboardType: TextInputType.phone,
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                  decoration: postFormFilledDecoration(
                    icon: Icons.phone_outlined,
                    hint: Countries.phoneHint(_country),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PostFormLabeledField(
                label: 'Email',
                child: TextFormField(
                  controller: _emailController,
                  maxLength: 120,
                  keyboardType: TextInputType.emailAddress,
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                  decoration: postFormFilledDecoration(
                    icon: Icons.mail_outline,
                    hint: 'jobs@example.org',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final ok = RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(v.trim());
                    return ok ? null : 'Enter a valid email';
                  },
                ),
              ),
              if (_hiring && JobService.redesignAvailable) ...[
                const SizedBox(height: 18),
                PostFormLabeledField(
                  label: 'Application form link (optional)',
                  child: TextFormField(
                    controller: _applyUrlController,
                    maxLength: 300,
                    keyboardType: TextInputType.url,
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                    decoration: postFormFilledDecoration(
                      icon: Icons.link_rounded,
                      hint: 'https://…',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final ok = RegExp(
                        r'^https?://\S+$',
                        caseSensitive: false,
                      ).hasMatch(v.trim());
                      return ok ? null : 'Start the link with https://';
                    },
                  ),
                ),
              ],
              if (JobService.redesignAvailable) ...[
                const SizedBox(height: 18),
                PostFormLabeledField(
                  label: _hiring
                      ? 'Application instructions (optional)'
                      : 'Availability (optional)',
                  child: TextFormField(
                    controller: _applyInstructionsController,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                    decoration: postFormFilledDecoration(
                      icon: Icons.assignment_outlined,
                      hint: _hiring
                          ? 'e.g. Send your CV and two references by 15 Nov'
                          : 'e.g. Available from January, weekdays',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    final palette = context.palette;
    final place = [
      _locationController.text.trim(),
      _regionValue ?? '',
      Countries.nameOf(_country),
    ].where((s) => s.isNotEmpty).toSet().join(', ');
    final page = _myPages.where((p) => p.id == _pageId).firstOrNull;
    final rows = <(String, String, int)>[
      ('Listing', _hiring ? 'Vacancy' : 'Looking for work', 0),
      ('Title', _titleController.text.trim(), 1),
      if (_companyController.text.trim().isNotEmpty)
        ('Employer', _companyController.text.trim(), 1),
      if (page != null) ('Page', page.name, 1),
      ('Field', JobCategory.labelFor(_category), 1),
      ('Type', jobTypes[_jobType] ?? _jobType, 2),
      ('Experience', JobLevel.byId(_level).label, 2),
      if (_arrangement != null)
        ('Arrangement', workArrangements[_arrangement] ?? '', 2),
      ('Location', place, 2),
      if (_payText != null) ('Pay', _payText!, 3),
      if (_redesign && _urgent) (_hiring ? 'Start' : 'Available', 'Now', 2),
      if (_sabbathFriendly) ('Sabbath', 'Sabbath-friendly', 3),
      if (_hiring && _isSdaInstitution) ('Employer type', 'Adventist', 3),
      if (_phoneController.text.trim().isNotEmpty)
        ('Phone', _phoneController.text.trim(), 4),
      if (_emailController.text.trim().isNotEmpty)
        ('Email', _emailController.text.trim(), 4),
      if (_applyUrlController.text.trim().isNotEmpty && _hiring)
        ('Apply link', _applyUrlController.text.trim(), 4),
    ];
    final preview = _previewJob();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How it will look',
          style: AppTextStyles.labelLarge.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        IgnorePointer(
          child: preview.isSeeking
              ? SeekerCard(job: preview, onTap: () {})
              : JobCard(job: preview, onTap: () {}),
        ),
        const SizedBox(height: 18),
        _hint(
          _isEdit
              ? 'Check your changes. Editing the employer, contact details '
                    'or pay of a live job sends it back for a quick review.'
              : 'Check everything once. After you submit, a moderator '
                    'reviews it — usually within a day — and it goes live '
                    'for 30 days.',
        ),
        PostFormCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final r in rows)
                InkWell(
                  onTap: () => setState(() => _step = r.$3),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 104,
                          child: Text(
                            r.$1,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            r.$2,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: palette.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PostFormCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _hiring ? 'About the role' : 'About you',
                style: AppTextStyles.labelLarge.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _descriptionController.text.trim(),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.text,
                  height: 1.5,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _step = 3),
                  child: const Text('Edit'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// After a new post: say plainly what happens next.
  Widget _buildSubmitted() {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: AppColors.primaryBlue,
                  size: 44,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Waiting for review',
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineSmall.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'A moderator checks every listing before it goes live. '
                "You'll find it under My job posts in the meantime, and "
                "it stays up for 30 days once it's approved.",
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.textMuted,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    // This route's context is gone once it pops.
                    final router = GoRouter.of(context);
                    router.pop(true);
                    router.pushNamed('my_jobs');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('See my job posts'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.pop(true),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftBanner extends StatelessWidget {
  const _DraftBanner({required this.onDiscard});
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.history_rounded,
            size: 18,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Picked up where you left off.',
              style: AppTextStyles.bodySmall.copyWith(color: palette.text),
            ),
          ),
          TextButton(onPressed: onDiscard, child: const Text('Start over')),
        ],
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : palette.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(
                    alpha: selected ? 0.14 : 0.07,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primaryBlue),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.primaryBlue : palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.white,
          activeTrackColor: AppColors.primaryBlue,
        ),
      ],
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      icon: Icon(Icons.expand_more, color: AppColors.textMuted),
      style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
      decoration: postFormFilledDecoration(icon: icon, hint: hint),
      hint: Text(
        hint,
        style: AppTextStyles.bodyLarge.copyWith(
          color: AppColors.textMuted,
          fontSize: 15,
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
