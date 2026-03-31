import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/connection.dart';
import 'database/database.dart';
import 'providers/database_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/initializer_screen.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final connection = await getSharedConnection();
  final db = AppDatabase(connection);

  // Initialize settings before app start
  final container = ProviderContainer();
  await container.read(appSettingsProvider.notifier).init();
  final initialSettings = container.read(appSettingsProvider);

  await db.cleanupOldData();
  await initializeBackgroundService();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        appSettingsProvider.overrideWithValue(initialSettings),
      ],
      child: const FloodioApp(),
    ),
  );
}

class FloodioApp extends ConsumerWidget {
  const FloodioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Floodio Mesh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1), // Blue 900
          primary: const Color(0xFF0D47A1),
          secondary: const Color(0xFFFF6D00), // Orange A400
          tertiary: const Color(0xFF00838F), // Cyan 800
          surface: const Color(0xFFF8F9FA),
          error: const Color(0xFFD32F2F),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D47A1),
          ),
          titleLarge: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          bodyMedium: TextStyle(fontSize: 15, height: 1.4),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF0D47A1),
          foregroundColor: Colors.white,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const InitializerScreen(),
    );
  }
}
