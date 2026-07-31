import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/tadabbur_note.dart';
import '../providers/notes_provider.dart';
import '../data/tadabbur_repository.dart';

class TadabburAccordion extends StatefulWidget {
  final String surahId;
  final String verseId;
  final VoidCallback onCancel;

  const TadabburAccordion({
    Key? key,
    required this.surahId,
    required this.verseId,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<TadabburAccordion> createState() => _TadabburAccordionState();
}

class _TadabburAccordionState extends State<TadabburAccordion> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _notesController = TextEditingController();
  
  bool _isPublic = false;
  bool _isAnonymous = false;
  bool _isSaving = false;
  bool _saveSuccess = false;

  List<TadabburNote> _communityNotes = [];
  bool _isLoadingCommunity = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Load existing personal note state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notesProv = Provider.of<NotesProvider>(context, listen: false);
      final existingNote = notesProv.getNoteObjectForVerse(widget.surahId, widget.verseId);
      if (existingNote != null) {
        setState(() {
          _notesController.text = existingNote.noteText;
          _isPublic = existingNote.isPublic;
          _isAnonymous = existingNote.isAnonymous;
        });
      }
    });

    _fetchCommunityNotes();
  }

  Future<void> _fetchCommunityNotes() async {
    setState(() => _isLoadingCommunity = true);
    final repo = TadabburRepository();
    final notes = await repo.fetchCommunityNotes(widget.surahId, widget.verseId);
    if (mounted) {
      setState(() {
        _communityNotes = notes;
        _isLoadingCommunity = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _saveNote(NotesProvider notesProv) async {
    setState(() => _isSaving = true);
    
    await notesProv.saveNote(
      surahId: widget.surahId,
      verseId: widget.verseId,
      noteText: _notesController.text,
      isPublic: _isPublic,
      isAnonymous: _isAnonymous,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (_notesController.text.trim().isNotEmpty) {
        setState(() => _saveSuccess = true);
        Future.delayed(const Duration(milliseconds: 1600), () {
          if (mounted) {
            setState(() => _saveSuccess = false);
            widget.onCancel();
          }
        });
      } else {
        widget.onCancel();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notesProv = Provider.of<NotesProvider>(context);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelStyle: GoogleFonts.notoSansThai(fontWeight: FontWeight.w500, fontSize: 13),
            unselectedLabelStyle: GoogleFonts.notoSansThai(fontSize: 13),
            indicatorColor: Theme.of(context).primaryColor,
            labelColor: isDark ? Colors.white : Colors.black87,
            tabs: const [
              Tab(text: 'My Note'),
              Tab(text: 'Community'),
            ],
          ),
          SizedBox(
            height: 320, // fixed height for content area
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMyNoteTab(isDark, notesProv),
                _buildCommunityTab(isDark, notesProv),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyNoteTab(bool isDark, NotesProvider notesProv) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextField(
              controller: _notesController,
              style: GoogleFonts.notoSansThai(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Write your reflection (Tadabbur)...',
                hintStyle: GoogleFonts.notoSansThai(fontSize: 13),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(10),
              ),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  title: Text('Public Note', style: GoogleFonts.notoSansThai(fontSize: 12, fontWeight: FontWeight.w500)),
                  subtitle: Text('Share with community', style: GoogleFonts.notoSansThai(fontSize: 10, color: Colors.grey)),
                  value: _isPublic,
                  onChanged: (val) => setState(() => _isPublic = val),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              if (_isPublic)
                Expanded(
                  child: SwitchListTile(
                    title: Text('Anonymous', style: GoogleFonts.notoSansThai(fontSize: 12, fontWeight: FontWeight.w500)),
                    subtitle: Text('Hide my name', style: GoogleFonts.notoSansThai(fontSize: 10, color: Colors.grey)),
                    value: _isAnonymous,
                    onChanged: (val) => setState(() => _isAnonymous = val),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: Text('Cancel', style: GoogleFonts.notoSansThai(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSaving || _saveSuccess ? null : () => _saveNote(notesProv),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _saveSuccess ? 'Saved ✓' : 'Save Note',
                        style: GoogleFonts.notoSansThai(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityTab(bool isDark, NotesProvider notesProv) {
    if (_isLoadingCommunity) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_communityNotes.isEmpty) {
      return Center(
        child: Text(
          'No public notes yet. Be the first to share your reflection!',
          style: GoogleFonts.notoSansThai(color: Colors.grey, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _communityNotes.length,
      separatorBuilder: (_, __) => Divider(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      itemBuilder: (context, index) {
        final note = _communityNotes[index];
        final authorName = note.isAnonymous ? 'Anonymous' : (note.userEmail?.split('@').first ?? 'Someone');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
                  child: Text(
                    authorName.substring(0, 1).toUpperCase(),
                    style: GoogleFonts.notoSansThai(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).primaryColor),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  authorName,
                  style: GoogleFonts.notoSansThai(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  timeago.format(note.createdAt),
                  style: GoogleFonts.notoSansThai(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              note.noteText,
              style: GoogleFonts.notoSansThai(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                InkWell(
                  onTap: () {
                    // Optimistic toggle
                    setState(() {
                       // We can't mutate note.userLiked directly if it's final. Let's rebuild the note or fetch again.
                       // For simple UI:
                    });
                    notesProv.toggleLikeLocally(note, () {
                       _fetchCommunityNotes(); // refresh to get true counts
                    });
                  },
                  child: Row(
                    children: [
                      Icon(
                        note.userLiked ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: note.userLiked ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${note.likesCount}',
                        style: GoogleFonts.notoSansThai(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
