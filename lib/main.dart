import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database/connection.dart';
import 'database/database.dart';
import 'providers/database_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/critical_alert_provider.dart';
import 'screens/initializer_screen.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://placeholder.supabase.co',
    ),
    anonKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: 'placeholder',
    ),
  );

  final connection = await getSharedConnection();
  final db = AppDatabase(connection);

  final prefs = await SharedPreferences.getInstance();

  db.cleanupOldData().catchError((e) {
    debugPrint("[FloodioApp] Error during database cleanup: $e");
  });
  await initializeBackgroundService();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const FloodioApp(),
    ),
  );
}

class FloodioApp extends ConsumerWidget {
  const FloodioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final isOfficial = settings.isOfficialMode;
    final isRedAlert = ref.watch(redAlertControllerProvider).isActive;

    final seedColor = isRedAlert
        ? Colors.redAccent
        : (isOfficial ? const Color(0xFFB71C1C) : const Color(0xFF0D47A1));
    final primaryColor = isRedAlert
        ? Colors.redAccent
        : (isOfficial ? const Color(0xFFB71C1C) : const Color(0xFF0D47A1));
    final secondaryColor = isRedAlert
        ? Colors.orangeAccent
        : (isOfficial ? const Color(0xFFFFD54F) : const Color(0xFFFF6D00));

    ThemeData theme;
    if (isRedAlert) {
      theme = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
          primary: primaryColor,
          secondary: secondaryColor,
          tertiary: Colors.red.shade900,
          surface: const Color(0xFF200000),
          error: Colors.red,
        ),
        textTheme: TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
          titleLarge: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
          bodyMedium: const TextStyle(
            fontSize: 15,
            height: 1.4,
            color: Colors.white70,
          ),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: Colors.red.shade900,
          labelStyle: const TextStyle(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          color: const Color(0xFF3E0000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.red.shade900.withValues(alpha: 0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      );
    } else {
      theme = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          primary: primaryColor,
          secondary: secondaryColor,
          tertiary: const Color(0xFF00838F), // Cyan 800
          surface: const Color(0xFFF8F9FA),
          error: const Color(0xFFD32F2F),
        ),
        textTheme: TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
          titleLarge: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
          bodyMedium: const TextStyle(fontSize: 15, height: 1.4),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Floodio Mesh',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const InitializerScreen(),
    );
  }
}
