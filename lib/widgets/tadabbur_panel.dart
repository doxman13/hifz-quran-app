import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../providers/notes_provider.dart';
import '../providers/settings_provider.dart';
import '../models/tadabbur_note.dart';
import '../data/tadabbur_repository.dart';
import '../theme/app_theme.dart';

class TadabburPanel extends StatefulWidget {
  final String surahId;
  final String verseId;
  final VoidCallback onClose;

  const TadabburPanel({
    Key? key,
    required this.surahId,
    required this.verseId,
    required this.onClose,
  }) : super(key: key);

  @override
  State<TadabburPanel> createState() => _TadabburPanelState();
}

class _TadabburPanelState extends State<TadabburPanel> {
  final _repo = TadabburRepository();
  final _controller = TextEditingController();
  bool _isPublic = false;
  bool _isAnonymous = false;
  bool _isSaving = false;
  bool _saveSuccess = false;
  bool _isEditing = false;
  TadabburNote? _savedNote;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadNote() async {
    setState(() => _loading = true);
    final notesProv = context.read<NotesProvider>();
    final existing = notesProv.getNoteObjectForVerse(
      widget.surahId,
      widget.verseId,
    );
    if (existing != null) {
      setState(() {
        _savedNote = existing;
        _controller.text = existing.noteText;
        _isPublic = existing.isPublic;
        _isAnonymous = existing.isAnonymous;
        _loading = false;
        if (existing.noteText.trim().isEmpty) {
          _isEditing = true;
        }
      });
    } else {
      setState(() {
        _isEditing = true;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final text = _controller.text.trim();

    setState(() => _isSaving = true);
    final notesProv = context.read<NotesProvider>();
    final isPublicToSave = text.isEmpty ? false : _isPublic;

    await notesProv.saveNote(
      surahId: widget.surahId,
      verseId: widget.verseId,
      noteText: text,
      isPublic: isPublicToSave,
      isAnonymous: _isAnonymous,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      setState(() => _saveSuccess = true);
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) {
          setState(() => _saveSuccess = false);
          widget.onClose();
        }
      });
    }
  }

  Future<void> _delete() async {
    try {
      await context.read<NotesProvider>().deleteNote(
        widget.surahId,
        widget.verseId,
      );
      if (mounted) {
        setState(() => _savedNote = null);
        widget.onClose();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final colors = settings.getAppColors();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(color: colors.borderSoft),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border(bottom: BorderSide(color: colors.borderSoft)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      color: Colors.red.shade400,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Favorite & Reflection — Ayah ${widget.surahId}:${widget.verseId}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.textStrong,
                      ),
                    ),
                    const Spacer(),
                    if (_savedNote != null)
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _isEditing = !_isEditing),
                        icon: Icon(
                          _isEditing ? Icons.close : Icons.edit_rounded,
                          size: 14,
                          color: colors.primary,
                        ),
                        label: Text(
                          _isEditing ? 'Cancel' : 'Edit',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: widget.onClose,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: colors.foreground.withOpacity(0.6),
                    ),
                  ],
                ),
              ),
              // Body
              Flexible(
                child: SingleChildScrollView(
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_savedNote != null && !_isEditing)
                      ? _buildSavedCard(colors, isDark)
                      : _buildForm(colors, isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedCard(AppThemeColors colors, bool isDark) {
    final hasNoteText = _savedNote!.noteText.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? colors.background.withOpacity(0.4)
                  : colors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.borderSoft),
            ),
            child: hasNoteText
                ? Text(
                    _savedNote!.noteText,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: colors.textStrong,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        color: Colors.red.shade400,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Favorited this verse (no reflection text added)',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: colors.textStrong.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (hasNoteText) ...[
                _buildPrivacyChip(colors),
                const SizedBox(width: 8),
              ],
              Text(
                timeago.format(_savedNote!.updatedAt),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: colors.foreground.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (hasNoteText) ...[
                if (_savedNote!.isPublic)
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        final updated = await _repo.saveNote(
                          TadabburNote(
                            id: _savedNote!.id,
                            userId: _savedNote!.userId,
                            surahId: _savedNote!.surahId,
                            verseId: _savedNote!.verseId,
                            noteText: _savedNote!.noteText,
                            isPublic: false,
                            isAnonymous: _savedNote!.isAnonymous,
                            likesCount: _savedNote!.likesCount,
                            language: _savedNote!.language,
                            createdAt: _savedNote!.createdAt,
                            updatedAt: DateTime.now(),
                            synced: true,
                          ),
                        );
                        if (updated != null && mounted) {
                          setState(() => _savedNote = updated);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.lock_outline_rounded, size: 14),
                    label: Text(
                      'Make Private',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        final updated = await _repo.saveNote(
                          TadabburNote(
                            id: _savedNote!.id,
                            userId: _savedNote!.userId,
                            surahId: _savedNote!.surahId,
                            verseId: _savedNote!.verseId,
                            noteText: _savedNote!.noteText,
                            isPublic: true,
                            isAnonymous: _savedNote!.isAnonymous,
                            likesCount: _savedNote!.likesCount,
                            language: _savedNote!.language,
                            createdAt: _savedNote!.createdAt,
                            updatedAt: DateTime.now(),
                            synced: true,
                          ),
                        );
                        if (updated != null && mounted) {
                          setState(() => _savedNote = updated);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.public_rounded, size: 14),
                    label: Text(
                      'Make Public',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Colors.red.shade400,
                ),
                tooltip: 'Unfavorite',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(
                        'Remove from Favorites',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                      ),
                      content: Text(
                        'Are you sure you want to unfavorite this verse?',
                        style: GoogleFonts.inter(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            'Unfavorite',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) await _delete();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyChip(AppThemeColors colors) {
    final isPublic = _savedNote?.isPublic ?? _isPublic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPublic
            ? Colors.green.withOpacity(0.08)
            : colors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPublic
              ? Colors.green.withOpacity(0.2)
              : colors.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPublic ? Icons.public : Icons.lock_outline,
            size: 11,
            color: isPublic ? Colors.green : colors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            isPublic ? 'Public' : 'Private',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: isPublic ? Colors.green : colors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(AppThemeColors colors, bool isDark) {
    final isTextEmpty = _controller.text.trim().isEmpty;
    final buttonLabel = _saveSuccess
        ? 'Saved successfully'
        : isTextEmpty
        ? 'Save as Favorite'
        : 'Save Favorite & Note';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.rate_review_outlined,
                size: 15,
                color: colors.primary.withOpacity(0.8),
              ),
              const SizedBox(width: 6),
              Text(
                'Reflection Note (Optional)',
                style: GoogleFonts.inter(
                  color: colors.textStrong,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 10,
            style: GoogleFonts.notoSansThai(fontSize: 15, color: colors.textStrong),
            decoration: InputDecoration(
              hintText: 'Write your reflection here (optional)...',
              hintStyle: GoogleFonts.notoSansThai(
                fontSize: 14,
                color: colors.foreground.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: isDark
                  ? colors.background.withOpacity(0.4)
                  : colors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.borderSoft, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (!isTextEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 15,
                  color: colors.primary.withOpacity(0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  'Visibility',
                  style: GoogleFonts.inter(
                    color: colors.textStrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? colors.background.withOpacity(0.5)
                    : colors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.borderSoft),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isPublic = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_isPublic
                              ? (isDark
                                    ? colors.primary.withOpacity(0.2)
                                    : colors.primary)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: !_isPublic
                                  ? (isDark
                                        ? colors.primary
                                        : colors.textInverse)
                                  : colors.foreground.withOpacity(0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Private',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: !_isPublic
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: !_isPublic
                                    ? (isDark
                                          ? colors.primary
                                          : colors.textInverse)
                                    : colors.foreground.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isPublic = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _isPublic
                              ? (isDark
                                    ? colors.primary.withOpacity(0.2)
                                    : colors.primary)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.public_rounded,
                              size: 14,
                              color: _isPublic
                                  ? (isDark
                                        ? colors.primary
                                        : colors.textInverse)
                                  : colors.foreground.withOpacity(0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Public',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: _isPublic
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _isPublic
                                    ? (isDark
                                          ? colors.primary
                                          : colors.textInverse)
                                    : colors.foreground.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: isTextEmpty
                    ? Colors.red.shade400
                    : colors.primary,
                foregroundColor: colors.textInverse,
                disabledBackgroundColor:
                    (isTextEmpty ? Colors.red.shade400 : colors.primary)
                        .withOpacity(0.25),
                disabledForegroundColor: colors.textInverse.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
              ),
              onPressed: _isSaving || _saveSuccess ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _saveSuccess
                          ? Icons.check_circle_outline_rounded
                          : isTextEmpty
                          ? Icons.favorite_rounded
                          : Icons.save_rounded,
                      size: 16,
                    ),
              label: Text(
                buttonLabel,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
