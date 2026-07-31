// lib/models/tadabbur_note.dart

class TadabburNote {
  final String id;
  final String userId;
  final String surahId;
  final String verseId;
  final String noteText;
  final bool isPublic;
  final bool isAnonymous;
  final int likesCount;
  final String language;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? userEmail;
  final bool userLiked;
  final bool synced;

  TadabburNote({
    required this.id,
    required this.userId,
    required this.surahId,
    required this.verseId,
    required this.noteText,
    required this.isPublic,
    required this.isAnonymous,
    required this.likesCount,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
    this.userEmail,
    this.userLiked = false,
    this.synced = true,
  });

  factory TadabburNote.fromJson(Map<String, dynamic> json) {
    return TadabburNote(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      surahId: json['surah_id'] as String,
      verseId: json['verse_id'] as String,
      noteText: json['note_text'] as String,
      isPublic: json['is_public'] as bool? ?? false,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      likesCount: json['likes_count'] as int? ?? 0,
      language: json['language'] as String? ?? 'th',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String) 
          : DateTime.parse(json['created_at'] as String),
      userEmail: json['user_email'] as String?,
      userLiked: json['user_liked'] as bool? ?? false,
      synced: json['synced'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'surah_id': surahId,
      'verse_id': verseId,
      'note_text': noteText,
      'is_public': isPublic,
      'is_anonymous': isAnonymous,
      'likes_count': likesCount,
      'language': language,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
