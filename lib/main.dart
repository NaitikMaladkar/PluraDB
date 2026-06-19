import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pluradb/providers/app_provider.dart';
import 'package:pluradb/screens/home_screen.dart';
import 'package:pluradb/screens/welcome_screen.dart';
import 'package:pluradb/services/storage_service.dart';
import 'package:pluradb/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final storageService = StorageService();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(storageService),
      child: const PluraDBApp(),
    ),
  );
}

class PluraDBApp extends StatelessWidget {
  const PluraDBApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PluraDB',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (!provider.isInitialized) {
            return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.accent)));
          }
          if (provider.databases.isEmpty) {
            return const WelcomeScreen();
          }
          return const HomeScreen();
        },
      ),
    );
  }
}
