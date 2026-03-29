import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme.dart';
import 'providers/app_state_provider.dart';
import 'services/mqtt_service.dart';
import 'services/notification_service.dart';
import 'router.dart';

class AppConfig {
  static String supabaseUrl = '';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env', mergeWith: {}).catchError((_) {
    debugPrint('[WARN] .env file not found');
  });

  AppConfig.supabaseUrl = dotenv.env['SUPABASE_URL']!;
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp();
    await NotificationService.initialize();
  }

  final appState = AppStateProvider();
  final mqttService = MqttService();

  // Connect MQTT in background — non-blocking, silently skipped on web.
  mqttService.connect().catchError((e) {
    debugPrint('MQTT connection failed: $e');
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        Provider<MqttService>.value(value: mqttService),
      ],
      child: Consumer<AppStateProvider>(
        builder: (context, provider, _) => MaterialApp.router(
          title: 'Smart Irrigation',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: provider.themeMode,
          routerConfig: createRouter(appState),
          debugShowCheckedModeBanner: false,
        ),
      ),
    ),
  );
}
