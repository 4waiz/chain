import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dev/render_probe.dart';
import 'engine/render/palette.dart';

const bool kProbe = bool.fromEnvironment('CRC_PROBE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ChainReactionCityApp());
}

class ChainReactionCityApp extends StatelessWidget {
  const ChainReactionCityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chain Reaction City',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Toy.studio,
        fontFamily: 'Toy',
        useMaterial3: true,
      ),
      home: const RenderProbe(),
    );
  }
}
