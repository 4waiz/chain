import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import '../engine/assets/model_cache.dart';
import '../engine/render/camera.dart';
import '../engine/render/mesh.dart';
import '../engine/render/palette.dart';
import '../engine/render/render_instance.dart';
import '../engine/render/renderer.dart';
import '../engine/render/scene_view.dart';

/// Development harness used to validate the renderer against `logo.png` and to
/// measure frame cost on a real device. Not part of the shipping flow; reached
/// only with `--dart-define=CRC_PROBE=1`.
class RenderProbe extends StatefulWidget {
  const RenderProbe({super.key});

  @override
  State<RenderProbe> createState() => _RenderProbeState();
}

class _RenderProbeState extends State<RenderProbe> {
  final OrbitCamera _camera = OrbitCamera(distance: 3.4, yaw: -0.34, pitch: 0.30, fovY: 0.52);
  final Renderer _renderer = Renderer();
  final List<RenderInstance> _instances = <RenderInstance>[];

  bool _ready = false;
  String? _error;
  double _t = 0;
  int _copies = 1;
  bool _orbit = true;

  static const List<String> _slugs = <String>[
    'cannon_barrel', 'cannon_carriage', 'cannon_wheel', 'cannonball',
    'domino_blue', 'domino_yellow', 'domino_green', 'domino_red',
    'block_red', 'block_blue', 'block_roof',
    'toy_car_body', 'toy_car_wheel',
    'capsule_yellow', 'capsule_green', 'capsule_blue', 'capsule_red', 'capsule_duo',
    'star', 'coin', 'confetti',
  ];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await ModelCache.instance.loadAll(_slugs);
      final Set<String> missing = ModelCache.instance.missing;
      if (missing.isNotEmpty) {
        setState(() => _error = 'Missing models: ${missing.join(", ")}');
        return;
      }
      _rebuild();
      setState(() => _ready = true);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  RenderInstance? _add(String slug, Vector3 pos, {double rotZ = 0, double rotY = 0, double rotX = 0}) {
    final Mesh? m = ModelCache.instance.peek(slug);
    if (m == null) return null;
    final Matrix4 t = Matrix4.translation(pos);
    if (rotY != 0) t.rotateY(rotY);
    if (rotZ != 0) t.rotateZ(rotZ);
    if (rotX != 0) t.rotateX(rotX);
    final RenderInstance inst = RenderInstance(mesh: m, transform: t);
    _instances.add(inst);
    return inst;
  }

  /// Rebuilds the `logo.png` composition, optionally tiled [_copies] times to
  /// find the triangle ceiling.
  void _rebuild() {
    _instances.clear();
    for (int c = 0; c < _copies; c++) {
      final double oz = (c % 4) * 1.15 - 1.7;
      final double ox = (c ~/ 4) * 3.4;
      _composition(ox, oz);
    }
  }

  void _composition(double ox, double oz) {
    Vector3 p(double x, double y, double z) => Vector3(x + ox, y, z + oz);

    // Cannon.
    _add('cannon_carriage', p(-1.28, 0.115, 0));
    _add('cannon_barrel', p(-1.16, 0.250, 0), rotZ: 0.21);
    _add('cannon_wheel', p(-1.31, 0.108, 0.115));
    _add('cannon_wheel', p(-1.31, 0.108, -0.115));

    // Ball in flight.
    _add('cannonball', p(-0.74, 0.47, 0));

    // Block tower with green roof.
    _add('block_red', p(-0.30, 0.132, 0.10));
    _add('block_blue', p(-0.30, 0.396, 0.10));
    _add('block_red', p(-0.30, 0.660, 0.10));
    _add('block_roof', p(-0.30, 0.868, 0.10));

    // Domino run, progressively toppling.
    const List<(String, double, double)> run = <(String, double, double)>[
      ('domino_blue', -0.02, 0),
      ('domino_yellow', 0.20, 16),
      ('domino_green', 0.43, 38),
      ('domino_red', 0.70, 62),
    ];
    for (final (String slug, double x, double deg) in run) {
      final double a = deg * math.pi / 180.0;
      const double h = 0.42, th = 0.083;
      final double cx = x + (h / 2) * math.sin(a) - (th / 2) * (1 - math.cos(a));
      final double cy = (h / 2) * math.cos(a) + (th / 2) * math.sin(a);
      _add(slug, p(cx, cy, -0.16), rotZ: -a);
    }

    // Car.
    _add('toy_car_body', p(1.10, 0.128, -0.30));
    for (final (double dx, double dz) in <(double, double)>[
      (0.105, 0.105), (0.105, -0.105), (-0.105, 0.105), (-0.105, -0.105),
    ]) {
      _add('toy_car_wheel', p(1.10 + dx, 0.058, -0.30 + dz));
    }

    // Celebration burst.
    const List<(String, double, double, double)> caps = <(String, double, double, double)>[
      ('capsule_yellow', 1.32, 0.86, 0.30),
      ('capsule_green', 1.55, 0.72, 0.22),
      ('capsule_duo', 1.42, 0.58, 0.10),
      ('capsule_red', 1.68, 0.50, 0.34),
      ('capsule_blue', 1.24, 0.66, 0.42),
      ('star', 1.50, 0.98, 0.05),
      ('coin', 1.72, 0.80, -0.10),
    ];
    for (final (String slug, double x, double y, double z) in caps) {
      _add(slug, p(x, y, z), rotZ: x * 3.1, rotX: z * 2.4);
    }
  }

  void _onFrame(double dt) {
    _t += dt;
    if (_orbit) {
      _camera.yaw = -0.34 + math.sin(_t * 0.35) * 0.22;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Toy.studio,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, style: const TextStyle(color: Toy.red, fontSize: 16)),
          ),
        ),
      );
    }
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Toy.studio,
        body: Center(child: CircularProgressIndicator(color: Toy.blue)),
      );
    }

    final GlobalKey<State<SceneView>> key = GlobalKey<State<SceneView>>();
    return Scaffold(
      backgroundColor: Toy.studio,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: SceneView(
              key: key,
              camera: _camera,
              instances: _instances,
              renderer: _renderer,
              onFrame: _onFrame,
              onPan: (Offset d) {
                _orbit = false;
                _camera.yaw -= d.dx * 0.005;
                _camera.pitch += d.dy * 0.005;
              },
            ),
          ),
          Positioned(
            left: 12,
            top: 44,
            child: _StatsPanel(renderer: _renderer, instances: _instances),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                for (final int n in <int>[1, 4, 8, 16])
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _copies == n ? Toy.blue : Toy.white,
                      foregroundColor: _copies == n ? Toy.white : Toy.ink,
                    ),
                    onPressed: () => setState(() {
                      _copies = n;
                      _camera.distance = 3.4 + (n - 1) * 0.55;
                      _rebuild();
                    }),
                    child: Text('x$n'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsPanel extends StatefulWidget {
  const _StatsPanel({required this.renderer, required this.instances});
  final Renderer renderer;
  final List<RenderInstance> instances;

  @override
  State<_StatsPanel> createState() => _StatsPanelState();
}

class _StatsPanelState extends State<_StatsPanel> {
  double _p50 = 0, _p95 = 0, _max = 0;
  final List<double> _samples = <double>[];

  @override
  void initState() {
    super.initState();
    _pump();
  }

  Future<void> _pump() async {
    while (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _samples.add(widget.renderer.stats.lastFrameMs);
      if (_samples.length > 80) _samples.removeAt(0);
      final List<double> s = List<double>.from(_samples)..sort();
      if (s.isNotEmpty) {
        _p50 = s[s.length ~/ 2];
        _p95 = s[(s.length * 0.95).floor().clamp(0, s.length - 1)];
        _max = s.last;
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final RenderStats st = widget.renderer.stats;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Toy.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Toy.inkStrong, fontSize: 12, height: 1.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('instances  ${st.instancesDrawn} / ${widget.instances.length}'),
            Text('tris  ${st.trianglesDrawn} drawn / ${st.trianglesSubmitted} sub'),
            Text('shadows  ${st.shadowsDrawn}'),
            Text('cpu ms  p50 ${_p50.toStringAsFixed(2)}  p95 ${_p95.toStringAsFixed(2)}'),
            Text('cpu ms  max ${_max.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }
}
