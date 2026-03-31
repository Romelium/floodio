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
    final settings = ref.watch(appSettingsProvider);
    final isOfficial = settings.isOfficialMode;

    final seedColor = isOfficial ? const Color(0xFFB71C1C) : const Color(0xFF0D47A1);
    final primaryColor = isOfficial ? const Color(0xFFB71C1C) : const Color(0xFF0D47A1);
    final secondaryColor = isOfficial ? const Color(0xFFFFD54F) : const Color(0xFFFF6D00);

    return MaterialApp(
      title: 'Floodio Mesh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
          titleLarge: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          bodyMedium: const TextStyle(fontSize: 15, height: 1.4),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: primaryColor,
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
