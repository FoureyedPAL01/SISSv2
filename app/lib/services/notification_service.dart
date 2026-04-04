import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../router.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await NotificationService.showLocalNotification(message);
}

class NotificationService {
  NotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _localNotificationsReady = false;

  static const AndroidNotificationChannel _alertChannel =
      AndroidNotificationChannel(
        'rootsync_alerts',
        'Plant Alerts',
        description: 'Real-time alerts from your ESP32 plant monitoring system',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[WARN] Push notification permission denied');
      return;
    }

    debugPrint(
      '[INFO] Notification permission: ${settings.authorizationStatus}',
    );

    await _ensureLocalNotificationsInitialized();

    final String? token = await _messaging.getToken();
    debugPrint('[INFO] FCM token: $token');
    if (token != null) {
      await _saveTokenToSupabase(token);
    }

    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('[INFO] FCM token refreshed');
      _saveTokenToSupabase(newToken);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
        '[INFO] Foreground message: ${message.notification?.title ?? 'untitled'}',
      );
      showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[INFO] Notification tapped from background');
      handleNavigation(message.data);
    });

    final RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[INFO] App launched from notification');
      await Future.delayed(const Duration(milliseconds: 500));
      handleNavigation(initialMessage.data);
    }
  }

  static Future<void> _ensureLocalNotificationsInitialized() async {
    if (_localNotificationsReady) {
      return;
    }

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_alertChannel);

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
    );

    _localNotificationsReady = true;
  }

  static Future<void> _saveTokenToSupabase(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        debugPrint('[WARN] No logged-in user, skipping token save');
        return;
      }

      await Supabase.instance.client.from('device_tokens').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      debugPrint('[INFO] FCM token saved to Supabase');
    } catch (e) {
      debugPrint('[ERROR] Failed to save FCM token: $e');
    }
  }

  static Future<void> showLocalNotification(RemoteMessage message) async {
    final RemoteNotification? notification = message.notification;
    if (notification == null) {
      return;
    }

    await _ensureLocalNotificationsInitialized();

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _alertChannel.id,
          _alertChannel.name,
          channelDescription: _alertChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF2E7D32),
          enableVibration: true,
          playSound: true,
          when: DateTime.now().millisecondsSinceEpoch,
          showWhen: true,
        ),
      ),
      payload: message.data['screen']?.toString(),
    );
  }

  @pragma('vm:entry-point')
  static void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null || response.payload!.isEmpty) {
      handleNavigation(const <String, dynamic>{});
      return;
    }

    handleNavigation(<String, dynamic>{'screen': response.payload});
  }

  static void handleNavigation(Map<String, dynamic> data) {
    final String? screen = data['screen']?.toString();
    final context = rootNavigatorKey.currentContext;

    if (context == null) {
      debugPrint('[WARN] Navigation context not ready for notification tap');
      return;
    }

    switch (screen) {
      case 'alerts':
        context.go('/alerts');
        break;
      case 'profile':
        context.go('/profile');
        break;
      case 'weather':
        context.go('/weather');
        break;
      default:
        context.go('/');
    }
  }

  static Future<void> onUserLogin() async {
    final String? token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToSupabase(token);
    }
  }

  static Future<void> onUserLogout() async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      final token = await _messaging.getToken();

      if (currentUser != null) {
        await Supabase.instance.client
            .from('device_tokens')
            .delete()
            .eq('user_id', currentUser.id);
      } else if (token != null) {
        await Supabase.instance.client
            .from('device_tokens')
            .delete()
            .eq('fcm_token', token);
      }

      await _messaging.deleteToken();
      debugPrint('[INFO] FCM token removed on logout');
    } catch (e) {
      debugPrint('[ERROR] Failed to remove FCM token: $e');
    }
  }

  static Future<void> sendTestNotification() async {
    await _ensureLocalNotificationsInitialized();

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'rootsync_alerts',
          'Plant Alerts',
          channelDescription:
              'Real-time alerts from your ESP32 plant monitoring system',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _localNotifications.show(
      0,
      'Test Notification',
      'This is a test notification from RootSync!',
      details,
    );

    debugPrint('[INFO] Test notification sent');
  }
}
