import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'providers/app_state_provider.dart';
import 'services/mqtt_service.dart';
import 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env", mergeWith: {}).catchError((_) {
    // .env missing — app will crash later at Supabase.initialize if keys are absent
    debugPrint('[WARN] .env file not found');
  });
  // Initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Create services once at startup
  final appState = AppStateProvider();
  final mqttService = MqttService();

  // Connect MQTT in background (non-blocking)
  mqttService.connect().catchError((e) {
    debugPrint('MQTT connection failed: $e');
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        Provider<MqttService>.value(value: mqttService),
      ],
      child: MaterialApp.router(
        title: 'Smart Irrigation',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        routerConfig: createRouter(appState),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}
