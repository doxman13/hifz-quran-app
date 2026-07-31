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
import 'hifz_new_verses_setup_screen.dart';
import 'hifz_review_setup_screen.dart';

class HifzLandingScreen extends StatefulWidget {
  final QuranRepository quranRepository;
  final QuranFoundationRepository foundationRepository;

  const HifzLandingScreen({
    super.key,
    required this.quranRepository,
    required this.foundationRepository,
  });

  @override
  State<HifzLandingScreen> createState() => _HifzLandingScreenState();
}

class _HifzLandingScreenState extends State<HifzLandingScreen>
    with SingleTickerProviderStateMixin {
  int _masteredCount = 0;
  int _inProgressCount = 0;
  bool _hasActiveSession = false;
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
      _hasActiveSession = activeSession != null;
      _loading = false;
    });
    _animController.forward();
  }

  Future<void> _openNewVerses() async {
    final prefs = await SharedPreferences.getInstance();
    
    final result = await Navigator.push<NewVersesSetupResult>(
      context,
      MaterialPageRoute(
        builder: (_) => HifzNewVersesSetupScreen(
          quranRepository: widget.quranRepository,
          initialSurah: prefs.getInt('hifz_nv_surah') ?? 1,
          initialStartVerse: prefs.getInt('hifz_nv_start_verse') ?? 1,
          initialEndVerse: prefs.getInt('hifz_nv_end_verse') ?? 3,
          initialPage: prefs.getInt('hifz_nv_page') ?? 1,
          initialIsSurahMode: prefs.getBool('hifz_nv_is_surah_mode') ?? true,
        ),
      ),
    );
    
    if (result != null && mounted) {
      if (result.resumeSnapshot != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HifzMemorizeScreen(
              quranRepository: widget.quranRepository,
              foundationRepository: widget.foundationRepository,
              resumeSessionSnapshot: result.resumeSnapshot,
            ),
          ),
        );
        return;
      }

      await prefs.setInt('hifz_nv_surah', result.surah);
      await prefs.setInt('hifz_nv_start_verse', result.startVerse);
      await prefs.setInt('hifz_nv_end_verse', result.endVerse);
      await prefs.setInt('hifz_nv_page', result.page);
      await prefs.setBool('hifz_nv_is_surah_mode', result.isSurahMode);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HifzMemorizeScreen(
            quranRepository: widget.quranRepository,
            foundationRepository: widget.foundationRepository,
            surahNumber: result.surah,
            startVerse: result.startVerse,
            endVerse: result.endVerse,
            initialSessionType: HifzSessionType.newVerses,
            repeatStart: result.repeatStart,
            initialPage: result.page,
            isSurahMode: result.isSurahMode,
          ),
        ),
      );
    }
  }

  Future<void> _openReview() async {
    final result =
        await Navigator.push<(ReviewGranularity, ReviewTargetParams, ActiveSessionSnapshot?)>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HifzReviewSetupScreen(quranRepository: widget.quranRepository),
      ),
    );
    if (result != null && mounted) {
      final (granularity, params, resumeSnap) = result;
      if (resumeSnap != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HifzMemorizeScreen(
              quranRepository: widget.quranRepository,
              foundationRepository: widget.foundationRepository,
              resumeSessionSnapshot: resumeSnap,
            ),
          ),
        );
        return;
      }
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HifzMemorizeScreen(
            quranRepository: widget.quranRepository,
            foundationRepository: widget.foundationRepository,
            initialSessionType: HifzSessionType.review,
            reviewGranularity: granularity,
            reviewTargetParams: params,
          ),
        ),
      );
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

  void _resumeSession() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HifzMemorizeScreen(
          quranRepository: widget.quranRepository,
          foundationRepository: widget.foundationRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final settings = Provider.of<SettingsProvider>(context);
    final isThai = settings.languageCode == 'th';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // ── Hero Header ─────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: screenHeight * 0.24,
            pinned: true,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeroHeader(colorScheme, textTheme, isThai),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
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

          // ── Resume Banner ───────────────────────────────────────────────────
          if (_hasActiveSession && !_loading)
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _buildResumeBanner(colorScheme, textTheme, isThai),
              ),
            ),

          // ── Mode Title ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Text(
                isThai ? 'เลือกรูปแบบการฝึกฝน' : 'Choose Your Practice',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),

          // ── Mode Cards ──────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                FadeTransition(
                  opacity: _fadeAnim,
                  child: _HifzModeCard(
                    icon: Icons.menu_book_rounded,
                    accentColor: colorScheme.primary,
                    title: 'New Verses (Takrar)',
                    titleThai: 'ท่องอายะห์ใหม่',
                    subtitle: isThai
                        ? 'ฝึกฝนอายะห์ใหม่ด้วยวิธี Gundal — อ่านแบบเปิดเผยและซ่อนอย่างละ 3 รอบ จากนั้นเชื่อมโยงลำดับอายะห์'
                        : 'Practice new verses with the Gundal method — 3 rounds of visible & hidden recitation, then sequence linking.',
                    badge: null,
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
                    title: 'Review Mode',
                    titleThai: 'ทบทวนฮิฟซ์',
                    subtitle: isThai
                        ? 'เสริมสร้างความจำที่เคยท่องจำ ทบทวนรายสูเราะฮ์ ช่วงอายะห์ หรือหน้ามุสฮัฟ ด้วยวงจรเปิดเผย-ซ่อนแบบ 2x/2x'
                        : 'Strengthen memorized content. Review by Surah, Verse range, or Mushaf page with 2×/2× visible-hidden cycle.',
                    badge: _inProgressCount > 0
                        ? (isThai
                            ? 'กำลังดำเนินการ $_inProgressCount เซสชัน'
                            : '$_inProgressCount in progress')
                        : null,
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
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.psychology_alt_rounded,
                  size: 28,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isThai ? 'โหมดท่องจำ' : 'Hifz Memorization',
                style: GoogleFonts.notoSansThai(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onPrimaryContainer,
                  height: 1.2,
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
          : Row(
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
                  icon: Icons.import_contacts_rounded,
                  label: isThai ? 'สูเราะฮ์' : 'Surahs',
                  value: '114',
                  color: colorScheme.secondary,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              ],
            ),
    );
  }

  // ── Resume Banner ────────────────────────────────────────────────────────────
  Widget _buildResumeBanner(ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    return GestureDetector(
      onTap: _resumeSession,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.history_rounded, color: colorScheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isThai ? 'พบเซสชันที่ดำเนินการอยู่' : 'Active session found',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    isThai ? 'แตะเพื่ออ่านต่อจากที่คุณทำค้างไว้' : 'Tap to resume where you left off',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: colorScheme.primary),
          ],
        ),
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
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
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
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
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
                color: colorScheme.onSurfaceVariant,
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
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _pressed
                ? widget.accentColor.withValues(alpha: 0.06)
                : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.accentColor.withValues(alpha: _pressed ? 0.5 : 0.25),
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.12),
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
                              color: cs.tertiary.withValues(alpha: 0.12),
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
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
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
