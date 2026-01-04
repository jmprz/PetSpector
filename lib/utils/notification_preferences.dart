import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreferences {
  static const String _keyScanNotifications = 'scan_notifications';
  static const String _keyMoodNotifications = 'mood_notifications';
  static const String _keyWeeklySummary = 'weekly_summary';
  static const String _keyHealthAlerts = 'health_alerts';

  // Default values
  static const bool _defaultScanNotifications = true;
  static const bool _defaultMoodNotifications = true;
  static const bool _defaultWeeklySummary = false;
  static const bool _defaultHealthAlerts = true;

  // Get notification preferences
  static Future<bool> getScanNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyScanNotifications) ?? _defaultScanNotifications;
  }

  static Future<bool> getMoodNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyMoodNotifications) ?? _defaultMoodNotifications;
  }

  static Future<bool> getWeeklySummary() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyWeeklySummary) ?? _defaultWeeklySummary;
  }

  static Future<bool> getHealthAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHealthAlerts) ?? _defaultHealthAlerts;
  }

  // Set notification preferences
  static Future<void> setScanNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyScanNotifications, value);
  }

  static Future<void> setMoodNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMoodNotifications, value);
  }

  static Future<void> setWeeklySummary(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWeeklySummary, value);
  }

  static Future<void> setHealthAlerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHealthAlerts, value);
  }

  // Get all preferences as a map
  static Future<Map<String, bool>> getAllPreferences() async {
    return {
      'scanNotifications': await getScanNotifications(),
      'moodNotifications': await getMoodNotifications(),
      'weeklySummary': await getWeeklySummary(),
      'healthAlerts': await getHealthAlerts(),
    };
  }

  // Reset all preferences to defaults
  static Future<void> resetToDefaults() async {
    await setScanNotifications(_defaultScanNotifications);
    await setMoodNotifications(_defaultMoodNotifications);
    await setWeeklySummary(_defaultWeeklySummary);
    await setHealthAlerts(_defaultHealthAlerts);
  }
}

