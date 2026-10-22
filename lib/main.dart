import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/batam_game.dart';
import 'ui/hud/game_hud.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const BatamApp());
}

class BatamApp extends StatefulWidget {
  const BatamApp({super.key});

  @override
  State<BatamApp> createState() => _BatamAppState();
}

class _BatamAppState extends State<BatamApp> {
  final _game = BatamGame();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Batam: The Journey Begins',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          children: [
            GameWidget(game: _game),
            Positioned.fill(child: GameHud(game: _game)),
          ],
        ),
      ),
    );
  }
}
