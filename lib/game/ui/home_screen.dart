import 'package:flutter/material.dart';

import '../../data/audio_service.dart';
import '../../data/save_service.dart';
import '../../engine/render/palette.dart';
import '../level/level_repository.dart';
import 'daily_screen.dart';
import 'design.dart';
import 'lab_screen.dart';
import 'map_screen.dart';
import 'play_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'toy_city_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    SaveService.instance.addListener(_onSave);
    AudioService.instance.startMusic();
  }

  @override
  void dispose() {
    SaveService.instance.removeListener(_onSave);
    super.dispose();
  }

  void _onSave() {
    if (mounted) setState(() {});
  }

  /// The first level the player has not yet completed, or the last one.
  String get _currentLevelId {
    final List<String> all = LevelRepository.instance.orderedIds;
    if (all.isEmpty) return 'w1_l1';
    for (final String id in all) {
      if (!SaveService.instance.isCompleted(id)) return id;
    }
    return all.last;
  }

  Future<void> _go(Widget screen) async {
    AudioService.instance.uiTap();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final SaveService save = SaveService.instance;
    final LevelRepository repo = LevelRepository.instance;
    final String current = _currentLevelId;
    final int world = repo.worldOf(current);
    final int idx = repo.indexInWorld(current);

    return Scaffold(
      body: StudioBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: D.s5),
            child: Column(
              children: <Widget>[
                const SizedBox(height: D.s3),
                Row(
                  children: <Widget>[
                    ToyChip(
                      icon: Icons.monetization_on_rounded,
                      value: '${save.coins}',
                      colour: Toy.yellowDark,
                    ),
                    const SizedBox(width: D.s2),
                    ToyChip(
                      icon: Icons.star_rounded,
                      value: '${save.totalStars}',
                      colour: Toy.yellow,
                    ),
                    const Spacer(),
                    ToyIconButton(
                      icon: Icons.settings_rounded,
                      tooltip: 'Settings',
                      onTap: () => _go(const SettingsScreen()),
                    ),
                  ],
                ),

                const Spacer(flex: 2),

                // The wordmark card is the art bible itself.
                Flexible(
                  flex: 12,
                  child: Image.asset(
                    'logo.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),

                const Spacer(flex: 1),
                Text('One tap. Total chaos.', style: D.body(Toy.inkSoft)),
                const Spacer(flex: 2),

                ToyButton(
                  label: save.levelsCompleted == 0
                      ? 'Play'
                      : 'Level $world-$idx',
                  colour: Toy.blue,
                  icon: Icons.play_arrow_rounded,
                  big: true,
                  wide: true,
                  onTap: () => _go(PlayScreen(levelId: current)),
                ),
                const SizedBox(height: D.s3),

                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Tile(
                        icon: Icons.map_rounded,
                        label: 'Levels',
                        colour: Toy.green,
                        badge: '${save.levelsCompleted}/${repo.levelCount}',
                        onTap: () => _go(const MapScreen()),
                      ),
                    ),
                    const SizedBox(width: D.s3),
                    Expanded(
                      child: _Tile(
                        icon: Icons.today_rounded,
                        label: 'Daily',
                        colour: Toy.red,
                        badge: save.dailyStreak > 0
                            ? '${save.dailyStreak} day'
                            : 'New',
                        onTap: () => _go(const DailyScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: D.s3),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Tile(
                        icon: Icons.location_city_rounded,
                        label: 'Toy City',
                        colour: Toy.orange,
                        badge: '${save.cityUnlocks.length}',
                        onTap: () => _go(const ToyCityScreen()),
                      ),
                    ),
                    const SizedBox(width: D.s3),
                    Expanded(
                      child: _Tile(
                        icon: Icons.science_rounded,
                        label: 'Lab',
                        colour: Toy.purple,
                        badge: save.labUnlocked
                            ? '${save.labBestChain}'
                            : 'Lv10',
                        enabled: save.labUnlocked,
                        onTap: () => _go(const LabScreen()),
                      ),
                    ),
                    const SizedBox(width: D.s3),
                    Expanded(
                      child: _Tile(
                        icon: Icons.storefront_rounded,
                        label: 'Shop',
                        colour: Toy.cyan,
                        onTap: () => _go(const ShopScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: D.s5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
    this.badge,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback onTap;
  final String? badge;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color c = enabled ? colour : Toy.grey;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: D.s3, horizontal: D.s2),
        decoration: BoxDecoration(
          color: Toy.white,
          borderRadius: BorderRadius.circular(D.rLg),
          boxShadow: D.chip,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: c, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: D.label(enabled ? Toy.inkStrong : Toy.inkSoft)),
            if (badge != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(badge!, style: D.tiny(Toy.inkSoft)),
            ],
          ],
        ),
      ),
    );
  }
}
