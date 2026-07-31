import 'package:shared_preferences/shared_preferences.dart';

class RemoteContentCache {
  static const _contentPrefix = 'remoteContentBody_';

  Future<String?> readContent(String contentKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_contentPrefix$contentKey');
  }

  Future<void> writeContent(String contentKey, String content) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_contentPrefix$contentKey', content);
  }
}
