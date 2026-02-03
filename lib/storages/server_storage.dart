import 'package:shared_preferences/shared_preferences.dart';

class ServerStorage {
  static const String _key = 'saved_servers';

  static Future<void> saveServers(List<String> servers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, servers);
  }

  static Future<List<String>> loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }
}