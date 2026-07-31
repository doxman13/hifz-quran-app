import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../database/hifz_repository.dart';
import '../models/hifz_session_config.dart';
import '../providers/settings_provider.dart';
import '../data/quran_repository.dart';
import '../data/quran_foundation_repository.dart';
import 'hifz_memorize_screen.dart';

class HifzHistoryScreen extends StatefulWidget {
  final QuranRepository quranRepository;
  final QuranFoundationRepository foundationRepository;

  const HifzHistoryScreen({
    super.key,
    required this.quranRepository,
    required this.foundationRepository,
  });

  @override
  State<HifzHistoryScreen> createState() => _HifzHistoryScreenState();
}

class _HistoryItem {
  final String id;
  final HifzSessionType sessionType;
  final int? surahNumber;
  final String title;
  final DateTime date;
  final bool isInProgress;
  final ActiveSessionSnapshot? snapshot;

  _HistoryItem({
    required this.id,
    required this.sessionType,
    this.surahNumber,
    required this.title,
    required this.date,
    required this.isInProgress,
    this.snapshot,
  });
}

class _HifzHistoryScreenState extends State<HifzHistoryScreen> {
  final HifzRepository _repo = HifzRepository();
  List<_HistoryItem> _items = [];
  bool _loading = true;
  bool _isSelectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final activeSessions = await _repo.getAllActiveSessions();
    final completedRecords = await _repo.getHistory();

    final List<_HistoryItem> items = [];

    // Convert active sessions (in progress)
    for (final s in activeSessions) {
      String title = '';
      if (s.sessionType == HifzSessionType.newVerses) {
        title = 'Surah ${s.nvSurahNumber} (New Verses)';
      } else {
        final gran = s.reviewGranularity;
        if (gran == ReviewGranularity.bySurah) {
          title = 'Surah ${s.reviewTargetParams?.startSurah ?? 1} (Review)';
        } else if (gran == ReviewGranularity.byVerses) {
          title = 'Surah ${s.reviewTargetParams?.surahNumber ?? 1} (Review)';
        } else {
          title = 'Page ${s.reviewTargetParams?.startPage ?? 1} (Review)';
        }
      }
      items.add(_HistoryItem(
        id: s.sessionId,
        sessionType: s.sessionType,
        surahNumber: s.sessionType == HifzSessionType.newVerses
            ? s.nvSurahNumber
            : (s.reviewTargetParams?.surahNumber ?? s.reviewTargetParams?.startSurah),
        title: title,
        date: DateTime.fromMillisecondsSinceEpoch(s.lastUpdatedTimestamp),
        isInProgress: true,
        snapshot: s,
      ));
    }

    // Convert completed records
    for (final r in completedRecords) {
      items.add(_HistoryItem(
        id: r.id,
        sessionType: r.sessionType,
        surahNumber: r.surahNumber,
        title: r.title,
        date: r.completedAt,
        isInProgress: false,
      ));
    }

    // Sort by date DESC
    items.sort((a, b) => b.date.compareTo(a.date));

    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  String _getLocalizedTitle(_HistoryItem r, bool isThai) {
    if (r.sessionType == HifzSessionType.newVerses) {
      final surah = r.surahNumber ?? 1;
      return isThai ? 'สูเราะฮ์ $surah (อายะห์ใหม่)' : 'Surah $surah (New Verses)';
    } else {
      final surahOrPage = r.surahNumber;
      final isPage = r.title.startsWith('Page');
      if (isPage) {
        final match = RegExp(r'\d+').firstMatch(r.title);
        final pageNum = match != null ? match.group(0) : '1';
        return isThai ? 'หน้า $pageNum (ทบทวน)' : 'Page $pageNum (Review)';
      } else {
        final surah = surahOrPage ?? 1;
        return isThai ? 'สูเราะฮ์ $surah (ทบทวน)' : 'Surah $surah (Review)';
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, _HistoryItem item) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isThai = settings.languageCode == 'th';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: colorScheme.surface,
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 28),
          ),
          title: Text(
            isThai ? 'ลบรายการนี้?' : 'Delete this item?',
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          content: Text(
            isThai
                ? 'คุณแน่ใจหรือไม่ว่าต้องการลบ "${_getLocalizedTitle(item, isThai)}"? การกระทำนี้ไม่สามารถย้อนกลับได้'
                : 'Are you sure you want to delete "${_getLocalizedTitle(item, isThai)}"? This action cannot be undone.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(isThai ? 'ลบ' : 'Delete'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      try {
        if (item.isInProgress) {
          await _repo.clearActiveSession(sessionId: item.id);
        } else {
          await _repo.deleteHistory(item.id);
        }
      } catch (e) {
        debugPrint('Delete failed: $e');
      }
      await _load();
    }
  }

  Future<void> _openInProgress(_HistoryItem r) async {
    if (r.snapshot == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HifzMemorizeScreen(
          quranRepository: widget.quranRepository,
          foundationRepository: widget.foundationRepository,
          resumeSessionSnapshot: r.snapshot,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = Provider.of<SettingsProvider>(context);
    final isThai = settings.languageCode == 'th';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          isThai ? 'ประวัติการฝึกฝน' : 'Practice History',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSelectMode) ...[
            IconButton(
              icon: Icon(
                _selectedIds.length == _items.length && _items.isNotEmpty
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: colorScheme.primary,
              ),
              tooltip: isThai ? 'เลือกทั้งหมด' : 'Select All',
              onPressed: () {
                setState(() {
                  if (_selectedIds.length == _items.length) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds.addAll(_items.map((e) => e.id));
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: colorScheme.error),
              tooltip: isThai ? 'ลบที่เลือก' : 'Delete selected',
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) {
                          final cs = Theme.of(ctx).colorScheme;
                          final tt = Theme.of(ctx).textTheme;
                          return AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            backgroundColor: cs.surface,
                            icon: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.errorContainer.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.delete_sweep_rounded, color: cs.error, size: 28),
                            ),
                            title: Text(
                              isThai ? 'ลบรายการที่เลือก?' : 'Delete selected items?',
                              textAlign: TextAlign.center,
                              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 20),
                            ),
                            content: Text(
                              isThai
                                  ? 'คุณแน่ใจหรือไม่ว่าต้องการลบ ${_selectedIds.length} รายการ? การกระทำนี้ไม่สามารถย้อนกลับได้'
                                  : 'Are you sure you want to delete ${_selectedIds.length} items? This action cannot be undone.',
                              textAlign: TextAlign.center,
                              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            actionsAlignment: MainAxisAlignment.center,
                            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            actions: [
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                                      child: Text(isThai ? 'ลบ' : 'Delete'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                      if (confirmed == true && mounted) {
                        try {
                          final inProgressIds = _items
                              .where((e) => e.isInProgress && _selectedIds.contains(e.id))
                              .map((e) => e.id)
                              .toList();
                          final historyIds = _items
                              .where((e) => !e.isInProgress && _selectedIds.contains(e.id))
                              .map((e) => e.id)
                              .toList();

                          for (final id in inProgressIds) {
                            await _repo.clearActiveSession(sessionId: id);
                          }
                          for (final id in historyIds) {
                            await _repo.deleteHistory(id);
                          }
                        } catch (e) {
                          debugPrint('Bulk delete failed: $e');
                        }
                        setState(() => _selectedIds.clear());
                        await _load();
                      }
                    },
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: colorScheme.onSurfaceVariant),
              tooltip: isThai ? 'ยกเลิกเลือก' : 'Cancel selection',
              onPressed: () {
                setState(() {
                  _isSelectMode = false;
                  _selectedIds.clear();
                });
              },
            ),
          ] else
            IconButton(
              icon: Icon(Icons.checklist_rounded, color: colorScheme.primary),
              tooltip: isThai ? 'เลือก' : 'Select',
              onPressed: () {
                setState(() => _isSelectMode = true);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    isThai ? 'ยังไม่มีประวัติการฝึกฝน' : 'No history recorded yet.',
                    style: textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final r = _items[index];
                    final isNew = r.sessionType == HifzSessionType.newVerses;
                    final isSelected = _selectedIds.contains(r.id);
                    final tile = Container(
                      decoration: BoxDecoration(
                        color: _isSelectMode && isSelected
                            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                            : colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: r.isInProgress && !_isSelectMode
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : isSelected
                                  ? colorScheme.primary.withValues(alpha: 0.5)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
                          width: r.isInProgress && !_isSelectMode ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: _isSelectMode
                            ? Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                size: 28,
                              )
                            : Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isNew
                                      ? colorScheme.primary.withValues(alpha: 0.15)
                                      : colorScheme.tertiary.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isNew ? Icons.menu_book_rounded : Icons.replay_circle_filled_rounded,
                                  color: isNew ? colorScheme.primary : colorScheme.tertiary,
                                ),
                              ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _getLocalizedTitle(r, isThai),
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (r.isInProgress && !_isSelectMode)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colorScheme.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  isThai ? 'กำลังดำเนินการ' : 'In Progress',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            DateFormat.yMMMMEEEEd().add_jm().format(r.date),
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        trailing: _isSelectMode
                            ? null
                            : r.isInProgress
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.play_arrow_rounded,
                                          color: colorScheme.primary, size: 28),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline_rounded,
                                            color: colorScheme.error, size: 18),
                                        tooltip: isThai ? 'ลบ' : 'Delete',
                                        onPressed: () => _confirmDelete(context, r),
                                      ),
                                    ],
                                  )
                                : IconButton(
                                    icon: Icon(Icons.delete_outline_rounded,
                                        color: colorScheme.error, size: 20),
                                    tooltip: isThai ? 'ลบ' : 'Delete',
                                    onPressed: () => _confirmDelete(context, r),
                                  ),
                        onTap: _isSelectMode
                            ? () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedIds.remove(r.id);
                                  } else {
                                    _selectedIds.add(r.id);
                                  }
                                });
                              }
                            : r.isInProgress && r.snapshot != null
                                ? () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => HifzMemorizeScreen(
                                          quranRepository: widget.quranRepository,
                                          foundationRepository: widget.foundationRepository,
                                          resumeSessionSnapshot: r.snapshot,
                                        ),
                                      ),
                                    );
                                    _load();
                                  }
                                : null,
                      ),
                    );

                    if (_isSelectMode) {
                      return tile;
                    }
                    return InkWell(
                      onTap: r.isInProgress && r.snapshot != null
                          ? () => _openInProgress(r)
                          : null,
                      child: tile,
                    );
                  }
                ),
    );
  }
}
