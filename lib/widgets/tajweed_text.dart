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
    final sanitized = ruleClass.replaceAll("'", "").replaceAll('"', '');
    switch (sanitized) {
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
      case 'idgham_mutajanisayn':
      case 'idgham_mutaqaribayn':
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
    final parts = _parseTajweedParts(text);

    for (final part in parts) {
      final isRule = part.className.isNotEmpty;
      spans.add(TextSpan(
        text: part.text,
        style: TextStyle(
          fontFamily: 'Tajweed',
          fontSize: fontSize,
          color: isRule
              ? _getColorForClass(part.className)
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black),
        ),
      ));
    }

    return RichText(
      textAlign: TextAlign.justify,
      textDirection: TextDirection.rtl,
      text: TextSpan(children: spans),
    );
  }

  static List<_TajweedPart> _parseTajweedParts(String wordStr) {
    final parts = <_TajweedPart>[];
    final classStack = <String>[];
    var buffer = StringBuffer();
    var bufferClass = '';

    String activeClass() => classStack.isEmpty ? '' : classStack.last;

    void flushBuffer() {
      if (buffer.isEmpty) return;
      parts.add(_TajweedPart(
        text: buffer.toString(),
        className: bufferClass,
      ));
      buffer = StringBuffer();
    }

    var index = 0;
    while (index < wordStr.length) {
      final tagStart = wordStr.indexOf('<', index);
      if (tagStart == -1) {
        final text = wordStr.substring(index);
        final nextClass = activeClass();
        if (buffer.isNotEmpty && bufferClass != nextClass) {
          flushBuffer();
        }
        bufferClass = nextClass;
        buffer.write(text);
        break;
      }

      if (tagStart > index) {
        final text = wordStr.substring(index, tagStart);
        final nextClass = activeClass();
        if (buffer.isNotEmpty && bufferClass != nextClass) {
          flushBuffer();
        }
        bufferClass = nextClass;
        buffer.write(text);
      }

      final tagEnd = wordStr.indexOf('>', tagStart + 1);
      if (tagEnd == -1) {
        break;
      }

      final tag = wordStr.substring(tagStart + 1, tagEnd).trim();
      if (tag.startsWith('/')) {
        if (classStack.isNotEmpty) classStack.removeLast();
      } else if (!tag.startsWith('img') && !tag.endsWith('/')) {
        final className = _extractClass(tag);
        classStack.add(className);
      }

      index = tagEnd + 1;
    }

    flushBuffer();
    return parts;
  }

  static String _extractClass(String tag) {
    final match = RegExp(r'''class\s*=\s*["']?([^"'>\s]+)''').firstMatch(tag);
    if (match != null) {
      return match.group(1)?.replaceAll("'", "").replaceAll('"', '').trim() ?? '';
    }
    return '';
  }
}

class _TajweedPart {
  final String text;
  final String className;
  _TajweedPart({required this.text, required this.className});
}
