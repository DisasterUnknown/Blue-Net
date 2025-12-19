import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalSharedPreferences {
  static Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    LogService.log("Info", "Setting pref $key to $value");
    await prefs.setString(key, value);
  }

  static Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    LogService.log("Info", "Getting pref $key");
    return prefs.getString(key);
  }

  static Future<void> removeKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    LogService.log("Info", "Removing pref $key");
    await prefs.remove(key);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    LogService.log("Info", "Clearing all preferences");
    await prefs.clear();
  }
}
