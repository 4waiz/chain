import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/audio_service.dart';
import '../../data/save_service.dart';
import '../../engine/render/palette.dart';
import '../level/level_repository.dart';
import 'design.dart';
import 'play_screen.dart';

/// The winding level map.
///
/// Nodes snake down the screen on a sine path so progression reads as a
/// journey through a toy town rather than a grid. Each world gets its own
/// banner, accent colour and landmark.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const List<Color> _worldColours = <Color>[
    Toy.blue,
    Toy.orange,
    Toy.cyan,
    Toy.red,
    Toy.green,
  ];
  static const List<IconData> _worldIcons = <IconData>[
    Icons.directions_car_rounded,
    Icons.precision_manufacturing_rounded,
    Icons.sailing_rounded,
    Icons.celebration_rounded,
    Icons.apartment_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final LevelRepository repo = LevelRepository.instance;
    final SaveService save = SaveService.instance;

    return Scaffold(
      body: StudioBackdrop(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(D.s4, D.s3, D.s4, D.s2),
                child: Row(
                  children: <Widget>[
                    ToyIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () {
                        AudioService.instance.uiTap();
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: D.s3),
                    Text('Levels', style: D.title(Toy.inkStrong)),
                    const Spacer(),
                    ToyChip(
                      icon: Icons.star_rounded,
                      value: '${save.totalStars}/${repo.levelCount * 3}',
                      colour: Toy.yellow,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s7),
                  itemCount: repo.worlds.length,
                  itemBuilder: (BuildContext ctx, int wi) {
                    final WorldInfo w = repo.worlds[wi];
                    if (w.levelIds.isEmpty) return const SizedBox.shrink();
                    final Color colour =
                        _worldColours[wi % _worldColours.length];
                    final int worldStars = w.levelIds.fold(
                      0,
                      (int a, String id) => a + (save.levels[id]?.stars ?? 0),
                    );
                    final bool locked = !_worldUnlocked(wi, repo, save);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(height: D.s4),
                        _WorldBanner(
                          index: wi,
                          info: w,
                          colour: colour,
                          icon: _worldIcons[wi % _worldIcons.length],
                          stars: worldStars,
                          maxStars: w.levelIds.length * 3,
                          locked: locked,
                        ),
                        const SizedBox(height: D.s3),
                        _WorldTrail(
                          levelIds: w.levelIds,
                          colour: colour,
                          locked: locked,
                          onPick: (String id) => _open(id),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A world opens once the previous one is mostly done — enough slack that a
  /// player is never hard-blocked by one awkward level.
  bool _worldUnlocked(int index, LevelRepository repo, SaveService save) {
    if (index == 0) return true;
    final WorldInfo prev = repo.worlds[index - 1];
    if (prev.levelIds.isEmpty) return true;
    final int done = prev.levelIds.where(save.isCompleted).length;
    return done >= (prev.levelIds.length * 0.7).floor();
  }

  Future<void> _open(String id) async {
    AudioService.instance.uiTap();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => PlayScreen(levelId: id)));
    if (mounted) setState(() {});
  }
}

class _WorldBanner extends StatelessWidget {
  const _WorldBanner({
    required this.index,
    required this.info,
    required this.colour,
    required this.icon,
    required this.stars,
    required this.maxStars,
    required this.locked,
  });

  final int index;
  final WorldInfo info;
  final Color colour;
  final IconData icon;
  final int stars;
  final int maxStars;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return ToyCard(
      padding: const EdgeInsets.all(D.s4),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: (locked ? Toy.grey : colour).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              locked ? Icons.lock_rounded : icon,
              color: locked ? Toy.greyDark : colour,
              size: 26,
            ),
          ),
          const SizedBox(width: D.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'World ${info.id}  ·  ${info.name}',
                  style: D.heading(locked ? Toy.inkSoft : Toy.inkStrong),
                ),
                const SizedBox(height: 2),
                Text(
                  locked ? 'Finish more of the previous world' : info.subtitle,
                  style: D.body(Toy.inkSoft),
                ),
                const SizedBox(height: D.s2),
                ToyBar(
                  value: maxStars == 0 ? 0 : stars / maxStars,
                  colour: locked ? Toy.grey : colour,
                  height: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: D.s3),
          Column(
            children: <Widget>[
              const Icon(Icons.star_rounded, color: Toy.yellow, size: 20),
              Text('$stars', style: D.label(Toy.inkStrong)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The snaking row of level nodes for one world.
class _WorldTrail extends StatelessWidget {
  const _WorldTrail({
    required this.levelIds,
    required this.colour,
    required this.locked,
    required this.onPick,
  });

  final List<String> levelIds;
  final Color colour;
  final bool locked;
  final void Function(String id) onPick;

  static const double _nodeSize = 58;
  static const double _rowHeight = 92;

  @override
  Widget build(BuildContext context) {
    final SaveService save = SaveService.instance;
    final int rows = (levelIds.length / 2).ceil();

    return SizedBox(
      height: rows * _rowHeight + 12,
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          final List<Offset> points = <Offset>[];
          for (int i = 0; i < levelIds.length; i++) {
            // Sine snake: two nodes per row, alternating side to side.
            final double t = i / math.max(1, levelIds.length - 1);
            final double x =
                c.maxWidth * (0.5 + 0.33 * math.sin(t * math.pi * 3.1));
            final double y =
                30 + (i / 2) * _rowHeight + (i.isOdd ? _rowHeight / 2 : 0);
            points.add(Offset(x, y));
          }

          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _TrailPainter(points, locked ? Toy.grey : colour),
                ),
              ),
              for (int i = 0; i < levelIds.length; i++)
                Positioned(
                  left: points[i].dx - _nodeSize / 2,
                  top: points[i].dy - _nodeSize / 2,
                  child: _LevelNode(
                    number: i + 1,
                    stars: save.levels[levelIds[i]]?.stars ?? 0,
                    colour: colour,
                    locked: locked || !_reachable(i, levelIds, save),
                    isNext: !locked && _isNext(i, levelIds, save),
                    onTap: () => onPick(levelIds[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static bool _reachable(int i, List<String> ids, SaveService save) =>
      i == 0 || save.isCompleted(ids[i - 1]);

  static bool _isNext(int i, List<String> ids, SaveService save) =>
      !save.isCompleted(ids[i]) && _reachable(i, ids, save);
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.points, this.colour);
  final List<Offset> points;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final Paint p = Paint()
      ..color = colour.withValues(alpha: 0.28)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final Offset a = points[i - 1];
      final Offset b = points[i];
      final Offset mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      path.quadraticBezierTo(a.dx, mid.dy, mid.dx, mid.dy);
      path.quadraticBezierTo(b.dx, mid.dy, b.dx, b.dy);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) =>
      old.colour != colour || old.points.length != points.length;
}

class _LevelNode extends StatelessWidget {
  const _LevelNode({
    required this.number,
    required this.stars,
    required this.colour,
    required this.locked,
    required this.isNext,
    required this.onTap,
  });

  final int number;
  final int stars;
  final Color colour;
  final bool locked;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool done = stars > 0;
    final Color fill = locked ? Toy.studioDeep : (done ? colour : Toy.white);
    final Color fg = locked ? Toy.greyDark : (done ? Toy.white : Toy.inkStrong);

    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: isNext ? Border.all(color: colour, width: 3.5) : null,
              boxShadow: locked ? null : D.chip,
            ),
            alignment: Alignment.center,
            child: locked
                ? const Icon(Icons.lock_rounded, size: 20, color: Toy.greyDark)
                : Text('$number', style: D.number(fg)),
          ),
          const SizedBox(height: 3),
          if (!locked) StarRow(earned: stars, size: 13),
        ],
      ),
    );
  }
}
