import 'dart:io';

void main() {
  final file = File('lib/screens/hifz_memorize_screen.dart');
  var content = file.readAsStringSync();

  // 1. Fix Peek gesture (replace all occurrences of onLongPressCancel to also include onLongPressUp and onPointerUp)
  content = content.replaceAll(
    'onLongPressCancel: () => provider.setPeekActive(false),',
    'onLongPressCancel: () => provider.setPeekActive(false),\n                                                    onLongPressUp: () => provider.setPeekActive(false),\n                                                    onTapUp: (_) => provider.setPeekActive(false),',
  );

  content = content.replaceAll(
    'onLongPressCancel: isHidden\n                                          ? () => provider.setPeekActive(false)\n                                          : null,',
    'onLongPressCancel: isHidden\n                                          ? () => provider.setPeekActive(false)\n                                          : null,\n                                      onLongPressUp: isHidden ? () => provider.setPeekActive(false) : null,\n                                      onTapUp: isHidden ? (_) => provider.setPeekActive(false) : null,',
  );

  // 2. Remove Tap Anywhere wrapper
  content = content.replaceAll(
'''                Positioned.fill(
                  child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (!provider.isSessionCompleted) {
                  provider.incrementProgress();
                  HapticFeedback.lightImpact();
                }
              },
              child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: [''',
'''                Positioned.fill(
                  child: Column(
                    children: ['''
  );

  content = content.replaceAll(
'''                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
            bottomNavigationBar: Container(''',
'''                    ],
                  ),
                ),
      ],
    ),
            bottomNavigationBar: Container('''
  );

  // 3. Fix bottom bar (remove report button, make tally expanded)
  content = content.replaceAll(
'''                      Row(
                        children: [

                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _showGundalReportModal(context, provider),
                              icon: const Icon(Icons.assessment_outlined),
                              label: const Text('Session Report'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => provider.incrementProgress(),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Tally (+1)'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),''',
'''                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => provider.incrementProgress(),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Tally (+1)'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),'''
  );

  // 4. Add audio button to AppBar
  content = content.replaceAll(
'''              actions: [
                IconButton(
                  icon: const Icon(Icons.tune_outlined),''',
'''              actions: [
                IconButton(
                  icon: const Icon(Icons.play_circle_outline),
                  tooltip: 'Play Range',
                  onPressed: () {
                    final audio = context.read<MushafAudioProvider>();
                    if (provider.currentTask != null) {
                      // Just play the first verse of the target for simplicity, or we could queue it.
                      audio.playSingleIndependentVerse('\${widget.surahNumber}:\${provider.currentTask!.verseNumbers.first}');
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.tune_outlined),'''
  );

  // 5. Update ListView to use Uthmani font and inline play button
  content = content.replaceAll(
'''                                          text: TextSpan(
                                            style: textTheme.bodyLarge?.copyWith(
                                              fontSize: 22,
                                              height: 1.8,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: 'Verse \$verseNum: ',
                                                style: TextStyle(
                                                  color: isTarget ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              TextSpan(
                                                text: qcf.getVerse(widget.surahNumber, verseNum),
                                                style: TextStyle(
                                                  color: isHidden
                                                      ? Colors.transparent
                                                      : (isTarget ? null : textTheme.bodyLarge?.color?.withValues(alpha: 0.4)),
                                                ),
                                              ),
                                            ],
                                          ),''',
'''                                          text: TextSpan(
                                            style: textTheme.bodyLarge?.copyWith(
                                              fontFamily: 'UthmanicHafs',
                                              fontSize: 28,
                                              height: 1.8,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: qcf.getVerse(widget.surahNumber, verseNum) + ' ' + _toArabicVerseNumber(verseNum),
                                                style: TextStyle(
                                                  color: isHidden
                                                      ? Colors.transparent
                                                      : (isTarget ? null : textTheme.bodyLarge?.color?.withValues(alpha: 0.4)),
                                                ),
                                              ),
                                            ],
                                          ),'''
  );
  
  content = content.replaceAll(
'''                                        child: RichText(
                                          textAlign: TextAlign.right,
                                          text: TextSpan(''',
'''                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (!isHidden)
                                              IconButton(
                                                icon: const Icon(Icons.volume_up_outlined),
                                                onPressed: () {
                                                  context.read<MushafAudioProvider>().playSingleIndependentVerse('\${widget.surahNumber}:\$verseNum');
                                                },
                                              ),
                                            Expanded(
                                              child: RichText(
                                                textAlign: TextAlign.right,
                                                text: TextSpan('''
  );
  
  content = content.replaceAll(
'''                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),''',
'''                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        )
                                      ],
                                      ),
                                      ),
                                    );
                                  },
                                ),
                        ),'''
  );


  file.writeAsStringSync(content);
}
