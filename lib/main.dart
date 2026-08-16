import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'providers/journal_provider.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端（Windows）使用 sqlite3 FFI 实现。
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final prefs = await SharedPreferences.getInstance();

  final journal = JournalProvider();
  await journal.load();

  runApp(PageNoteApp(
    settings: SettingsProvider(prefs),
    journal: journal,
  ));
}

class PageNoteApp extends StatelessWidget {
  const PageNoteApp({
    super.key,
    required this.settings,
    required this.journal,
  });

  final SettingsProvider settings;
  final JournalProvider journal;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: journal),
      ],
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return MaterialApp(
            onGenerateTitle: (context) => '拾页',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(settings.seedColor),
            darkTheme: AppTheme.dark(settings.seedColor),
            themeMode: settings.themeMode,
            locale: const Locale('zh'),
            supportedLocales: const [
              Locale('zh'),
              Locale('en'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(settings.fontScale),
                ),
                child: child!,
              );
            },
            home: RootShell(),
          );
        },
      ),
    );
  }
}
