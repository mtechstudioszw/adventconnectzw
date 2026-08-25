import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/countries.dart';
import '../../models/event_model.dart';
import '../../services/ads/interstitial_ad_manager.dart';
import '../../services/auth_service.dart';
import '../../services/event_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_theme.dart';
import '../../widgets/country_picker_sheet.dart';
import '../../widgets/event_card.dart';
import '../../widgets/preview_sheet.dart';
import '../widgets/post_form_widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PostEventScreen extends StatefulWidget {
  const PostEventScreen({super.key, this.existing, this.churchId});

  /// When non-null, the screen runs in edit mode: title/labels switch
  /// to "Update event", the form is pre-filled, and submission calls
  /// `EventService.updateEvent` instead of `postEvent`.
  final Event? existing;

  /// When non-null, this is a church admin posting on behalf of their church
  /// — the new event is tagged with this church so it can be featured on Home.
  final String? churchId;

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

  /// Free-text region for non-ZW events. Shares the `province` column with
  /// [_province]; see [_regionValue].
  final _regionController = TextEditingController();
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

  /// ISO 3166-1 alpha-2. Never null in practice — seeded in [initState]
  /// from the event being edited, else from the poster's own profile.
  String? _country;
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
    // Country first, then whichever location control hangs off it. Edit
    // mode used to leave province blank, so re-saving an event moved it to
    // whatever the organiser happened to re-pick.
    _country = existing?.country ?? AuthService.currentCountry();
    if (_isZimbabwe) {
      _province = existing?.province;
    } else {
      _regionController.text = existing?.province ?? '';
    }
  }

  /// Zimbabwe is the one country with a real province list in this app
  /// (`_provinces`). Everywhere else the same column takes free text.
  bool get _isZimbabwe => _country == 'ZW';

  /// What goes in the `province` column: the dropdown in Zimbabwe, the
  /// free-text region anywhere else, null when neither is filled.
  String? get _regionValue {
    if (_isZimbabwe) return _province;
    final typed = _regionController.text.trim();
    return typed.isEmpty ? null : typed;
  }

  /// Changing country invalidates whichever location control is showing,
  /// so the old value is dropped rather than carried across.
  void _onCountryPicked(Country picked) {
    setState(() {
      _country = picked.code;
      _province = null;
      _regionController.clear();
    });
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
    _regionController.dispose();
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
      builder: brandPickerBuilder,
    );
  }

  Future<TimeOfDay?> _showTimePicker({required TimeOfDay? initial}) {
    return showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 18, minute: 0),
      builder: brandPickerBuilder,
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

    // Preview before it goes out. An event card leads with a date block
    // and a cover crop — neither of which the form shows you.
    final confirmed = await showEntityPreview(
      context,
      title: 'How your event will look',
      confirmLabel: widget.isEditing ? 'Save changes' : 'Post it',
      child: EventCard(
        event: Event(
          // Never persisted — the real id comes from the insert.
          id: widget.existing?.id ?? 'preview',
          title: _titleController.text.trim(),
          eventDate: _startDate!,
          eventTime: _formatTime(_startTime!),
          endDate: _endDate,
          endTime: _endTime == null ? null : _formatTime(_endTime!),
          rsvpCount: widget.existing?.rsvpCount ?? 0,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          location: _venueController.text.trim().isEmpty
              ? null
              : _venueController.text.trim(),
          coverPhotoUrl: _coverPhotoUrl,
          capacity: int.tryParse(_capacityController.text),
          createdAt: DateTime.now(),
        ),
        isGoing: false,
        onTap: () {},
      ),
    );
    if (!confirmed || !mounted) return;

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
          country: _country,
          province: _regionValue,
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
          churchId: widget.churchId,
          title: _titleController.text,
          startDate: _startDate!,
          startTime: startTimeStr,
          endDate: _endDate,
          endTime: endTimeStr,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          venue: _venueController.text.isEmpty ? null : _venueController.text,
          country: _country,
          province: _regionValue,
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
      unawaited(InterstitialAdManager.maybeShow());
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
      backgroundColor: Colors.transparent,
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
              color: context.palette.textMuted,
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
              maxLength: 120,
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
              maxLength: 4000,
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
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: context.palette.textMuted,
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
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: context.palette.textMuted,
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
              maxLength: 120,
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
              maxLength: 60,
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
                  const DropdownMenuItem(
                      value: null, child: Text('Not specified')),
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
              maxLength: 80,
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
              maxLength: 20,
              keyboardType: TextInputType.phone,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.phone_outlined,
                hint: Countries.phoneHint(_country),
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
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.palette.divider),
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
                        ? context.palette.textMuted
                        : context.palette.text,
                  ),
                ),
              ),
              ?trailing,
              Icon(
                Icons.expand_more,
                color: context.palette.textMuted,
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
      // The popup menu surface — without this it defaults to a light canvas
      // in dark mode, leaving the province options on a white sheet.
      dropdownColor: context.palette.card,
      icon: Icon(
        Icons.expand_more,
        color: context.palette.textMuted,
      ),
      style: AppTextStyles.bodyLarge.copyWith(
        fontSize: 15,
        color: context.palette.text,
      ),
      decoration: postFormFilledDecoration(icon: icon, hint: hint),
      hint: Text(
        hint,
        style: AppTextStyles.bodyLarge.copyWith(
          color: context.palette.textMuted,
          fontSize: 15,
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
