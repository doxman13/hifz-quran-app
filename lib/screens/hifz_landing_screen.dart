// lib/screens/hifz_landing_screen.dart
//
// Landing page for Hifz (Memorization) Mode.
// Provides entry points to New Verses, Review Mode and Mastery Progress.
// No business logic — delegates to HifzMemorizeScreen / setup screens.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../database/hifz_repository.dart';
import '../models/hifz_session_config.dart';
import '../providers/settings_provider.dart';
import 'hifz_history_screen.dart';
import 'hifz_mastery_list_screen.dart';
import 'hifz_settings_screen.dart';
import 'hifz_memorize_screen.dart';
import 'hifz_guide_screen.dart';
import 'hifz_wizard_setup_screen.dart';
import 'hifz_review_setup_screen.dart';

class HifzLandingScreen extends StatefulWidget {
  final QuranRepository quranRepository;
  final QuranFoundationRepository foundationRepository;
  final bool isEmbedded;

  const HifzLandingScreen({
    super.key,
    required this.quranRepository,
    required this.foundationRepository,
    this.isEmbedded = false,
  });

  @override
  State<HifzLandingScreen> createState() => _HifzLandingScreenState();
}

class _HifzLandingScreenState extends State<HifzLandingScreen>
    with SingleTickerProviderStateMixin {
  int _masteredCount = 0;
  int _inProgressCount = 0;
  bool _hasActiveSession = false;
  ActiveSessionSnapshot? _activeSessionSnapshot;
  bool _loading = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _loadStats();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final repo = HifzRepository();
    final records = await repo.getAllCompletionRecords();
    final activeSession = await repo.loadActiveSession();
    if (!mounted) return;
    setState(() {
      _masteredCount = records.where((r) => r.newVersesCompleted && r.reviewCount >= 3).length;
      _inProgressCount =
          records.where((r) => r.newVersesCompleted || r.reviewCount > 0).length;
      _activeSessionSnapshot = activeSession;
      _hasActiveSession = activeSession != null;
      _loading = false;
    });
    _animController.forward();
  }

  Future<void> _openNewVerses() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HifzWizardSetupScreen(
          quranRepository: widget.quranRepository,
          foundationRepository: widget.foundationRepository,
          initialMode: HifzSessionType.newVerses,
          initialSurah: prefs.getInt('hifz_nv_surah') ?? 67,
          initialStartVerse: prefs.getInt('hifz_nv_start_verse') ?? 1,
          initialEndVerse: prefs.getInt('hifz_nv_end_verse') ?? 5,
          initialRepeatStart: prefs.getInt('hifz_nv_repeat_start') ?? 1,
          initialStep: 1,
        ),
      ),
    );
    if (mounted) {
      _loadStats();
    }
  }

  Future<void> _openReview() async {
    await Navigator.push<(ReviewGranularity, ReviewTargetParams, ActiveSessionSnapshot?)>(
      context,
      MaterialPageRoute(
        builder: (_) => HifzReviewSetupScreen(
          quranRepository: widget.quranRepository,
          foundationRepository: widget.foundationRepository,
        ),
      ),
    );
    if (mounted) {
      _loadStats();
    }
  }

  Future<void> _openWizard() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HifzWizardSetupScreen(
          quranRepository: widget.quranRepository,
          foundationRepository: widget.foundationRepository,
          initialRepeatStart: prefs.getInt('hifz_nv_repeat_start') ?? 1,
          initialStep: 0,
        ),
      ),
    );
    if (mounted) {
      _loadStats();
    }
  }

  void _openMastery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HifzMasteryListScreen(quranRepository: widget.quranRepository),
      ),
    );
  }

  void _openGuide() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HifzGuideScreen(
          onStartNewVerses: _openNewVerses,
          onStartReview: _openReview,
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HifzHistoryScreen(
          quranRepository: widget.quranRepository,
          foundationRepository: widget.foundationRepository,
        ),
      ),
    );
  }

  Future<void> _resumeSession() async {
    final snap = _activeSessionSnapshot ?? await HifzRepository().loadActiveSession();
    if (snap == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HifzMemorizeScreen(
          quranRepository: widget.quranRepository,
          foundationRepository: widget.foundationRepository,
          resumeSessionSnapshot: snap,
        ),
      ),
    );
    if (mounted) {
      _loadStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = Provider.of<SettingsProvider>(context);
    final isThai = settings.languageCode == 'th';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero Header ─────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 150,
            pinned: true,
            foregroundColor: colorScheme.onSurface,
            backgroundColor: colorScheme.surface,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeroHeader(colorScheme, textTheme, isThai),
            ),
            leading: (widget.isEmbedded || !Navigator.canPop(context))
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline_rounded),
                tooltip: isThai ? 'คู่มือการท่องจำ' : 'How to Hifz Guide',
                onPressed: _openGuide,
              ),
              IconButton(
                icon: const Icon(Icons.history_rounded),
                tooltip: isThai ? 'ประวัติ' : 'History',
                onPressed: _openHistory,
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: isThai ? 'ตั้งค่า' : 'Settings',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HifzSettingsScreen())),
              ),
            ],
          ),

          // ── Stats Strip ─────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _buildStatsStrip(colorScheme, textTheme, isThai),
            ),
          ),

          // ── Resume Hero Banner ──────────────────────────────────────────────
          if (_hasActiveSession && !_loading)
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _buildResumeBanner(colorScheme, textTheme, isThai),
              ),
            ),

          // ── How-To Guide Teaser ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _buildGuideTeaserBanner(colorScheme, textTheme, isThai),
            ),
          ),

          // ── Mode Title ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  Text(
                    isThai ? 'โหมดการฝึกฝน' : 'Practice Modes',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    isThai ? 'ท่องใหม่ 20% · ทบทวน 80%' : '20% New · 80% Review',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Mode Cards ──────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Guided 3-Step Wizard Entry Banner ──────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: InkWell(
                    onTap: _openWizard,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colorScheme.primary,
                            colorScheme.primary.withValues(alpha: 0.85),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.auto_fix_high_rounded,
                              size: 28,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      isThai
                                          ? 'เริ่มต้นทีละขั้นตอน'
                                          : 'Step-by-Step Setup',
                                      style: GoogleFonts.notoSansThai(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isThai ? '3 ขั้นตอน' : '3 Steps',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isThai
                                      ? 'เลือกเป้าหมาย ──> กำหนดช่วง ──> เริ่มท่องทันที'
                                      : 'Select goal ──> set range ──> start session',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                FadeTransition(
                  opacity: _fadeAnim,
                  child: _HifzModeCard(
                    icon: Icons.menu_book_rounded,
                    accentColor: colorScheme.primary,
                    title: 'New Verses (Takrar)',
                    titleThai: 'ท่องจำอายะห์ใหม่ (Takrar)',
                    subtitle: isThai
                        ? 'ท่องจำอายะห์ใหม่ด้วยวิธีตัครอร (Takrar) — สลับเปิดเผย 10x และซ่อน 5x เพื่อสร้างภาพจำลงสมอง'
                        : 'Memorize new verses with the Takrar repetition method — 10x visible & 5x hidden active recall.',
                    badge: null,
                    tags: isThai
                        ? ['วงจรตัครอร 10V + 5H', 'แบ่งย่อยอายะห์ตามวักฟ์', 'เชื่อมโยงลำดับ']
                        : ['10V + 5H Takrar Cycle', 'Waqf Chunking', 'Sequence Linking'],
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                    onTap: _openNewVerses,
                  ),
                ),
                const SizedBox(height: 12),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: _HifzModeCard(
                    icon: Icons.replay_circle_filled_rounded,
                    accentColor: colorScheme.tertiary,
                    title: 'Review Mode (Muraja\'ah)',
                    titleThai: 'ทบทวนฮิฟซ์ (Muraja\'ah)',
                    subtitle: isThai
                        ? 'หัวใจของการฮิฟซ์! รักษาสิ่งที่เคยท่องจำไม่ให้เลือนหาย ด้วยวงจรเปิดเผย-ซ่อนแบบ 2x/2x'
                        : 'The heart of Hifz! Protect memorized portions with the 2x/2x visible-hidden cycle.',
                    badge: _inProgressCount > 0
                        ? (isThai
                            ? 'กำลังดำเนินการ $_inProgressCount'
                            : '$_inProgressCount active')
                        : null,
                    tags: isThai
                        ? ['วงจร 2x/2x ล็อกความจำ', 'หัวใจสำคัญ 80%', 'ทบทวนสะบักกี & มันซิล']
                        : ['2x/2x Retention Lock', 'Essential 80%', 'Sabqi & Manzil'],
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                    onTap: _openReview,
                  ),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),

          // ── Mastery Section ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _buildMasteryTile(colorScheme, textTheme, isThai),
              ),
            ),
          ),

          // ── History Section ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: _buildHistoryTile(colorScheme, textTheme, isThai),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Header ─────────────────────────────────────────────────────────────
  Widget _buildHeroHeader(ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.6),
            colorScheme.secondaryContainer.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.psychology_alt_rounded,
                  size: 26,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      isThai ? 'ศูนย์รวมการท่องจำ' : 'Hifz Command Center',
                      style: GoogleFonts.notoSansThai(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      isThai
                          ? 'ฝึกฝนอายะห์ใหม่ & รักษาการท่องจำด้วยการทบทวน'
                          : 'Master new verses & protect retention with review',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Stats Strip ─────────────────────────────────────────────────────────────
  Widget _buildStatsStrip(ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    final progress = _masteredCount / 114;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: _loading
          ? const Center(
              child: SizedBox(
                height: 36,
                width: 36,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              children: [
                Row(
                  children: [
                    _StatPill(
                      icon: Icons.military_tech_rounded,
                      label: isThai ? 'เชี่ยวชาญ' : 'Mastered',
                      value: '$_masteredCount',
                      color: colorScheme.primary,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    ),
                    _VertDivider(colorScheme: colorScheme),
                    _StatPill(
                      icon: Icons.trending_up_rounded,
                      label: isThai ? 'กำลังฝึก' : 'In Progress',
                      value: '$_inProgressCount',
                      color: colorScheme.tertiary,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    ),
                    _VertDivider(colorScheme: colorScheme),
                    _StatPill(
                      icon: Icons.pie_chart_rounded,
                      label: isThai ? 'ความสำเร็จ' : 'Quran Mastery',
                      value: '${(progress * 100).toStringAsFixed(1)}%',
                      color: colorScheme.secondary,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor:
                        colorScheme.outlineVariant.withValues(alpha: 0.3),
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
    );
  }

  // ── Guide Teaser Banner ─────────────────────────────────────────────────────
  Widget _buildGuideTeaserBanner(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    return GestureDetector(
      onTap: _openGuide,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.tertiary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.school_rounded,
                  color: colorScheme.tertiary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isThai
                        ? 'คู่มือการท่องจำ: ทำไมการทบทวนถึงสำคัญที่สุด?'
                        : 'How to Hifz: Why Review is 80% of Retention',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isThai
                        ? 'เรียนรู้วงจรตัครอร (Takrar) และระบบทบทวน 2x/2x แตะเพื่ออ่านคู่มือ'
                        : 'Learn the Takrar repetition cycle & 2x/2x review system. Tap to view.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _getResumeSessionSubtitle(ActiveSessionSnapshot snap, bool isThai) {
    if (snap.sessionType == HifzSessionType.newVerses) {
      final surah = snap.nvSurahNumber ?? 1;
      final start = snap.nvStartVerse ?? 1;
      final end = snap.nvEndVerse ?? 1;
      final task = snap.currentStepIndex + 1;
      if (isThai) {
        return 'สูเราะฮ์ $surah:$start-$end • งานที่ $task • แตะเพื่อทำต่อ';
      } else {
        return 'Surah $surah:$start-$end • Task $task • Tap to resume';
      }
    } else {
      final gran = snap.reviewGranularity ?? ReviewGranularity.bySurah;
      final step = snap.currentStepIndex + 1;
      final mode = snap.currentMode == 'hidden'
          ? (isThai ? 'ซ่อน' : 'Hidden')
          : (isThai ? 'แสดง' : 'Visible');
      if (gran == ReviewGranularity.bySurah) {
        final surah = snap.reviewTargetParams?.startSurah ?? 1;
        if (isThai) {
          return 'ทบทวน สูเราะฮ์ $surah • ขั้นตอน $step ($mode) • แตะเพื่อทำต่อ';
        } else {
          return 'Review Surah $surah • Step $step ($mode) • Tap to resume';
        }
      } else if (gran == ReviewGranularity.byVerses) {
        final surah = snap.reviewTargetParams?.surahNumber ?? 1;
        final start = snap.reviewTargetParams?.startVerse ?? 1;
        final end = snap.reviewTargetParams?.endVerse ?? 1;
        if (isThai) {
          return 'ทบทวน สูเราะฮ์ $surah:$start-$end • ขั้นตอน $step • แตะเพื่อทำต่อ';
        } else {
          return 'Review Surah $surah:$start-$end • Step $step • Tap to resume';
        }
      } else {
        final page = snap.reviewTargetParams?.startPage ?? 1;
        if (isThai) {
          return 'ทบทวน หน้า $page • ขั้นตอน $step • แตะเพื่อทำต่อ';
        } else {
          return 'Review Page $page • Step $step • Tap to resume';
        }
      }
    }
  }

  // ── Resume Banner ────────────────────────────────────────────────────────────
  Widget _buildResumeBanner(ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    final subtitle = _activeSessionSnapshot != null
        ? _getResumeSessionSubtitle(_activeSessionSnapshot!, isThai)
        : (isThai ? 'แตะเพื่ออ่านต่อจากที่คุณทำค้างไว้' : 'Tap to resume where you left off');

    final isNewVerses =
        _activeSessionSnapshot?.sessionType == HifzSessionType.newVerses;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_circle_filled_rounded,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      isThai
                          ? (isNewVerses ? 'เซสชันท่องจำค้างอยู่' : 'เซสชันทบทวนค้างอยู่')
                          : (isNewVerses ? 'Active New Verses' : 'Active Review'),
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                isThai ? 'ทำค้างไว้' : 'In Progress',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _resumeSession,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(isThai ? 'ทำต่อจากจุดเดิม' : 'Resume Session Now'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── History Tile ─────────────────────────────────────────────────────────────
  Widget _buildHistoryTile(ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    return GestureDetector(
      onTap: _openHistory,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.history_rounded, color: colorScheme.tertiary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isThai ? 'ประวัติการฝึกฝน' : 'Practice History',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    isThai ? 'ดูเซสชันที่ผ่านมาและบันทึกการท่องจำ' : 'View past sessions & memorization logs',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Mastery Tile ─────────────────────────────────────────────────────────────
  Widget _buildMasteryTile(ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    final progress = _masteredCount / 114;
    return GestureDetector(
      onTap: _openMastery,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_rounded,
                    color: colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Text(
                  isThai ? 'ความคืบหน้าการท่องจำ' : 'Mastery Progress',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  isThai ? '$_masteredCount / 114 สูเราะฮ์' : '$_masteredCount / 114 Surahs',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isThai
                  ? '${(progress * 100).toStringAsFixed(1)}% ของอัลกุรอานทั้งหมดถูกท่องจำแล้ว'
                  : '${(progress * 100).toStringAsFixed(1)}% of full Quran memorized',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _HifzModeCard ─────────────────────────────────────────────────────────────
class _HifzModeCard extends StatefulWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String titleThai;
  final String subtitle;
  final String? badge;
  final List<String>? tags;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onTap;

  const _HifzModeCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.titleThai,
    required this.subtitle,
    required this.badge,
    this.tags,
    required this.colorScheme,
    required this.textTheme,
    required this.onTap,
  });

  @override
  State<_HifzModeCard> createState() => _HifzModeCardState();
}

class _HifzModeCardState extends State<_HifzModeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final tt = widget.textTheme;
    final settings = Provider.of<SettingsProvider>(context);
    final isThai = settings.languageCode == 'th';
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _pressed
                ? widget.accentColor.withValues(alpha: 0.08)
                : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _pressed
                  ? widget.accentColor.withValues(alpha: 0.4)
                  : cs.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(widget.icon, color: widget.accentColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isThai ? widget.titleThai : widget.title,
                            style: GoogleFonts.notoSansThai(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (widget.badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.tertiary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              widget.badge!,
                              style: tt.labelSmall?.copyWith(
                                color: cs.tertiary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    if (widget.tags != null && widget.tags!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: widget.tags!.map((t) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: widget.accentColor.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            t,
                            style: tt.labelSmall?.copyWith(
                              color: widget.accentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 10.5,
                            ),
                          ),
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  final ColorScheme colorScheme;
  const _VertDivider({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 48,
      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}
