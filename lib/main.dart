import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/audio_service.dart';
import 'data/save_service.dart';
import 'data/settings.dart';
import 'game/level/level_repository.dart';
import 'game/ui/design.dart';
import 'game/ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF2F2F3),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  await Settings.instance.load();
  await SaveService.instance.load();
  await LevelRepository.instance.loadIndex();
  await AudioService.instance.init();

  runApp(const ChainReactionCityApp());
}

class ChainReactionCityApp extends StatelessWidget {
  const ChainReactionCityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chain Reaction City',
      debugShowCheckedModeBanner: false,
      theme: D.theme(),
      home: const HomeScreen(),
    );
  }
}
