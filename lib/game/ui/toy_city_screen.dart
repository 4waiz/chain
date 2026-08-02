import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import '../../data/audio_service.dart';
import '../../data/save_service.dart';
import '../../engine/assets/model_cache.dart';
import '../../engine/render/camera.dart';
import '../../engine/render/mesh.dart';
import '../../engine/render/palette.dart';
import '../../engine/render/render_instance.dart';
import '../../engine/render/renderer.dart';
import '../../engine/render/scene_bounds.dart';
import '../../engine/render/scene_view.dart';
import '../level/level_repository.dart';
import 'design.dart';

/// A landmark the city can unlock, in the order they appear.
class CityPiece {
  const CityPiece(this.model, this.label, {this.scale = 1.0});
  final String model;
  final String label;
  final double scale;
}

/// The Toy City: a purely visual reward that grows one landmark per completed
/// level. Deliberately not a management game â€” there is nothing to tap, spend
/// or optimise. It exists so that progress has somewhere to accumulate.
class ToyCityScreen extends StatefulWidget {
  const ToyCityScreen({super.key});

  @override
  State<ToyCityScreen> createState() => _ToyCityScreenState();
}

class _ToyCityScreenState extends State<ToyCityScreen> {
  static const List<CityPiece> _pieces = <CityPiece>[
    CityPiece('road_straight', 'Main Street'),
    CityPiece('building_small', 'Corner Shop'),
    CityPiece('park_tree', 'First Tree'),
    CityPiece('building_mid', 'Town Hall'),
    CityPiece('lamp_post', 'Street Lamp'),
    CityPiece('park_bench', 'Park Bench'),
    CityPiece('building_small', 'Bakery'),
    CityPiece('street_sign', 'Signpost'),
    CityPiece('pedestrian_bridge', 'Footbridge'),
    CityPiece('building_tall', 'Tower Block'),
    CityPiece('park_tree', 'Park Grove'),
    CityPiece('traffic_barrier', 'Roadworks'),
    CityPiece('conveyor', 'Factory Line'),
    CityPiece('building_mid', 'Workshop'),
    CityPiece('road_wide', 'Plaza'),
    CityPiece('flag_base', 'Flag Pole'),
    CityPiece('building_small', 'Harbour Office'),
    CityPiece('park_tree', 'Harbour Trees'),
    CityPiece('bell', 'Harbour Bell'),
    CityPiece('lamp_post', 'Dock Lamp'),
    CityPiece('building_tall', 'Lighthouse', scale: 1.1),
    CityPiece('celebration_machine', 'Confetti Works'),
    CityPiece('building_mid', 'Carnival Booth'),
    CityPiece('fireworks_box', 'Fireworks Stand'),
    CityPiece('park_bench', 'Carnival Seats'),
    CityPiece('spring_launcher', 'Bouncy Ride'),
    CityPiece('building_small', 'Ticket Hut'),
    CityPiece('city_beacon', 'City Beacon'),
    CityPiece('building_tall', 'Skyscraper', scale: 1.15),
    CityPiece('finish_tower', 'Victory Tower', scale: 1.2),
  ];

  final OrbitCamera _camera = OrbitCamera(pitch: 0.55, yaw: -0.7, fovY: 0.5);
  final Renderer _renderer = Renderer();
  final List<RenderInstance> _instances = <RenderInstance>[];
  bool _ready = false;
  bool _framed = false;

  int get _unlocked =>
      math.min(_pieces.length, SaveService.instance.cityUnlocks.length);

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    final int n = _unlocked;
    final Set<String> models = <String>{
      for (int i = 0; i < n; i++) _pieces[i].model,
    };
    await ModelCache.instance.loadAll(models);

    _instances.clear();
    for (int i = 0; i < n; i++) {
      final CityPiece p = _pieces[i];
      final Mesh? m = ModelCache.instance.peek(p.model);
      if (m == null) continue;

      // Lay the city out on a spiral so it always looks composed, however many
      // pieces are unlocked, and never needs a hand-authored layout per count.
      final double a = i * 2.399963; // golden angle
      final double r = 0.34 * math.sqrt(i + 0.6);
      final double x = math.cos(a) * r;
      final double z = math.sin(a) * r;
      final double y = m.sizeY * 0.5 * p.scale;

      final Matrix4 t = Matrix4.translation(Vector3(x, y, z))
        ..rotateY(a * 0.5)
        ..scaleByVector3(Vector3.all(p.scale));
      _instances.add(RenderInstance(mesh: m, transform: t));
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    final int n = _unlocked;
    final int total = _pieces.length;
    final int levels = LevelRepository.instance.levelCount;

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
                    Expanded(
                      child: Text('Toy City', style: D.title(Toy.inkStrong)),
                    ),
                    ToyChip(
                      icon: Icons.location_city_rounded,
                      value: '$n/$total',
                      colour: Toy.orange,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: n == 0
                    ? _Empty(levels: levels)
                    : (!_ready
                          ? const Center(
                              child: CircularProgressIndicator(color: Toy.blue),
                            )
                          : LayoutBuilder(
                              builder: (BuildContext ctx, BoxConstraints c) {
                                if (!_framed &&
                                    c.maxHeight > 0 &&
                                    _instances.isNotEmpty) {
                                  _framed = true;
                                  final SceneBounds b = SceneBounds.of(
                                    _instances,
                                  );
                                  _camera.frameBounds(
                                    b.lo,
                                    b.hi,
                                    c.maxWidth / c.maxHeight,
                                    pad: 1.3,
                                    verticalBias: 0.1,
                                  );
                                }
                                return SceneView(
                                  camera: _camera,
                                  instances: _instances,
                                  renderer: _renderer,
                                  // A slow turntable so the whole city reads.
                                  onFrame: (double dt) =>
                                      _camera.yaw += dt * 0.16,
                                );
                              },
                            )),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s4),
                child: ToyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        n == 0
                            ? 'Nothing built yet'
                            : 'Latest: ${_pieces[n - 1].label}',
                        style: D.heading(Toy.inkStrong),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        n >= total
                            ? 'Your city is complete. Every landmark is standing.'
                            : 'Next: ${_pieces[n].label} â€” finish one more level',
                        style: D.body(Toy.inkSoft),
                      ),
                      const SizedBox(height: D.s3),
                      ToyBar(
                        value: total == 0 ? 0 : n / total,
                        colour: Toy.orange,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.levels});
  final int levels;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(D.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Toy.orange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.location_city_rounded,
                size: 46,
                color: Toy.orange,
              ),
            ),
            const SizedBox(height: D.s4),
            Text('Your city starts here', style: D.heading(Toy.inkStrong)),
            const SizedBox(height: D.s2),
            Text(
              'Every level you finish adds a landmark. There are $levels to build.',
              style: D.body(Toy.inkSoft),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
