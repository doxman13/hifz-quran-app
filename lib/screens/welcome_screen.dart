import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main_app_shell.dart';
import '../data/quran_repository.dart';
import '../data/quran_foundation_repository.dart';
import '../providers/settings_provider.dart';
import '../services/remote_content_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../shared/shared.dart';

class WelcomeScreen extends StatefulWidget {
  final QuranRepository repository;
  final QuranFoundationRepository foundationRepository;

  const WelcomeScreen({
    super.key,
    required this.repository,
    required this.foundationRepository,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _minimumWelcomeDuration = Duration(milliseconds: 4200);

  Timer? _fallbackTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _prepareHome();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepareHome() async {
    _fallbackTimer = Timer(const Duration(seconds: 8), () {
      _completeWelcome(repositoryReady: false);
    });

    var repositoryReady = false;
    await Future.wait([
      Future<void>.delayed(_minimumWelcomeDuration),
      _refreshContentThenInitRepository()
          .then((_) {
            repositoryReady = true;
          })
          .catchError((_) {
            repositoryReady = false;
          }),
    ]);

    await _completeWelcome(repositoryReady: repositoryReady);
  }

  Future<void> _refreshContentThenInitRepository() async {
    try {
      await RemoteContentService.instance.updateAllIfDue();
    } catch (error) {
      debugPrint('Unable to auto-check Quran content updates: $error');
    }

    await widget.repository.init();
  }

  Future<void> _completeWelcome({required bool repositoryReady}) async {
    if (_navigated) return;
    _navigated = true;
    _fallbackTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_welcome', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 520),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (context, animation, secondaryAnimation) =>
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
                child: MainAppShell(
                  repository: widget.repository,
                  foundationRepository: widget.foundationRepository,
                ),
              ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0E5C59);
    const textColor = Color(0xFFF5EDDC);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32.0,
                  vertical: 24.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(),

                    // Bismillah SVG
                    SvgPicture.asset(
                      'assets/Bismillah_Calligraphy6.svg',
                      width: 240,
                      colorFilter: const ColorFilter.mode(
                        textColor,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Translation
                    Consumer<SettingsProvider>(
                      builder: (context, settings, _) {
                        final isThai = settings.languageCode == 'th';
                        return Text(
                          context.tr('welcome_bismillah'),
                          style: isThai
                              ? GoogleFonts.notoSansThai(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                )
                              : GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                  letterSpacing: 0.2,
                                ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),

                    const Spacer(),

                    // Logo at the bottom
                    SvgPicture.asset(
                      'assets/logo.svg',
                      height: 128,
                    ),
                     const SizedBox(height: 32),
                  ],
                ),
                ),
               ),
              ),
    );
  }
}
