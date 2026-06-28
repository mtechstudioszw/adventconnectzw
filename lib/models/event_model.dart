class Event {
  const Event({
    required this.id,
    required this.title,
    required this.eventDate,
    required this.eventTime,
    required this.rsvpCount,
    this.endDate,
    this.endTime,
    this.description,
    this.location,
    this.churchId,
    this.churchName,
    this.churchPhotoUrl,
    this.organizerId,
    this.organizerName,
    this.contactPhone,
    this.capacity,
    this.coverPhotoUrl,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? description;
  final DateTime eventDate;
  final String eventTime;
  /// Optional end date — for multi-day events. Null means single-day
  /// (ends on [eventDate]).
  final DateTime? endDate;
  /// Optional end time in `HH:mm`. Null means open-ended.
  final String? endTime;
  final String? location;
  final String? churchId;

  /// Name of the church that posted this event (when church-hosted). Drives
  /// the featured Home card + gold tick.
  final String? churchName;

  /// The church's logo (profile photo), shown on the featured card once set.
  final String? churchPhotoUrl;
  final String? organizerId;

  /// True for events posted by a church admin (tagged with a church).
  bool get isChurchEvent => (churchId ?? '').isNotEmpty;
  /// Display name of the user who posted this event. Populated from
  /// the joined profile in EventService.fetchEvents / fetchEventById.
  /// May be null on cached payloads written by older builds.
  final String? organizerName;
  /// Direct contact phone for the event (optional). When present we
  /// surface a WhatsApp + Call button on the details screen so users
  /// can reach the organizer outside the in-app chat.
  final String? contactPhone;
  final int? capacity;
  final int rsvpCount;
  final String? coverPhotoUrl;
  final DateTime? createdAt;

  DateTime get startsAt {
    final parts = eventTime.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(
      eventDate.year,
      eventDate.month,
      eventDate.day,
      hour,
      minute,
    );
  }

  bool get isPast => startsAt.isBefore(DateTime.now());
  bool get isFull => capacity != null && rsvpCount >= capacity!;

  factory Event.fromJson(Map<String, dynamic> json) {
    // DB columns are `start_date` / `start_time`. We keep the legacy
    // `event_date` / `event_time` keys as a fallback so cached payloads
    // written by older builds still hydrate correctly.
    final rawDate = json['start_date'] ?? json['event_date'];
    DateTime eventDate;
    if (rawDate is DateTime) {
      eventDate = rawDate;
    } else if (rawDate != null) {
      eventDate = DateTime.tryParse('$rawDate') ?? DateTime.now();
    } else {
      eventDate = DateTime.now();
    }

    final rawTime = json['start_time'] ?? json['event_time'];
    String eventTime;
    if (rawTime == null) {
      eventTime = '00:00';
    } else {
      eventTime = rawTime.toString();
      if (eventTime.length >= 5) {
        eventTime = eventTime.substring(0, 5);
      }
    }

    final rawEndDate = json['end_date'];
    DateTime? endDate;
    if (rawEndDate is DateTime) {
      endDate = rawEndDate;
    } else if (rawEndDate != null) {
      endDate = DateTime.tryParse('$rawEndDate');
    }

    final rawEndTime = json['end_time'];
    String? endTime;
    if (rawEndTime != null) {
      final s = rawEndTime.toString();
      endTime = s.length >= 5 ? s.substring(0, 5) : s;
    }

    // Service inserts `venue` + `city`; model surfaces a single `location`
    // string. Prefer an explicit `location`; otherwise compose one from
    // venue/city so events posted through the form still show a location.
    final explicitLocation = json['location'] as String?;
    String? resolvedLocation = explicitLocation;
    if (resolvedLocation == null || resolvedLocation.isEmpty) {
      final venue = (json['venue'] as String?)?.trim() ?? '';
      final city = (json['city'] as String?)?.trim() ?? '';
      if (venue.isNotEmpty && city.isNotEmpty) {
        resolvedLocation = '$venue, $city';
      } else if (venue.isNotEmpty) {
        resolvedLocation = venue;
      } else if (city.isNotEmpty) {
        resolvedLocation = city;
      }
    }

    final organizer = json['profiles'];
    final organizerMap =
        organizer is Map<String, dynamic> ? organizer : null;
    final organizerName = (organizerMap?['full_name'] as String?)?.trim();

    final church = json['churches'];
    final churchMap = church is Map<String, dynamic> ? church : null;

    return Event(
      id: json['id'].toString(),
      title: (json['title'] ?? '') as String,
      description: json['description'] as String?,
      eventDate: eventDate,
      eventTime: eventTime,
      endDate: endDate,
      endTime: endTime,
      location: resolvedLocation,
      churchId: json['church_id']?.toString(),
      churchName: churchMap?['name'] as String?,
      churchPhotoUrl: churchMap?['profile_photo_url'] as String?,
      organizerId: json['organizer_id']?.toString(),
      organizerName: (organizerName == null || organizerName.isEmpty)
          ? (json['contact_name'] as String?)?.trim()
          : organizerName,
      contactPhone: (json['contact_phone'] as String?)?.trim().isNotEmpty == true
          ? (json['contact_phone'] as String).trim()
          : null,
      capacity: _readNullableInt(json['capacity']),
      rsvpCount: _readInt(json['rsvp_count']),
      coverPhotoUrl: json['cover_photo_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'start_date': _formatDate(eventDate),
        'start_time': eventTime,
        if (endDate != null) 'end_date': _formatDate(endDate!),
        if (endTime != null) 'end_time': endTime,
        'location': location,
        'church_id': churchId,
        'organizer_id': organizerId,
        'contact_phone': contactPhone,
        'capacity': capacity,
        'rsvp_count': rsvpCount,
        'cover_photo_url': coverPhotoUrl,
        'created_at': createdAt?.toIso8601String(),
      };

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Event copyWith({int? rsvpCount}) {
    return Event(
      id: id,
      title: title,
      description: description,
      eventDate: eventDate,
      eventTime: eventTime,
      endDate: endDate,
      endTime: endTime,
      location: location,
      churchId: churchId,
      organizerId: organizerId,
      organizerName: organizerName,
      contactPhone: contactPhone,
      capacity: capacity,
      rsvpCount: rsvpCount ?? this.rsvpCount,
      coverPhotoUrl: coverPhotoUrl,
      createdAt: createdAt,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static int? _readNullableInt(dynamic value) {
    if (value == null) return null;
    return _readInt(value);
  }
}
