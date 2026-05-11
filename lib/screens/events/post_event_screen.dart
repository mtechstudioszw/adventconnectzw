import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/event_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../widgets/post_form_widgets.dart';

class PostEventScreen extends StatefulWidget {
  const PostEventScreen({super.key});

  @override
  State<PostEventScreen> createState() => _PostEventScreenState();
}

class _PostEventScreenState extends State<PostEventScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _venueController = TextEditingController();
  final _cityController = TextEditingController();
  final _capacityController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  DateTime? _startDate;
  TimeOfDay? _startTime;
  String? _province;
  String _category = 'community';
  String? _coverPhotoUrl;
  bool _uploadingPhoto = false;
  bool _saving = false;
  String? _error;

  static const _categories = <String, String>{
    'camp_meeting': 'Camp meeting',
    'youth': 'Youth',
    'concert': 'Concert',
    'graduation': 'Graduation',
    'week_of_prayer': 'Week of prayer',
    'conference': 'Conference',
    'community': 'Community',
    'other': 'Other',
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
    _descriptionController.dispose();
    _venueController.dispose();
    _cityController.dispose();
    _capacityController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primaryBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 18, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primaryBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _startTime = picked);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null) {
      setState(() => _error = 'Pick the event date.');
      return;
    }
    if (_startTime == null) {
      setState(() => _error = 'Pick the start time.');
      return;
    }
    setState(() => _saving = true);
    try {
      final hh = _startTime!.hour.toString().padLeft(2, '0');
      final mm = _startTime!.minute.toString().padLeft(2, '0');
      await EventService.postEvent(
        title: _titleController.text,
        startDate: _startDate!,
        startTime: '$hh:$mm',
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        venue: _venueController.text.isEmpty ? null : _venueController.text,
        province: _province,
        city: _cityController.text.isEmpty ? null : _cityController.text,
        category: _category,
        capacity: int.tryParse(_capacityController.text),
        contactName: _contactNameController.text.isEmpty
            ? null
            : _contactNameController.text,
        contactPhone: _contactPhoneController.text.isEmpty
            ? null
            : _contactPhoneController.text,
        coverPhotoUrl: _coverPhotoUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Event submitted. Awaiting approval.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      context.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not post the event. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const PostFormHero(
              kicker: 'NEW EVENT',
              title: 'Tell us what\'s happening',
              subtitle: 'Submit camp meetings, youth rallies, or concerts.',
              fallbackRouteName: 'events',
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
                      _buildFlyerCard(),
                      const SizedBox(height: 16),
                      _buildBasicsCard(),
                      const SizedBox(height: 16),
                      _buildScheduleCard(),
                      const SizedBox(height: 16),
                      _buildLocationCard(),
                      const SizedBox(height: 16),
                      _buildContactCard(),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        PostFormErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      PostFormSaveButton(
                        label: 'Submit event',
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

  Future<void> _pickFlyer() async {
    if (_uploadingPhoto) return;
    setState(() {
      _uploadingPhoto = true;
      _error = null;
    });
    try {
      final url = await StorageService.pickAndUploadEventFlyer();
      if (!mounted) return;
      if (url != null) setState(() => _coverPhotoUrl = url);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not upload flyer. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Widget _buildFlyerCard() {
    final hasPhoto = _coverPhotoUrl != null && _coverPhotoUrl!.isNotEmpty;
    return PostFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EVENT FLYER',
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.65),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _uploadingPhoto ? null : _pickFlyer,
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.30),
                    ),
                    image: hasPhoto
                        ? DecorationImage(
                            image: NetworkImage(_coverPhotoUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _uploadingPhoto
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.primaryBlue,
                          ),
                        )
                      : hasPhoto
                          ? null
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.image_outlined,
                                  color: AppColors.primaryBlue,
                                  size: 36,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to add a flyer',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: AppColors.primaryBlue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                ),
              ),
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
            label: 'Title',
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
                icon: Icons.event_outlined,
                hint: 'e.g. Harare Youth Rally',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Description',
            child: TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.notes_outlined,
                hint: 'What is this event about?',
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
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'community'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard() {
    final dateLabel = _startDate == null
        ? 'Pick a date'
        : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}';
    final timeLabel = _startTime == null
        ? 'Pick a time'
        : _startTime!.format(context);
    return PostFormCard(
      child: Column(
        children: [
          PostFormLabeledField(
            label: 'Date',
            child: _PickerField(
              icon: Icons.calendar_today_outlined,
              label: dateLabel,
              isPlaceholder: _startDate == null,
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Start time',
            child: _PickerField(
              icon: Icons.access_time,
              label: timeLabel,
              isPlaceholder: _startTime == null,
              onTap: _pickTime,
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
            label: 'Venue',
            child: TextFormField(
              controller: _venueController,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.place_outlined,
                hint: 'e.g. Solusi University Chapel',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'City',
            child: TextFormField(
              controller: _cityController,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.location_city_outlined,
                hint: 'e.g. Harare',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Province',
            child: _Dropdown<String?>(
              icon: Icons.map_outlined,
              hint: 'Choose a province',
              value: _province,
              items: [
                const DropdownMenuItem(value: null, child: Text('Not specified')),
                for (final p in _provinces)
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => _province = v),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Capacity (optional)',
            child: TextFormField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.people_outline,
                hint: '500',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final n = int.tryParse(v);
                if (n == null || n < 1) return 'Enter a positive number';
                return null;
              },
            ),
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
            label: 'Contact name',
            child: TextFormField(
              controller: _contactNameController,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.person_outline,
                hint: 'Who should attendees reach?',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Contact phone',
            child: TextFormField(
              controller: _contactPhoneController,
              keyboardType: TextInputType.phone,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.phone_outlined,
                hint: '+263 77 123 4567',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.isPlaceholder,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isPlaceholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.06)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 15,
                    color: isPlaceholder
                        ? const Color.fromRGBO(26, 26, 46, 0.5)
                        : AppColors.textDark,
                  ),
                ),
              ),
              const Icon(
                Icons.expand_more,
                color: Color.fromRGBO(26, 26, 46, 0.5),
              ),
            ],
          ),
        ),
      ),
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
