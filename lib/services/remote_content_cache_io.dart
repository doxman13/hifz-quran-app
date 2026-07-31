import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RemoteContentCache {
  Future<String?> readContent(String contentKey) async {
    final file = await _contentFile(contentKey);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> writeContent(String contentKey, String content) async {
    final file = await _contentFile(contentKey);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  Future<File> _contentFile(String contentKey) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/remote_content/$contentKey.json');
  }
}
