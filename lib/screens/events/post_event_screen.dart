import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/event_model.dart';
import '../../services/event_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../widgets/post_form_widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PostEventScreen extends StatefulWidget {
  const PostEventScreen({super.key, this.existing});

  /// When non-null, the screen runs in edit mode: title/labels switch
  /// to "Update event", the form is pre-filled, and submission calls
  /// `EventService.updateEvent` instead of `postEvent`.
  final Event? existing;

  bool get isEditing => existing != null;

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
  DateTime? _endDate;
  TimeOfDay? _endTime;
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

    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description ?? '';
      _venueController.text = existing.location ?? '';
      _capacityController.text = existing.capacity?.toString() ?? '';
      _coverPhotoUrl = existing.coverPhotoUrl;
      _startDate = existing.eventDate;
      _startTime = _parseTime(existing.eventTime);
      _endDate = existing.endDate;
      if (existing.endTime != null) {
        _endTime = _parseTime(existing.endTime!);
      }
    }
  }

  TimeOfDay? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
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

  Future<DateTime?> _showDatePicker({
    required DateTime? initial,
    required DateTime first,
  }) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? first,
      firstDate: first,
      lastDate: now.add(const Duration(days: 365 * 3)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primaryBlue),
        ),
        child: child!,
      ),
    );
  }

  Future<TimeOfDay?> _showTimePicker({required TimeOfDay? initial}) {
    return showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 18, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primaryBlue),
        ),
        child: child!,
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await _showDatePicker(
      initial: _startDate,
      first: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked;
        // Clamp the end date forwards if it now sits before the new
        // start.
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await _showTimePicker(initial: _startTime);
    if (picked != null && mounted) setState(() => _startTime = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await _showDatePicker(
      initial: _endDate ?? _startDate,
      first: _startDate ?? DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _endDate = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await _showTimePicker(initial: _endTime ?? _startTime);
    if (picked != null && mounted) setState(() => _endTime = picked);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null) {
      setState(() => _error = 'Pick the event start date.');
      return;
    }
    if (_startTime == null) {
      setState(() => _error = 'Pick the start time.');
      return;
    }

    // End-time must not sit before the start. Same-day events with an
    // end-time set are validated minute-by-minute; multi-day events
    // are validated by date.
    if (_endDate != null && _endDate!.isBefore(_startDate!)) {
      setState(() => _error = 'End date cannot be before the start date.');
      return;
    }
    if (_endTime != null && _endDate == null) {
      // Single-day event with both times — compare directly.
      final startMin = _startTime!.hour * 60 + _startTime!.minute;
      final endMin = _endTime!.hour * 60 + _endTime!.minute;
      if (endMin <= startMin) {
        setState(() => _error = 'End time must be after the start time.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final startTimeStr = _formatTime(_startTime!);
      final endTimeStr = _endTime == null ? null : _formatTime(_endTime!);
      if (widget.isEditing) {
        await EventService.updateEvent(
          eventId: widget.existing!.id,
          title: _titleController.text,
          startDate: _startDate!,
          startTime: startTimeStr,
          endDate: _endDate,
          endTime: endTimeStr,
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
      } else {
        await EventService.postEvent(
          title: _titleController.text,
          startDate: _startDate!,
          startTime: startTimeStr,
          endDate: _endDate,
          endTime: endTimeStr,
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
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Event updated.'
                : 'Event submitted. Awaiting approval.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      context.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = widget.isEditing
              ? 'Could not update the event. Please try again.'
              : 'Could not post the event. Please try again.';
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
            PostFormHero(
              kicker: widget.isEditing ? 'EDIT EVENT' : 'NEW EVENT',
              title: widget.isEditing
                  ? 'Update your event'
                  : 'Tell us what\'s happening',
              subtitle: widget.isEditing
                  ? 'Edit the details and save your changes.'
                  : 'Submit camp meetings, youth rallies, or concerts.',
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
                        label: widget.isEditing
                            ? 'Save changes'
                            : 'Submit event',
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
                            image: CachedNetworkImageProvider(_coverPhotoUrl!),
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
    final startDateLabel = _startDate == null
        ? 'Pick start date'
        : _formatPickedDate(_startDate!);
    final startTimeLabel =
        _startTime == null ? 'Pick start time' : _startTime!.format(context);
    final endDateLabel = _endDate == null
        ? 'Pick end date (optional)'
        : _formatPickedDate(_endDate!);
    final endTimeLabel = _endTime == null
        ? 'Pick end time (optional)'
        : _endTime!.format(context);
    return PostFormCard(
      child: Column(
        children: [
          PostFormLabeledField(
            label: 'Start date',
            child: _PickerField(
              icon: Icons.calendar_today_outlined,
              label: startDateLabel,
              isPlaceholder: _startDate == null,
              onTap: _pickStartDate,
            ),
          ),
          const SizedBox(height: 14),
          PostFormLabeledField(
            label: 'Start time',
            child: _PickerField(
              icon: Icons.access_time,
              label: startTimeLabel,
              isPlaceholder: _startTime == null,
              onTap: _pickStartTime,
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'End date',
            child: _PickerField(
              icon: Icons.event_outlined,
              label: endDateLabel,
              isPlaceholder: _endDate == null,
              onTap: _pickEndDate,
              trailing: _endDate == null
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Color.fromRGBO(26, 26, 46, 0.5),
                      ),
                      onPressed: () => setState(() => _endDate = null),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          PostFormLabeledField(
            label: 'End time',
            child: _PickerField(
              icon: Icons.timer_outlined,
              label: endTimeLabel,
              isPlaceholder: _endTime == null,
              onTap: _pickEndTime,
              trailing: _endTime == null
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Color.fromRGBO(26, 26, 46, 0.5),
                      ),
                      onPressed: () => setState(() => _endTime = null),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPickedDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool isPlaceholder;
  final VoidCallback onTap;
  final Widget? trailing;

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
              ?trailing,
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
