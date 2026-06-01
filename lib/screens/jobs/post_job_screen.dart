import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/job_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../widgets/post_form_widgets.dart';

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _companyController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _requirementsController = TextEditingController();
  final _salaryController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  String _category = 'other';
  String _jobType = 'full_time';
  String _postType = 'hiring';
  String? _province;
  bool _sabbathFriendly = false;
  bool _isSdaInstitution = false;
  bool _saving = false;
  String? _error;

  static const _categories = <String, String>{
    'teaching_education': 'Teaching / Education',
    'healthcare': 'Healthcare',
    'construction_trades': 'Construction / Trades',
    'farming_agriculture': 'Farming / Agriculture',
    'driving_transport': 'Driving / Transport',
    'domestic_caregiving': 'Domestic / Caregiving',
    'business_admin': 'Business / Admin',
    'it_technology': 'IT / Technology',
    'ministry_church': 'Ministry / Church',
    'other': 'Other',
  };

  static const _jobTypes = <String, String>{
    'full_time': 'Full-time',
    'part_time': 'Part-time',
    'contract': 'Contract',
    'internship': 'Internship',
    'volunteer': 'Volunteer',
  };

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

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _titleController.dispose();
    _companyController.dispose();
    _descriptionController.dispose();
    _requirementsController.dispose();
    _salaryController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_province == null) {
      setState(() => _error = 'Select a province.');
      return;
    }
    setState(() => _saving = true);
    try {
      await JobService.postJob(
        title: _titleController.text,
        description: _descriptionController.text,
        category: _category,
        province: _province!,
        location: _locationController.text,
        company: _companyController.text.isEmpty ? null : _companyController.text,
        requirements: _requirementsController.text.isEmpty
            ? null
            : _requirementsController.text,
        jobType: _jobType,
        postType: _postType,
        salaryRange:
            _salaryController.text.isEmpty ? null : _salaryController.text,
        sabbathFriendly: _sabbathFriendly,
        isSdaInstitution: _isSdaInstitution,
        contactPhone: _phoneController.text.isEmpty ? null : _phoneController.text,
        contactEmail: _emailController.text.isEmpty ? null : _emailController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _postType == 'hiring' ? 'Job posted.' : 'Looking-for posted.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      context.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not post the job. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const PostFormHero(
              kicker: 'JOB BOARD',
              title: 'Post a job',
              subtitle:
                  'Hiring or looking — your post stays live for 30 days.',
              fallbackRouteName: 'jobs',
            ),
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) => Opacity(
                opacity: _fade.value,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPostTypeCard(),
                      const SizedBox(height: 16),
                      _buildBasicsCard(),
                      const SizedBox(height: 16),
                      _buildDetailsCard(),
                      const SizedBox(height: 16),
                      _buildLocationCard(),
                      const SizedBox(height: 16),
                      _buildBadgesCard(),
                      const SizedBox(height: 16),
                      _buildContactCard(),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        PostFormErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      PostFormSaveButton(
                        label: _postType == 'hiring' ? 'Post job' : 'Post listing',
                        busy: _saving,
                        onTap: _saving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostTypeCard() {
    return PostFormCard(
      child: Row(
        children: [
          Expanded(
            child: _PostTypeButton(
              label: 'Hiring',
              icon: Icons.business_center_outlined,
              selected: _postType == 'hiring',
              onTap: () => setState(() => _postType = 'hiring'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PostTypeButton(
              label: 'Looking for work',
              icon: Icons.search_outlined,
              selected: _postType == 'seeking',
              onTap: () => setState(() => _postType = 'seeking'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicsCard() {
    return PostFormCard(
      child: Column(
        children: [
          PostFormLabeledField(
            label: _postType == 'hiring' ? 'Job title' : 'Role you offer',
            child: TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Title is required';
                if (v.trim().length < 3) return 'Title is too short';
                return null;
              },
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.work_outline,
                hint: 'e.g. Mathematics Teacher',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: _postType == 'hiring' ? 'Company' : 'Your business (optional)',
            child: TextFormField(
              controller: _companyController,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.business_outlined,
                hint: 'e.g. Solusi Adventist High School',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Category',
            child: _Dropdown<String>(
              icon: Icons.category_outlined,
              hint: 'Choose a category',
              value: _category,
              items: _categories.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'other'),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Type',
            child: _Dropdown<String>(
              icon: Icons.schedule,
              hint: 'Choose a type',
              value: _jobType,
              items: _jobTypes.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _jobType = v ?? 'full_time'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return PostFormCard(
      child: Column(
        children: [
          PostFormLabeledField(
            label: 'Description',
            child: TextFormField(
              controller: _descriptionController,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Description is required';
                }
                if (v.trim().length < 20) return 'Tell us more';
                return null;
              },
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.notes_outlined,
                hint: 'Day-to-day responsibilities and goals',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Requirements',
            child: TextFormField(
              controller: _requirementsController,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.checklist,
                hint: 'Qualifications, experience, references',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Salary range (optional)',
            child: TextFormField(
              controller: _salaryController,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.payments_outlined,
                hint: 'e.g. USD 600–900 / month',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return PostFormCard(
      child: Column(
        children: [
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
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Location',
            child: TextFormField(
              controller: _locationController,
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Location required';
                return null;
              },
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.location_on_outlined,
                hint: 'e.g. Mutare or Remote (Zimbabwe)',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgesCard() {
    return PostFormCard(
      child: Column(
        children: [
          _ToggleRow(
            icon: Icons.brightness_2_outlined,
            iconColor: AppColors.goldAccent,
            iconBg: AppColors.goldAccent.withValues(alpha: 0.12),
            title: 'Sabbath-friendly',
            subtitle: 'Roster respects Friday sundown to Saturday sundown.',
            value: _sabbathFriendly,
            onChanged: (v) => setState(() => _sabbathFriendly = v),
          ),
          const SizedBox(height: 14),
          _ToggleRow(
            icon: Icons.church_outlined,
            iconColor: AppColors.primaryBlue,
            iconBg: AppColors.primaryBlue.withValues(alpha: 0.10),
            title: 'SDA institution',
            subtitle: 'School, hospital, or office of the SDA church.',
            value: _isSdaInstitution,
            onChanged: (v) => setState(() => _isSdaInstitution = v),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    return PostFormCard(
      child: Column(
        children: [
          PostFormLabeledField(
            label: 'Contact phone',
            child: TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.phone_outlined,
                hint: '+263 77 123 4567',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Contact email',
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.mail_outline,
                hint: 'jobs@example.org',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
                if (!ok) return 'Enter a valid email';
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PostTypeButton extends StatelessWidget {
  const _PostTypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? AppColors.primaryGradient : null,
            color: selected ? null : context.palette.cardMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.06),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? AppColors.white
                    : const Color.fromRGBO(26, 26, 46, 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected
                      ? AppColors.white
                      : const Color.fromRGBO(26, 26, 46, 0.75),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
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
                  color: const Color.fromRGBO(26, 26, 46, 0.6),
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
      icon: const Icon(
        Icons.expand_more,
        color: Color.fromRGBO(26, 26, 46, 0.5),
      ),
      style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
      decoration: postFormFilledDecoration(icon: icon, hint: hint),
      hint: Text(
        hint,
        style: AppTextStyles.bodyLarge.copyWith(
          color: const Color.fromRGBO(26, 26, 46, 0.5),
          fontSize: 15,
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
