// lib/screens/hifz_guide_screen.dart
//
// Dedicated comprehensive "How to Hifz" guide screen.
// Explains the step-by-step methodology for both New Verses (Takrar Repetition)
// and Review Mode (Muraja'ah / Sabqi & Manzil), emphasizing that review
// is the core foundation of lifelong Quran retention.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

class HifzGuideScreen extends StatefulWidget {
  final VoidCallback? onStartNewVerses;
  final VoidCallback? onStartReview;

  const HifzGuideScreen({
    super.key,
    this.onStartNewVerses,
    this.onStartReview,
  });

  @override
  State<HifzGuideScreen> createState() => _HifzGuideScreenState();
}

class _HifzGuideScreenState extends State<HifzGuideScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isThai ? 'คู่มือการฮิฟซ์อัลกุรอาน' : 'How to Hifz (Guide)',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: isThai ? 'ปรัชญา' : 'Philosophy'),
            Tab(text: isThai ? 'ท่องจำใหม่' : 'New Verses'),
            Tab(text: isThai ? 'ทบทวน' : 'Review'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPhilosophyTab(colorScheme, textTheme, isThai),
          _buildNewVersesTab(colorScheme, textTheme, isThai),
          _buildReviewTab(colorScheme, textTheme, isThai),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: Philosophy & The Big Picture
  // ---------------------------------------------------------------------------
  Widget _buildPhilosophyTab(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Golden Rule Banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withValues(alpha: 0.7),
                colorScheme.surfaceContainerHighest,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_rounded,
                      color: colorScheme.primary, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    isThai ? 'กฎทองคำแห่งการฮิฟซ์' : 'The Golden Rule of Hifz',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isThai
                    ? '«การรักษาอายะห์เดิม สำคัญกว่าการท่องจำอายะห์ใหม่»'
                    : '“Preserving what you have memorized is far more important than memorizing new verses.”',
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isThai
                    ? 'ผู้ท่องจำส่วนใหญ่ล้มเหลวเพราะคิดว่า "ท่องจบแล้วคือเสร็จ" แต่ความจริงอัลกุรอานหลุดลอยได้เร็วกว่าอูฐที่หลุดจากเชือกผูก หากปราศจากการทบทวนอย่างสม่ำเสมอ อายะห์ใหม่จะเลือนหายไปภายใน 3–7 วัน'
                    : 'Most students struggle because they assume "memorized once = done forever." In reality, the Quran slips away faster than a camel freed from its tether. Without continuous review, new verses fade within 3–7 days.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // The 3 Classical Hifz Pillars
        Text(
          isThai ? '3 เสาหลักของการฮิฟซ์แบบดั้งเดิม' : 'The 3 Classical Pillars of Hifz',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        _PillarCard(
          number: '1',
          icon: Icons.menu_book_rounded,
          accentColor: colorScheme.primary,
          title: isThai ? 'สะบัก (Sabaq) — อายะห์ใหม่' : 'Sabaq (New Lesson)',
          subtitle: isThai
              ? 'การท่องจำอายะห์ใหม่ประจำวัน เช่น วันละ 3–5 อายะห์ หรือ 1 หน้า ใช้สมาธิสูงและเทคนิคตัครอร (Takrar)'
              : 'Daily new verses (e.g. 3–5 ayahs or 1 page). Requires high focus and the Takrar repetition cycle.',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(height: 12),
        _PillarCard(
          number: '2',
          icon: Icons.history_toggle_off_rounded,
          accentColor: colorScheme.tertiary,
          title: isThai ? 'สะบักกี (Sabqi) — ทบทวนอายะห์ล่าสุด' : 'Sabqi (Recent Revision)',
          subtitle: isThai
              ? 'ทบทวนอายะห์ที่ท่องจำไปในช่วง 7–14 วันที่ผ่านมา เพื่อไม่ให้อายะห์ใหม่ที่เพิ่งจำได้เลือนหายไป'
              : 'Reviewing verses memorized over the past 7–14 days to lock them from short-term into long-term memory.',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(height: 12),
        _PillarCard(
          number: '3',
          icon: Icons.all_inclusive_rounded,
          accentColor: colorScheme.secondary,
          title: isThai ? 'มันซิล / ดอร์ (Manzil) — ทบทวนรวม' : 'Manzil (Cumulative Review)',
          subtitle: isThai
              ? 'ทบทวนส่วนที่จำได้แม่นยำแล้วทั้งหมดแบบหมุนเวียนรอบละ 1 ญุซอ์ หรือ 1 สูเราะฮ์ต่อวัน เพื่อรักษาตลอดชีวิต'
              : 'Rotating cumulative review of fully mastered Juz or Surahs (e.g. 1 Juz/day) for lifelong retention.',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(height: 24),

        // Call to action
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _tabController.animateTo(1),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(isThai ? 'ดูวิธีท่องจำใหม่' : 'New Verses Guide'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _tabController.animateTo(2),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text(isThai ? 'ดูวิธีทบทวน' : 'Review Guide'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: New Verses (Takrar Repetition) Method
  // ---------------------------------------------------------------------------
  Widget _buildNewVersesTab(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          isThai ? 'ขั้นตอนการท่องจำอายะห์ใหม่ (วิธีตัครอร Takrar)' : 'New Verses Methodology (Takrar Cycle)',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          isThai
              ? 'ระบบจะแบ่งอายะห์เป็นช่วงๆ และให้คุณอ่านตามวงจรสลับระหว่าง "เปิดเผยตัวอักษร" และ "ซ่อนตัวอักษรเพื่อทดสอบความจำ"'
              : 'The system breaks down verses into manageable chunks and guides you through alternating visible & hidden active recall.',
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),

        _StepGuideCard(
          step: '1',
          icon: Icons.hearing_rounded,
          title: isThai ? 'ฟังเสียงและเข้าใจความหมาย' : 'Listen & Comprehend First',
          description: isThai
              ? 'ก่อนเริ่มท่องจำ ให้กดฟังเสียงผู้อ่านเพื่อตรวจสอบการออกเสียง ตัวสะกด และจุดหยุดพัก (วักฟ์) ที่ถูกต้องเสมอ'
              : 'Always listen to the audio recitation first to lock in correct tajweed, vowel endings, and Waqf stops.',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(height: 12),

        _StepGuideCard(
          step: '2',
          icon: Icons.visibility_rounded,
          title: isThai ? 'รอบเปิดเผย (Visible) — สร้างภาพจำ' : 'Visible Rounds (10x) — Visual Memory',
          description: isThai
              ? 'อ่านออกเสียงพร้อมมองตัวอักษรในมุสฮัฟ 10 ครั้ง เพื่อให้สมองและดวงตาจดจำตำแหน่งคำและความยาวของประโยค'
              : 'Recite aloud while looking at the Mushaf text 10 times. This builds visual and muscle memory.',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(height: 12),

        _StepGuideCard(
          step: '3',
          icon: Icons.visibility_off_rounded,
          title: isThai ? 'รอบซ่อน (Hidden) — ดึงความจำเชิงรุก' : 'Hidden Rounds (5x) — Active Recall',
          description: isThai
              ? 'ตัวอักษรจะถูกซ่อนไว้ ให้ท่องจำจากความจำ 5 ครั้ง หากติดขัดสามารถแตะเพื่อแอบดู (Peek) หรือขอคำใบ้คำแรกได้'
              : 'The text disappears. Recite 5 times entirely from memory. Tap peek or use hint if you get stuck.',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(height: 12),

        _StepGuideCard(
          step: '4',
          icon: Icons.link_rounded,
          title: isThai ? 'การเชื่อมโยงลำดับ (Linked Sequence)' : 'Linked Sequence — Seamless Transitions',
          description: isThai
              ? 'เมื่อท่องจำอายะห์ที่ 1 และ 2 ได้แล้ว ระบบจะเชื่อมโยงให้อ่าน 1 ➔ 2 ต่อเนื่องกัน เพื่อไม่ให้สะดุดตรงรอยต่อของอายะห์'
              : 'After memorizing Verse 1 & 2 individually, the system links 1 ➔ 2 together so your memory flows without pausing.',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(height: 20),

        // Session Linking Strategy Section (Session 1 vs Session 2)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.cable_rounded,
                        color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isThai
                              ? 'เทคนิคการตั้งค่าช่วงอายะห์แบบลูกโซ่'
                              : 'The Linking Chain Strategy',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          isThai
                              ? 'ป้องกันการจำแบบ "เกาะเดี่ยว" ที่เชื่อมต่อไม่ได้'
                              : 'Connecting consecutive sessions seamlessly',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                isThai
                    ? 'ปัญหาที่พบบ่อยที่สุด: ผู้ท่องจำมักจำอายะห์ 1–10 ได้ และจำอายะห์ 11–20 ได้ แต่พอลองอ่านต่อกัน 1–20 จะ "สะดุดหรือนึกไม่ออกตรงรอยต่อระหว่างอายะห์ 10 ไป 11" เสมอ!'
                    : 'The most common Hifz obstacle: A student memorizes Ayahs 1–10 and then 11–20 separately, but freezes at the junction when trying to flow from Ayah 10 into 11!',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),

              // Visual Example Cards: Session 1 vs Session 2
              _buildSessionChainExample(
                sessionNumber: '1',
                dayLabel: isThai ? 'เซสชันที่ 1 (เช่น วันที่ 1)' : 'Session 1 (e.g. Day 1)',
                rangeText: isThai ? 'ช่วง: 1 – 10' : 'Range: 1 – 10',
                repeatText: isThai
                    ? 'เริ่มเชื่อมจาก: 1'
                    : 'Repeat Start: 1',
                outcomeText: isThai
                    ? 'ท่องอายะห์ 1 ถึง 10 จนคล่อง และอ่านเชื่อม 1 ➔ 10 จบรอบ'
                    : 'Memorize 1 to 10 and cement the chain from 1 ➔ 10.',
                isHighlight: false,
                colorScheme: colorScheme,
                textTheme: textTheme,
                isThai: isThai,
              ),
              const SizedBox(height: 12),
              _buildSessionChainExample(
                sessionNumber: '2',
                dayLabel: isThai ? 'เซสชันที่ 2 (เช่น วันที่ 2 — หัวใจสำคัญ!)' : 'Session 2 (e.g. Day 2 — Crucial!)',
                rangeText: isThai ? 'ช่วง: 11 – 20' : 'Range: 11 – 20',
                repeatText: isThai
                    ? 'เริ่มเชื่อมจาก: 1 (ไม่ใช่ 11!)'
                    : 'Repeat Start: 1 (NOT 11!)',
                outcomeText: isThai
                    ? 'เมื่อท่องจำอายะห์ใหม่ 11–20 ระบบจะดึงให้ทบทวนเชื่อมตั้งแต่ 1 ➔ 11, 1 ➔ 12 จนถึง 1 ➔ 20 ทำให้รอยต่อระหว่างเมื่อวานกับวันนี้ถูกเชื่อมกันอย่างสมบูรณ์แบบ!'
                    : 'While acquiring 11–20, each link step tests 1 ➔ 11, 1 ➔ 12... up to 1 ➔ 20. The yesterday-to-today junction is permanently fused!',
                isHighlight: true,
                colorScheme: colorScheme,
                textTheme: textTheme,
                isThai: isThai,
              ),

              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.secondary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline_rounded,
                        color: colorScheme.secondary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isThai
                            ? '💡 จุดเช็คพอยต์: หากซูเราะฮ์ยาวมาก (เช่น อัลบะเกาะเราะฮ์) สามารถตั้งค่า Repeat Start ย้อนกลับไปที่ "ต้นหน้า" หรือ "ต้นรุกูอ์" แทนที่จะเริ่มจากอายะห์ 1 เสมอไป'
                            : '💡 Pro-Tip for Long Surahs: In lengthy surahs (e.g. Al-Baqarah), you can set Repeat Start back to the top of the Page or Ruku\' rather than Ayah 1 indefinitely.',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Action CTA
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            widget.onStartNewVerses?.call();
          },
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(isThai ? 'เริ่มท่องจำอายะห์ใหม่ตอนนี้' : 'Start New Verses Session'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: Review Mode (Muraja'ah) Method
  // ---------------------------------------------------------------------------
  Widget _buildReviewTab(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Alert Box: The Importance of Review
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: colorScheme.error, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isThai ? 'อย่าละเลยการทบทวน!' : 'Never Skip Review Mode!',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isThai
                          ? 'ทันทีที่คุณท่องอายะห์ใหม่จบ ให้ทบทวนซ้ำทันทีภายใน 24 ชั่วโมง และทบทวนอย่างน้อย 3 รอบเพื่อเปลี่ยนเป็นสถานะ "เชี่ยวชาญ (Mastered)"'
                          : 'As soon as you finish new verses, review them within 24 hours. A surah must be reviewed at least 3 times to achieve "Mastered" status.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Text(
          isThai ? 'วงจรทบทวนแบบ 2x/2x ในแอป' : 'The 2x/2x Review Cycle in HifzSpace',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        _StepGuideCard(
          step: '1',
          icon: Icons.check_circle_outline_rounded,
          title: isThai ? '2 รอบแบบเปิดเผย (Visible Accuracy Check)' : '2x Visible — Accuracy & Tajweed Check',
          description: isThai
              ? 'อ่านโดยมองตัวอักษร 2 รอบเพื่อยืนยันว่าสระ พยัญชนะ และจุดหยุดพักไม่มีจุดผิดพลาดตกหล่น'
              : 'Recite with text visible 2 times to verify zero vowel errors, tajweed slips, or missing words.',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(height: 12),

        _StepGuideCard(
          step: '2',
          icon: Icons.lock_outline_rounded,
          title: isThai ? '2 รอบแบบซ่อนสนิท (Hidden Retention Lock)' : '2x Hidden — Pure Memory Verification',
          description: isThai
              ? 'ตัวอักษรจะถูกซ่อนทั้งหมด อ่านจากความจำ 2 รอบเพื่อยืนยันว่าข้อมูลถูกบันทึกลงในความจำระยะยาวอย่างแท้จริง'
              : 'Text is fully hidden. Recite twice purely from heart to prove it is locked in long-term retention.',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(height: 20),

        // Routine Schedule Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isThai ? 'ตารางเวลาการทบทวนที่แนะนำ' : 'Recommended Review Routine',
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _RoutineRow(
                time: isThai ? 'ทันทีหลังจำใหม่' : 'Immediately',
                task: isThai ? 'ทบทวนอายะห์ใหม่ 1 รอบเต็ม' : '1 full review of new verses',
                colorScheme: colorScheme,
              ),
              _RoutineRow(
                time: isThai ? 'วันถัดไป' : 'Next Day',
                task: isThai ? 'ทบทวนสะบักกี (Verses 7 วันล่าสุด)' : 'Sabqi review (last 7 days of verses)',
                colorScheme: colorScheme,
              ),
              _RoutineRow(
                time: isThai ? 'ประจำสัปดาห์' : 'Weekly',
                task: isThai ? 'ทบทวนมันซิล (1 สูเราะฮ์ หรือ 1 ญุซอ์)' : 'Manzil review (1 full Surah or Juz)',
                colorScheme: colorScheme,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Action CTA
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            widget.onStartReview?.call();
          },
          icon: const Icon(Icons.replay_rounded),
          label: Text(isThai ? 'เริ่มเซสชันทบทวนตอนนี้' : 'Start Review Session'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: colorScheme.tertiary,
            foregroundColor: colorScheme.onTertiary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionChainExample({
    required String sessionNumber,
    required String dayLabel,
    required String rangeText,
    required String repeatText,
    required String outcomeText,
    required bool isHighlight,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required bool isThai,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHighlight
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlight
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isHighlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isHighlight
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  sessionNumber,
                  style: textTheme.labelMedium?.copyWith(
                    color: isHighlight
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dayLabel,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isHighlight ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Text(
                  rangeText,
                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.link_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isHighlight
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isHighlight
                          ? colorScheme.primary.withValues(alpha: 0.6)
                          : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    repeatText,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isHighlight
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            outcomeText,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Helper Widgets
// -----------------------------------------------------------------------------

class _PillarCard extends StatelessWidget {
  final String number;
  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _PillarCard({
    required this.number,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepGuideCard extends StatelessWidget {
  final String step;
  final IconData icon;
  final String title;
  final String description;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _StepGuideCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.description,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              step,
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineRow extends StatelessWidget {
  final String time;
  final String task;
  final ColorScheme colorScheme;

  const _RoutineRow({
    required this.time,
    required this.task,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              time,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              task,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
