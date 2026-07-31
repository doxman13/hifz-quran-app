// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/supabase_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/local_reading_provider.dart';
import '../providers/mushaf_reading_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/stats_provider.dart';
import '../data/quran_repository.dart';
import 'bookmarks_screen.dart';
import 'reading_screen.dart';
import 'tadabbur_private_screen.dart';
import '../theme/app_theme.dart';
import '../shared/shared.dart';

const String googleLogoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
  <path fill="#4285F4" d="M46.5 24c0-1.61-.15-3.16-.41-4.69H24v9h12.75c-.55 2.81-2.13 5.19-4.5 6.78l7 5.44C43.34 36.36 46.5 30.73 46.5 24z"/>
  <path fill="#FBBC05" d="M10.54 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.98-6.19z"/>
  <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7-5.44c-2.47 1.66-5.63 2.75-8.89 2.75-6.26 0-11.57-4.22-13.46-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>
''';

class ProfileScreen extends StatefulWidget {
  final QuranRepository? repository;

  const ProfileScreen({Key? key, this.repository}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _errorMessage;
  String? _successMessage;
  Future<List<Map<String, dynamic>>>? _reportsFuture;
  String? _fetchedUserId;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _showEditNameDialog(
    BuildContext context,
    SupabaseProvider supabaseProv,
  ) {
    final controller = TextEditingController(text: supabaseProv.displayName);
    final dialogFormKey = GlobalKey<FormState>();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            side: BorderSide(color: colorScheme.outline, width: 1),
          ),
          title: Text(
            context.tr('edit_name'),
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          content: Form(
            key: dialogFormKey,
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(
                labelText: context.tr('name'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  borderSide: BorderSide(color: colorScheme.outline, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  borderSide: BorderSide(color: colorScheme.outline, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return context.tr('please_enter_name');
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                context.tr('cancel'),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                if (!dialogFormKey.currentState!.validate()) return;
                try {
                  await supabaseProv.updateDisplayName(controller.text);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr('name_updated_successfully')),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr('error_occurred', args: {'error': '$e'}),
                        ),
                      ),
                    );
                  }
                }
              },
              child: Text(context.tr('save')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handlePasswordSignIn(SupabaseProvider supabaseProv) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await supabaseProv.signInWithPassword(
        _emailController.text,
        _passwordController.text,
      );
      setState(() {
        _successMessage = context.tr('login_success');
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePasswordSignUp(SupabaseProvider supabaseProv) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await supabaseProv.signUp(
        _emailController.text,
        _passwordController.text,
        _nameController.text,
      );
      setState(() {
        _successMessage = context.tr('register_success');
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSignOut(SupabaseProvider supabaseProv) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await supabaseProv.signOut();
      setState(() {
        _isSignUp = false;
        _emailController.clear();
        _passwordController.clear();
        _nameController.clear();
        _successMessage = context.tr('logout_success');
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleGoogleSignIn(SupabaseProvider supabaseProv) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await supabaseProv.signInWithGoogle();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleManualSync(
    SupabaseProvider supabaseProv,
    SettingsProvider settingsProv,
    LocalReadingProvider readingProv,
    MushafReadingProvider mushafProv,
    NotesProvider notesProv,
    StatsProvider statsProv,
  ) async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await readingProv.flushPendingProfileSyncs();
      await readingProv.flushPendingRecentReadingSync();
      await readingProv.flushPendingReadingStateSync();
      final mushafProfilesFlushed = await mushafProv.flushPendingProfileSyncs();
      if (!mushafProfilesFlushed) {
        throw StateError('Mushaf profile changes are still pending sync.');
      }
      await mushafProv.flushPendingRecentReadingSync();
      await statsProv.flushPendingSave();

      await settingsProv.syncWithSupabase(supabaseProv.userId);
      await readingProv.syncBookmarksAndProfilesWithSupabase(
        supabaseProv.userId,
      );
      await readingProv.syncReadingStateWithSupabase(supabaseProv.userId);
      await mushafProv.syncWithSupabase(supabaseProv.userId);
      await notesProv.syncWithSupabase();
      await statsProv.syncWithSupabase(supabaseProv.userId);
      if (mounted) {
        setState(() {
          _successMessage =
              'ซิงค์ข้อมูลสำเร็จแล้ว (Sync completed successfully!)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'เกิดข้อผิดพลาดในการซิงค์: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  void _openReading(String surahId, String verseId) {
    final repository = widget.repository;
    if (repository == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReadingScreen(
          repository: repository,
          initialSurah: surahId,
          initialVerseId: verseId,
        ),
      ),
    );
  }

  Future<void> _openBookmarks() async {
    final repository = widget.repository;
    if (repository == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookmarksScreen(repository: repository),
      ),
    );
    if (!mounted || result == null) return;

    _openReading(
      result['surahId'].toString(),
      result['verseId']?.toString() ??
          ((result['verseIndex'] as int? ?? 0) + 1).toString(),
    );
  }

  void _openTadabbur() {
    final repository = widget.repository;
    if (repository == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TadabburPrivateScreen(repository: repository),
      ),
    );
  }

  Future<void> _openReadingProfile(LocalReadingProfile profile) async {
    await context.read<LocalReadingProvider>().setActiveProfile(profile.id);
    _openReading(
      profile.furthestUnread.surahId,
      profile.furthestUnread.verseId,
    );
  }

  void _showReadingProfilesSheet(LocalReadingProvider readingProv) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final activeProfiles = readingProv.activeProfiles;
        final archivedProfiles = readingProv.archivedProfiles;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            shrinkWrap: true,
            children: [
              _buildSheetHeader(
                colorScheme,
                'โปรไฟล์การอ่าน',
                '${activeProfiles.length} ใช้งาน / ${archivedProfiles.length} เก็บถาวร',
              ),
              const SizedBox(height: 16),
              if (activeProfiles.isEmpty)
                _buildEmptyState(
                  colorScheme,
                  Icons.menu_book_outlined,
                  'ยังไม่มีแผนการอ่านที่ใช้งาน',
                  'สร้างเป้าหมายการอ่านจากหน้าแรก',
                )
              else
                ...activeProfiles.map(
                  (profile) => _buildProfileRow(
                    colorScheme: colorScheme,
                    title: profile.name,
                    subtitle:
                        '${profile.furthestUnread.surahId}:${profile.furthestUnread.verseId}',
                    icon: isFreeReadProfile(profile)
                        ? Icons.auto_stories_outlined
                        : Icons.flag_outlined,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _openReadingProfile(profile);
                    },
                    trailing: isFreeReadProfile(profile)
                        ? null
                        : IconButton(
                            tooltip: 'Archive',
                            icon: Icon(
                              Icons.archive_outlined,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () async {
                              await readingProv.deleteProfile(profile.id);
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                          ),
                  ),
                ),
              if (archivedProfiles.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildSheetHeader(
                  colorScheme,
                  'รายการที่เก็บถาวร',
                  'ซ่อนจากแผนการอ่านที่ใช้งาน',
                ),
                const SizedBox(height: 12),
                ...archivedProfiles.map(
                  (profile) => _buildProfileRow(
                    colorScheme: colorScheme,
                    title: profile.name,
                    subtitle: 'แผนที่เก็บถาวร',
                    icon: Icons.archive_outlined,
                    onTap: null,
                    trailing: TextButton(
                      onPressed: () async {
                        await readingProv.restoreProfile(profile.id);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      child: const Text('กู้คืน'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showMushafProfilesSheet(MushafReadingProvider mushafProv) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeProfiles = mushafProv.activeCustomProfiles;
    final archivedProfiles =
        mushafProv.profiles
            .where((profile) => !profile.isFreeRead && profile.isArchived)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            shrinkWrap: true,
            children: [
              _buildSheetHeader(
                colorScheme,
                'โปรไฟล์มุศฮัฟ',
                '${activeProfiles.length} ใช้งาน / ${archivedProfiles.length} เก็บถาวร',
              ),
              const SizedBox(height: 16),
              if (activeProfiles.isEmpty)
                _buildEmptyState(
                  colorScheme,
                  Icons.import_contacts_rounded,
                  'ยังไม่มีแผนการอ่านมุศฮัฟ',
                  'สร้างแผนแบบหน้า ซูเราะฮ์ หรือญุซจากหน้าอ่านมุศฮัฟ',
                )
              else
                ...activeProfiles.map(
                  (profile) => _buildProfileRow(
                    colorScheme: colorScheme,
                    title: profile.name,
                    subtitle:
                        'หน้า ${profile.startPage}-${profile.targetPage} / ปัจจุบัน ${profile.furthestUnreadPage}',
                    icon: Icons.import_contacts_rounded,
                    onTap: () async {
                      await mushafProv.setActiveProfile(profile.id);
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                    trailing: IconButton(
                      tooltip: 'Archive',
                      icon: Icon(
                        Icons.archive_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () async {
                        await mushafProv.archiveProfile(profile.id);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                    ),
                  ),
                ),
              if (archivedProfiles.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildSheetHeader(
                  colorScheme,
                  'รายการที่เก็บถาวร',
                  'ซ่อนจากแผนการอ่านมุศฮัฟที่ใช้งาน',
                ),
                const SizedBox(height: 12),
                ...archivedProfiles.map(
                  (profile) => _buildProfileRow(
                    colorScheme: colorScheme,
                    title: profile.name,
                    subtitle: 'หน้า ${profile.startPage}-${profile.targetPage}',
                    icon: Icons.archive_outlined,
                    onTap: null,
                    trailing: Icon(
                      Icons.lock_outline,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final supabaseProv = Provider.of<SupabaseProvider>(context);
    final readingProv = Provider.of<LocalReadingProvider>(context);
    final mushafProv = Provider.of<MushafReadingProvider>(context);
    final notesProv = Provider.of<NotesProvider>(context);
    final statsProv = Provider.of<StatsProvider>(context);
 
    if (supabaseProv.isLoggedIn &&
        (_reportsFuture == null || _fetchedUserId != supabaseProv.userId)) {
      _fetchedUserId = supabaseProv.userId;
      _reportsFuture = _fetchUserReports(supabaseProv.userId);
    }
 
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
 
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 26,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              context.tr('reader_profile'),
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              if (_successMessage != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Text(
                    _successMessage!,
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),

              if (!supabaseProv.isLoggedIn) ...[
                // Guest Profile banner (flat row)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                        child: Icon(
                          Icons.person,
                          color: colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('guest_reader'),
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              supabaseProv.displayName,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.edit_outlined, color: colorScheme.primary, size: 20),
                        onPressed: () =>
                            _showEditNameDialog(context, supabaseProv),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Form Section (Flat layout, no container/card backgrounds, no borders)
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.cloud_sync_outlined,
                            size: 36,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.tr('sync_with_cloud'),
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr('sync_desc'),
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Google sign-in button (Modern layout with soft Google gradient stroke)
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF4285F4), // Google Blue
                              Color(0xFFEA4335), // Google Red
                              Color(0xFFFBBC05), // Google Yellow
                              Color(0xFF34A853), // Google Green
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(1.5),
                        child: Material(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(AppTheme.radius - 1.5),
                          child: InkWell(
                            onTap: _isLoading
                                ? null
                                : () => _handleGoogleSignIn(supabaseProv),
                            borderRadius: BorderRadius.circular(AppTheme.radius - 1.5),
                            child: Container(
                              height: 53, // Adjust so total height with padding is 56px
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.string(
                                    googleLogoSvg,
                                    width: 24, // Bigger logo
                                    height: 24, // Bigger logo
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    context.tr('sign_in_with_google'),
                                    style: textTheme.titleMedium?.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            child: Text(
                              context.tr('or'),
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 24),

                      if (_isSignUp) ...[
                        TextFormField(
                          controller: _nameController,
                          keyboardType: TextInputType.name,
                          decoration: InputDecoration(
                            labelText: context.tr('display_name'),
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radius,
                              ),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return context.tr('please_enter_display_name');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: context.tr('email'),
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radius,
                            ),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return context.tr('please_enter_email');
                          }
                          if (!RegExp(
                            r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                          ).hasMatch(val.trim())) {
                            return context.tr('invalid_email_format');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: context.tr('password'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radius,
                            ),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return context.tr('please_enter_password');
                          }
                          if (val.length < 6) {
                            return context.tr('password_too_short');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radius,
                            ),
                          ),
                        ),
                        onPressed: _isLoading
                            ? null
                            : () {
                                if (_isSignUp) {
                                  _handlePasswordSignUp(supabaseProv);
                                } else {
                                  _handlePasswordSignIn(supabaseProv);
                                }
                              },
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: colorScheme.onPrimary,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isSignUp
                                    ? context.tr('sign_up')
                                    : context.tr('sign_in_with_email'),
                                style: textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimary,
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),

                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isSignUp = !_isSignUp;
                                  _errorMessage = null;
                                  _successMessage = null;
                                });
                              },
                        child: Text(
                          _isSignUp
                              ? context.tr('already_have_account')
                              : context.tr('dont_have_account'),
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Logged in UI - Flat and minimalist (no cards backgrounds or border strokes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.15,
                        ),
                        child: Icon(
                          Icons.person,
                          size: 50,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            supabaseProv.displayName,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: colorScheme.primary,
                            ),
                            onPressed: () =>
                                _showEditNameDialog(context, supabaseProv),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        supabaseProv.userEmail,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _isSyncing
                              ? null
                              : () => _handleManualSync(
                                  supabaseProv,
                                  settings,
                                  readingProv,
                                  mushafProv,
                                  notesProv,
                                  statsProv,
                                ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _isSyncing
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                colorScheme.primary,
                                              ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.sync,
                                        color: colorScheme.primary,
                                        size: 16,
                                      ),
                                const SizedBox(width: 8),
                                Text(
                                  _isSyncing
                                      ? 'กำลังซิงค์ (Syncing...)'
                                      : 'ซิงค์กับคลาวด์แล้ว (Tap to Sync)',
                                  style: textTheme.labelMedium?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Divider(color: colorScheme.outlineVariant, thickness: 1),
                      const SizedBox(height: 24),

                      _buildProfileStatsGroup(
                        title: 'อ่านพร้อมความหมาย',
                        children: [
                          _buildStatCard(
                            icon: Icons.menu_book,
                            title: 'แผนการอ่าน',
                            value: '${readingProv.activeProfiles.length} / 5',
                            color: colorScheme.primary,
                            onTap: () =>
                                _showReadingProfilesSheet(readingProv),
                          ),
                          _buildStatCard(
                            icon: Icons.bookmark,
                            title: 'บุ๊คมาร์ก',
                            value: '${readingProv.bookmarks.length}',
                            color: colorScheme.secondary,
                            onTap: _openBookmarks,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildProfileStatsGroup(
                        title: 'อ่านมุศฮัฟ',
                        children: [
                          _buildStatCard(
                            icon: Icons.import_contacts_rounded,
                            title: 'แผนการอ่าน',
                            value:
                                '${mushafProv.activeCustomProfiles.length}',
                            color: colorScheme.primary,
                            onTap: () => _showMushafProfilesSheet(mushafProv),
                          ),
                          _buildStatCard(
                            icon: Icons.bookmark_added_outlined,
                            title: 'บุ๊คมาร์ก',
                            value:
                                '${mushafProv.pageBookmarks.length + mushafProv.verseBookmarks.length}',
                            color: colorScheme.secondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildProfileStatsGroup(
                        title: 'สถิติและบันทึก',
                        children: [
                          _buildStatCard(
                            icon: Icons.favorite_rounded,
                            title: settings.languageCode == 'en'
                                ? 'My Favourite Ayat'
                                : 'อายะฮฺโปรดของฉัน',
                            value: '${notesProv.personalNotes.length}',
                            color: colorScheme.secondary,
                            onTap: _openTadabbur,
                          ),
                          _buildStatCard(
                            icon: Icons.local_fire_department,
                            title: 'วันอ่านต่อเนื่อง',
                            value: '${statsProv.streakCount} วัน',
                            color: colorScheme.primary,
                          ),
                          _buildReportsCountCard(supabaseProv),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              if (supabaseProv.isLoggedIn) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isLoading
                      ? null
                      : () => _handleSignOut(supabaseProv),
                  icon: const Icon(Icons.logout),
                  label: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: colorScheme.onError,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'ออกจากระบบ (Sign Out)',
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onError,
                          ),
                        ),
                ),
              ],
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileStatsGroup({
    required String title,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: GoogleFonts.notoSansThai(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: children,
        ),
      ],
    );
  }

  Widget _buildReportsCountCard(SupabaseProvider supabaseProv) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _reportsFuture,
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <Map<String, dynamic>>[];
        final value = snapshot.connectionState == ConnectionState.waiting
            ? '...'
            : '${reports.length}';

        return _buildStatCard(
          icon: Icons.report_outlined,
          title: 'รายงานปัญหา',
          value: value,
          color: colorScheme.secondary,
          onTap: () => _showReportsSheet(supabaseProv),
        );
      },
    );
  }

  void _showReportsSheet(SupabaseProvider supabaseProv) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: colorScheme.outline, width: 1),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.86,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _buildReportsSection(supabaseProv),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetHeader(
    ColorScheme colorScheme,
    String title,
    String subtitle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.notoSansThai(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState(
    ColorScheme colorScheme,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansThai(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow({
    required ColorScheme colorScheme,
    required String title,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: colorScheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansThai(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing ??
              Icon(
                Icons.chevron_right,
                color: onTap == null
                    ? colorScheme.outline
                    : colorScheme.onSurfaceVariant,
              ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: row,
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color
    color, // Maintain parameter signature to keep functionality intact
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    // Dynamically derive theme colors based on input color parameters
    // This allows us to use dynamic theme styles without breaking signatures
    Color activeColor = color;
    if (color == Colors.blue ||
        color == Colors.purple ||
        color == Colors.indigo ||
        color == Colors.teal) {
      activeColor = colorScheme.primary;
    } else if (color == Colors.orange ||
        color == Colors.red ||
        color == Colors.deepOrange) {
      activeColor = colorScheme.secondary;
    } else {
      activeColor = colorScheme.primary;
    }

    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: activeColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: activeColor,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        child: card,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchUserReports(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('error_reports')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching user reports: $e');
      return [];
    }
  }

  Widget _buildStatusBadge(String status) {
    final colorScheme = Theme.of(context).colorScheme;
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'reviewed_fixed':
        bgColor = colorScheme.primary.withOpacity(0.15);
        textColor = colorScheme.primary;
        label = 'แก้ไขแล้ว (Fixed)';
        break;
      case 'reviewed_not_needed':
        bgColor = colorScheme.outline.withOpacity(0.15);
        textColor = colorScheme.onSurfaceVariant;
        label = 'ไม่ต้องแก้ไข (No Action)';
        break;
      case 'pending_review':
      default:
        bgColor = colorScheme.secondary.withOpacity(0.15);
        textColor = colorScheme.secondary;
        label = 'รอดำเนินการ (Pending)';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.2), width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSansThai(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildReportsSection(SupabaseProvider supabaseProv) {
    if (!supabaseProv.isLoggedIn) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: colorScheme.outline, width: 1),
      ),
      margin: const EdgeInsets.only(top: 24),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'รายงานข้อผิดพลาด (My Error Reports)',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  onPressed: () {
                    setState(() {
                      _reportsFuture = _fetchUserReports(supabaseProv.userId);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _reportsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                      ),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    'เกิดข้อผิดพลาดในการโหลดข้อมูล (Error loading reports)',
                    style: GoogleFonts.notoSansThai(color: colorScheme.error),
                  );
                }
                final reports = snapshot.data ?? [];
                if (reports.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'ไม่มีประวัติการรายงานข้อผิดพลาด (No error reports submitted yet)',
                      style: GoogleFonts.notoSansThai(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: reports.length,
                  separatorBuilder: (context, index) =>
                      Divider(color: colorScheme.outline, thickness: 1),
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    final surahId = report['surah_id']?.toString() ?? '';
                    final ayahNum = report['ayah_number']?.toString() ?? '';
                    final reportedText =
                        report['reported_verse_text']?.toString() ?? '';
                    final userComment =
                        report['user_comment']?.toString() ?? '';
                    final status =
                        report['status']?.toString() ?? 'pending_review';
                    final adminNotes =
                        report['admin_resolution_notes']?.toString() ?? '';
                    final dateStr = report['created_at']?.toString() ?? '';

                    DateTime? parsedDate;
                    String formattedDate = '';
                    if (dateStr.isNotEmpty) {
                      try {
                        parsedDate = DateTime.parse(dateStr).toLocal();
                        formattedDate =
                            '${parsedDate.day}/${parsedDate.month}/${parsedDate.year} ${parsedDate.hour.toString().padLeft(2, '0')}:${parsedDate.minute.toString().padLeft(2, '0')}';
                      } catch (_) {}
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () => _openReading(surahId, ayahNum),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withOpacity(
                                      0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'อายะฮฺ $surahId:$ayahNum',
                                        style: GoogleFonts.notoSansThai(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.open_in_new,
                                        size: 12,
                                        color: colorScheme.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              _buildStatusBadge(status),
                            ],
                          ),
                          if (formattedDate.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'ข้อความโองการที่รายงาน (Verse text):',
                            style: GoogleFonts.notoSansThai(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            reportedText,
                            softWrap: true,
                            style: GoogleFonts.notoSansThai(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ความคิดเห็นของคุณ (Your comment):',
                            style: GoogleFonts.notoSansThai(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            userComment,
                            softWrap: true,
                            style: GoogleFonts.notoSansThai(
                              fontSize: 13,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (adminNotes.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: colorScheme.primary.withOpacity(0.15),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.admin_panel_settings,
                                        size: 16,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'บันทึกจากผู้ดูแล (Admin Note):',
                                        style: GoogleFonts.notoSansThai(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    adminNotes,
                                    softWrap: true,
                                    style: GoogleFonts.notoSansThai(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
