class Event {
  const Event({
    required this.id,
    required this.title,
    required this.eventDate,
    required this.eventTime,
    required this.rsvpCount,
    this.description,
    this.location,
    this.churchId,
    this.organizerId,
    this.capacity,
    this.coverPhotoUrl,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? description;
  final DateTime eventDate;
  final String eventTime;
  final String? location;
  final String? churchId;
  final String? organizerId;
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
    final rawDate = json['event_date'];
    DateTime eventDate;
    if (rawDate is DateTime) {
      eventDate = rawDate;
    } else {
      eventDate = DateTime.tryParse('$rawDate') ?? DateTime.now();
    }

    final rawTime = json['event_time'];
    String eventTime;
    if (rawTime == null) {
      eventTime = '00:00';
    } else {
      eventTime = rawTime.toString();
      if (eventTime.length >= 5) {
        eventTime = eventTime.substring(0, 5);
      }
    }

    return Event(
      id: json['id'].toString(),
      title: (json['title'] ?? '') as String,
      description: json['description'] as String?,
      eventDate: eventDate,
      eventTime: eventTime,
      location: json['location'] as String?,
      churchId: json['church_id']?.toString(),
      organizerId: json['organizer_id']?.toString(),
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
        'event_date':
            '${eventDate.year.toString().padLeft(4, '0')}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}',
        'event_time': eventTime,
        'location': location,
        'church_id': churchId,
        'organizer_id': organizerId,
        'capacity': capacity,
        'rsvp_count': rsvpCount,
        'cover_photo_url': coverPhotoUrl,
        'created_at': createdAt?.toIso8601String(),
      };

  Event copyWith({int? rsvpCount}) {
    return Event(
      id: id,
      title: title,
      description: description,
      eventDate: eventDate,
      eventTime: eventTime,
      location: location,
      churchId: churchId,
      organizerId: organizerId,
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
