import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestProfile {
  final int startPage;
  final int targetPage;
  TestProfile({required this.startPage, required this.targetPage});
}

class TestReaderScreen extends StatefulWidget {
  final int initialPage;
  final ValueNotifier<TestProfile?> profileNotifier;

  const TestReaderScreen({
    super.key,
    required this.initialPage,
    required this.profileNotifier,
  });

  @override
  State<TestReaderScreen> createState() => _TestReaderScreenState();
}

class _TestReaderScreenState extends State<TestReaderScreen> {
  late int _pageNumber;
  late PageController _pageController;

  int _pageToIndex(TestProfile? profile, int page) {
    if (profile == null) return (page - 1).clamp(0, 603);
    return (page.clamp(profile.startPage, profile.targetPage)) - profile.startPage;
  }

  @override
  void initState() {
    super.initState();
    final profile = widget.profileNotifier.value;
    _pageNumber = widget.initialPage;
    _pageController = PageController(
      initialPage: _pageToIndex(profile, _pageNumber),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TestProfile?>(
      valueListenable: widget.profileNotifier,
      builder: (context, profile, _) {
        if (profile == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return PageView.builder(
          controller: _pageController,
          itemCount: 604,
          onPageChanged: (index) {
            setState(() {
              _pageNumber = index + profile.startPage;
            });
          },
          itemBuilder: (context, index) {
            return Text('Page ${index + profile.startPage}');
          },
        );
      },
    );
  }
}

void main() {
  testWidgets('Verify fix works when profile loads after initState', (tester) async {
    final profileNotifier = ValueNotifier<TestProfile?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TestReaderScreen(
            initialPage: 50,
            profileNotifier: profileNotifier,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    profileNotifier.value = TestProfile(startPage: 1, targetPage: 604);
    await tester.pumpAndSettle();

    expect(find.text('Page 50'), findsOneWidget);
    expect(find.text('Page 1'), findsNothing);
  });
}
