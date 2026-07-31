import 'package:flutter/material.dart';

class TajweedText extends StatelessWidget {
  final String text;
  final double fontSize;

  const TajweedText({
    super.key,
    required this.text,
    this.fontSize = 24.0,
  });

  Color _getColorForClass(String ruleClass) {
    // Strip quotes if they exist in the class name e.g. class='ham_wasl'
    ruleClass = ruleClass.replaceAll("'", "").replaceAll('"', '');
    switch (ruleClass) {
      case 'madda_normal':
      case 'madda_permissible':
      case 'madda_necessary':
      case 'madda_obligatory_mottasel':
      case 'madda_obligatory_monfasel':
        return Colors.red;
      case 'ghunnah':
      case 'idgham_ghunnah':
        return Colors.green;
      case 'idgham_wo_ghunnah':
      case 'slnt':
      case 'ham_wasl':
      case 'laam_shamsiyah':
        return Colors.grey;
      case 'qalaqah':
        return Colors.blue;
      case 'ikhafa':
      case 'ikhafa_shafawi':
        return Colors.orange;
      case 'iqlab':
        return Colors.purple;
      default:
        return Colors.black;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    
    // A simple regex to match <rule class=... >...</rule> or plain text
    final regex = RegExp(r'<rule class=([^>]+)>([^<]+)</rule>|([^<]+)');
    final matches = regex.allMatches(text);

    for (final match in matches) {
      if (match.group(1) != null) {
        // This is a rule match
        final ruleClass = match.group(1)!;
        final content = match.group(2)!;
        spans.add(TextSpan(
          text: content,
          style: TextStyle(
            fontFamily: 'Tajweed', // The font family defined in pubspec.yaml
            fontSize: fontSize,
            color: _getColorForClass(ruleClass),
          ),
        ));
      } else {
        // This is plain text
        final content = match.group(3)!;
        spans.add(TextSpan(
          text: content,
          style: TextStyle(
            fontFamily: 'Tajweed',
            fontSize: fontSize,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
          ),
        ));
      }
    }

    return RichText(
      textAlign: TextAlign.justify,
      textDirection: TextDirection.rtl,
      text: TextSpan(children: spans),
    );
  }
}
