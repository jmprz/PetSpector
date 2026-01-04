import 'package:flutter/material.dart';
import '../utils/notification_preferences.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _scanNotifications = true;
  bool _moodNotifications = true;
  bool _weeklySummary = false;
  bool _healthAlerts = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);
    final prefs = await NotificationPreferences.getAllPreferences();
    setState(() {
      _scanNotifications = prefs['scanNotifications'] ?? true;
      _moodNotifications = prefs['moodNotifications'] ?? true;
      _weeklySummary = prefs['weeklySummary'] ?? false;
      _healthAlerts = prefs['healthAlerts'] ?? true;
      _isLoading = false;
    });
  }

  Future<void> _savePreferences() async {
    await NotificationPreferences.setScanNotifications(_scanNotifications);
    await NotificationPreferences.setMoodNotifications(_moodNotifications);
    await NotificationPreferences.setWeeklySummary(_weeklySummary);
    await NotificationPreferences.setHealthAlerts(_healthAlerts);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Notification settings saved!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: const Color(0xFF3F7795),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      "Manage your notification preferences",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  _buildNotificationTile(
                    icon: Icons.camera_alt,
                    title: "Scan Notifications",
                    subtitle: "Get notified when scans complete",
                    value: _scanNotifications,
                    onChanged: (value) {
                      setState(() => _scanNotifications = value);
                      _savePreferences();
                    },
                  ),
                  _buildNotificationTile(
                    icon: Icons.mood,
                    title: "Mood Analysis Notifications",
                    subtitle: "Get notified when mood analysis completes",
                    value: _moodNotifications,
                    onChanged: (value) {
                      setState(() => _moodNotifications = value);
                      _savePreferences();
                    },
                  ),
                  _buildNotificationTile(
                    icon: Icons.health_and_safety,
                    title: "Health Alerts",
                    subtitle: "Important health and allergy alerts",
                    value: _healthAlerts,
                    onChanged: (value) {
                      setState(() => _healthAlerts = value);
                      _savePreferences();
                    },
                  ),
                  _buildNotificationTile(
                    icon: Icons.summarize,
                    title: "Weekly Summary",
                    subtitle: "Receive weekly scan summary",
                    value: _weeklySummary,
                    onChanged: (value) {
                      setState(() => _weeklySummary = value);
                      _savePreferences();
                    },
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          await NotificationPreferences.resetToDefaults();
                          await _loadPreferences();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Reset to default settings"),
                                backgroundColor: Colors.blue,
                              ),
                            );
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          side: const BorderSide(color: Colors.grey),
                        ),
                        child: const Text("Reset to Defaults"),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildNotificationTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF3F7795).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF3F7795)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF3F7795),
      ),
    );
  }
}

