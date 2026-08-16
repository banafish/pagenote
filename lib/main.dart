import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'pages/editor_page.dart';
import 'providers/journal_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/template_provider.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/lock_gate.dart';

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

  final templates = TemplateProvider();
  await templates.load();

  // 写作提醒（仅 Android；Windows 自动降级）。
  await NotificationService.instance.init();

  runApp(PageNoteApp(
    settings: SettingsProvider(prefs),
    journal: journal,
    templates: templates,
  ));
}

class PageNoteApp extends StatelessWidget {
  const PageNoteApp({
    super.key,
    required this.settings,
    required this.journal,
    required this.templates,
  });

  final SettingsProvider settings;
  final JournalProvider journal;
  final TemplateProvider templates;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: journal),
        ChangeNotifierProvider.value(value: templates),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([settings, templates]),
        builder: (context, _) {
          return MaterialApp(
            onGenerateTitle: (context) => '拾页',
            debugShowCheckedModeBanner: false,
            navigatorKey: NotificationService.instance.navigatorKey,
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
            onGenerateRoute: (route) {
              // 点击写作提醒通知直达编辑页（REQ-07.3）：
              // 在当前栈顶直接叠加编辑器。
              if (route.name == '/write') {
                return MaterialPageRoute(builder: (_) => const EditorPage());
              }
              return null;
            },
            home: const LockGate(child: RootShell()),
          );
        },
      ),
    );
  }
}
