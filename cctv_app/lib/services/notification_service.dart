import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  String? _lastKey;
  DateTime? _lastAt;

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await plugin.initialize(settings);
    await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  Future<void> showStatus(String title, String body) async {
    final key = '$title|$body';
    final now = DateTime.now();
    if (_lastKey == key && _lastAt != null && now.difference(_lastAt!).inSeconds < 3) return;
    _lastKey = key;
    _lastAt = now;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'cctv_status',
        'CCTV Status',
        channelDescription: 'Camera and connection status alerts',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    await plugin.show(1001, title, body, details);
  }
}
