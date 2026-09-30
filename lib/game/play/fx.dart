import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../engine/assets/model_cache.dart';
import '../../engine/render/camera.dart';
import '../../engine/render/mesh.dart';
import '../../engine/render/palette.dart';
import '../../engine/render/render_instance.dart';
import 'devices.dart';

/// Pooled particle and celebration effects.
///
/// Two kinds, chosen per effect for what reads best against a white studio
/// backdrop:
///
///  * **Screen-space puffs** — impact dust, sparks, pops. Soft translucent
///    discs drawn in the overlay pass. Cheap, and they stay legible at any
///    depth without fighting the depth sort.
///  * **World-space pieces** — confetti, capsules, stars, debris. Real 3D
///    instances so the celebration is made of the same toys as the game.
///
/// Everything is preallocated. Nothing is created during a reaction.
class FxSystem {
  FxSystem({this.maxPuffs = 96, this.maxPieces = 72});

  final int maxPuffs;
  final int maxPieces;

  // ---- screen-space puffs (world position, projected at draw time) -------
  late final Float64List _puffPos = Float64List(maxPuffs * 3);
  late final Float64List _puffVel = Float64List(maxPuffs * 3);
  late final Float32List _puffLife = Float32List(maxPuffs);
  late final Float32List _puffMax = Float32List(maxPuffs);
  late final Float32List _puffSize = Float32List(maxPuffs);
  late final Int32List _puffColour = Int32List(maxPuffs);
  int _puffCursor = 0;

  // ---- world-space celebration pieces ------------------------------------
  final List<RenderInstance> pieceInstances = <RenderInstance>[];
  late final Float64List _piecePos = Float64List(maxPieces * 3);
  late final Float64List _pieceVel = Float64List(maxPieces * 3);
  late final Float64List _pieceSpin = Float64List(maxPieces * 3);
  late final Float64List _pieceAngle = Float64List(maxPieces * 3);
  late final Float32List _pieceLife = Float32List(maxPieces);
  late final Float32List _pieceMax = Float32List(maxPieces);
  int _pieceCursor = 0;
  bool _piecesReady = false;

  /// Deterministic pseudo-random source.
  ///
  /// Effects must not use `Random()`: two replays of the same reaction have to
  /// look the same, and a wall-clock-seeded RNG would break that. This is a
  /// plain counter-driven hash, reset with the level.
  int _seed = 0x9E3779B9;

  double _rand() {
    _seed = (_seed * 1664525 + 1013904223) & 0x7FFFFFFF;
    return _seed / 0x7FFFFFFF;
  }

  double _sym() => _rand() * 2.0 - 1.0;

  void reset() {
    _seed = 0x9E3779B9;
    _puffLife.fillRange(0, maxPuffs, 0);
    _pieceLife.fillRange(0, maxPieces, 0);
    for (final RenderInstance i in pieceInstances) {
      i.visible = false;
    }
  }

  /// Builds the celebration piece pool from the loaded models. Safe to call
  /// more than once; only the first call allocates.
  void preparePieces(List<RenderInstance> sceneInstances) {
    if (_piecesReady) return;
    const List<String> slugs = <String>[
      'confetti',
      'capsule_yellow',
      'capsule_green',
      'capsule_blue',
      'capsule_red',
      'capsule_orange',
      'capsule_purple',
      'capsule_duo',
      'star',
    ];
    final List<Mesh> meshes = <Mesh>[];
    for (final String s in slugs) {
      final Mesh? m = ModelCache.instance.peek(s);
      if (m != null) meshes.add(m);
    }
    if (meshes.isEmpty) return;

    for (int i = 0; i < maxPieces; i++) {
      final RenderInstance ri = RenderInstance(
        mesh: meshes[i % meshes.length],
        visible: false,
        castsShadow: false,
      );
      pieceInstances.add(ri);
      sceneInstances.add(ri);
    }
    _piecesReady = true;
  }

  // ------------------------------------------------------------------ spawn
  void puff(
    Vector3 at, {
    int count = 6,
    double speed = 0.5,
    Color? colour,
    double size = 12,
  }) {
    final int argb = Toy.argb(colour ?? Toy.greyDark);
    for (int i = 0; i < count; i++) {
      final int k = _puffCursor;
      _puffCursor = (_puffCursor + 1) % maxPuffs;
      final int o = k * 3;
      _puffPos[o] = at.x;
      _puffPos[o + 1] = at.y;
      _puffPos[o + 2] = at.z;
      _puffVel[o] = _sym() * speed;
      _puffVel[o + 1] = (0.25 + _rand() * 0.75) * speed;
      _puffVel[o + 2] = _sym() * speed;
      final double life = 0.28 + _rand() * 0.34;
      _puffLife[k] = life;
      _puffMax[k] = life;
      _puffSize[k] = size * (0.6 + _rand() * 0.8);
      _puffColour[k] = argb;
    }
  }

  /// Reaction feedback, mapped from a gameplay signal.
  void onSignal(GameSignal s) {
    final Vector3? at = s.at;
    if (at == null) return;
    switch (s.kind) {
      case SignalKind.impact:
        puff(
          at,
          count: 4,
          speed: 0.45,
          colour: Toy.greyDark,
          size: 8 + s.strength.clamp(0.0, 1.0) * 16,
        );
      case SignalKind.cannonFire:
        puff(at, count: 12, speed: 1.0, colour: Toy.grey, size: 20);
      case SignalKind.buttonPress:
        puff(at, count: 8, speed: 0.5, colour: Toy.red, size: 12);
      case SignalKind.springLaunch:
        puff(at, count: 8, speed: 0.8, colour: Toy.orange, size: 12);
      case SignalKind.balloonPop:
        puff(at, count: 14, speed: 1.1, colour: Toy.pink, size: 14);
      case SignalKind.breakGlass:
        puff(at, count: 14, speed: 0.9, colour: Toy.cyan, size: 10);
      case SignalKind.breakBlock:
        puff(at, count: 12, speed: 0.8, colour: Toy.wood, size: 14);
      case SignalKind.splash:
        puff(at, count: 12, speed: 0.7, colour: Toy.water, size: 16);
      case SignalKind.magnetPulse:
        puff(at, count: 10, speed: 0.6, colour: Toy.purple, size: 14);
      case SignalKind.spark:
        puff(at, count: 8, speed: 0.9, colour: Toy.yellow, size: 8);
      case SignalKind.collect:
        puff(at, count: 10, speed: 0.6, colour: Toy.yellow, size: 12);
      default:
        puff(at, count: 5, speed: 0.5, size: 10);
    }
  }

  /// The level-complete burst: toy pieces thrown up around [at].
  void celebrate(Vector3 at, {int count = 48}) {
    if (!_piecesReady) return;
    for (int i = 0; i < count && i < maxPieces; i++) {
      final int k = _pieceCursor;
      _pieceCursor = (_pieceCursor + 1) % maxPieces;
      final int o = k * 3;

      final double ang = _rand() * math.pi * 2;
      final double spread = 0.6 + _rand() * 1.5;
      _piecePos[o] = at.x + math.cos(ang) * 0.10;
      _piecePos[o + 1] = at.y + 0.10 + _rand() * 0.15;
      _piecePos[o + 2] = at.z + math.sin(ang) * 0.10;

      _pieceVel[o] = math.cos(ang) * spread * 0.55;
      _pieceVel[o + 1] = 2.1 + _rand() * 1.7;
      _pieceVel[o + 2] = math.sin(ang) * spread * 0.55;

      _pieceSpin[o] = _sym() * 9;
      _pieceSpin[o + 1] = _sym() * 9;
      _pieceSpin[o + 2] = _sym() * 9;
      _pieceAngle[o] = _rand() * 6.28;
      _pieceAngle[o + 1] = _rand() * 6.28;
      _pieceAngle[o + 2] = _rand() * 6.28;

      final double life = 1.9 + _rand() * 1.3;
      _pieceLife[k] = life;
      _pieceMax[k] = life;
      pieceInstances[k].visible = true;
    }
  }

  // ----------------------------------------------------------------- update
  void update(double dt, {double groundY = 0.0}) {
    for (int k = 0; k < maxPuffs; k++) {
      if (_puffLife[k] <= 0) continue;
      _puffLife[k] -= dt;
      final int o = k * 3;
      _puffPos[o] += _puffVel[o] * dt;
      _puffPos[o + 1] += _puffVel[o + 1] * dt;
      _puffPos[o + 2] += _puffVel[o + 2] * dt;
      _puffVel[o + 1] -= 1.6 * dt;
      final double drag = 1.0 - math.min(0.6, dt * 2.2);
      _puffVel[o] *= drag;
      _puffVel[o + 1] *= drag;
      _puffVel[o + 2] *= drag;
    }

    if (!_piecesReady) return;
    for (int k = 0; k < maxPieces; k++) {
      final RenderInstance ri = pieceInstances[k];
      if (_pieceLife[k] <= 0) {
        if (ri.visible) ri.visible = false;
        continue;
      }
      _pieceLife[k] -= dt;
      final int o = k * 3;

      _pieceVel[o + 1] -= 6.2 * dt;
      _piecePos[o] += _pieceVel[o] * dt;
      _piecePos[o + 1] += _pieceVel[o + 1] * dt;
      _piecePos[o + 2] += _pieceVel[o + 2] * dt;

      // Bounce once off the floor, then settle — the reference art's pieces
      // land and stay put rather than vanishing mid-air.
      if (_piecePos[o + 1] < groundY + 0.03) {
        _piecePos[o + 1] = groundY + 0.03;
        if (_pieceVel[o + 1] < -0.35) {
          _pieceVel[o + 1] = -_pieceVel[o + 1] * 0.38;
          _pieceVel[o] *= 0.55;
          _pieceVel[o + 2] *= 0.55;
        } else {
          _pieceVel[o + 1] = 0;
          _pieceVel[o] *= 0.86;
          _pieceVel[o + 2] *= 0.86;
          _pieceSpin[o] *= 0.86;
          _pieceSpin[o + 1] *= 0.86;
          _pieceSpin[o + 2] *= 0.86;
        }
      }

      _pieceAngle[o] += _pieceSpin[o] * dt;
      _pieceAngle[o + 1] += _pieceSpin[o + 1] * dt;
      _pieceAngle[o + 2] += _pieceSpin[o + 2] * dt;

      ri.visible = true;
      ri.opacity = math.min(1.0, _pieceLife[k] / 0.5);
      ri.transform
        ..setIdentity()
        ..setTranslationRaw(_piecePos[o], _piecePos[o + 1], _piecePos[o + 2])
        ..rotateY(_pieceAngle[o + 1])
        ..rotateX(_pieceAngle[o])
        ..rotateZ(_pieceAngle[o + 2]);
    }
  }

  // ------------------------------------------------------------------ guides
  final Paint _guide = Paint()..isAntiAlias = true;

  /// Projects a world point to screen. Returns null if it is behind the eye.
  static Offset? _project(
    Float64List vp,
    Vector3 p,
    double halfW,
    double halfH,
  ) {
    final double cw = vp[3] * p.x + vp[7] * p.y + vp[11] * p.z + vp[15];
    if (cw < 0.05) return null;
    final double cx = vp[0] * p.x + vp[4] * p.y + vp[8] * p.z + vp[12];
    final double cy = vp[1] * p.x + vp[5] * p.y + vp[9] * p.z + vp[13];
    final double inv = 1.0 / cw;
    return Offset(halfW + cx * inv * halfW, halfH - cy * inv * halfH);
  }

  /// Dotted trajectory showing exactly where a shot will go.
  ///
  /// Drawn as discrete dots rather than a line on purpose: dots read as a
  /// *prediction* rather than a wall, they stay legible over any colour, and
  /// their spacing communicates speed — bunched at the apex, stretched on the
  /// way down.
  void drawAimArc(
    ui.Canvas canvas,
    ui.Size size,
    OrbitCamera camera,
    List<Vector3> points,
    double time, {
    double accuracy = 1.0,
  }) {
    if (points.length < 2) return;
    // Warms from slate to green as the barrel swings onto the line the level
    // was built around, so a good shot is readable before committing to it.
    final Color tint = Color.lerp(Toy.inkStrong, Toy.green, accuracy)!;
    final Float64List vp = camera.viewProj.storage;
    final double halfW = size.width * 0.5;
    final double halfH = size.height * 0.5;

    // A slow crawl along the arc so it reads as live rather than painted on.
    final double phase = (time * 1.6) % 1.0;

    for (int i = 1; i < points.length; i++) {
      final Offset? s = _project(vp, points[i], halfW, halfH);
      if (s == null) continue;

      final double along = i / (points.length - 1);
      final double fade = (1.0 - along * 0.55).clamp(0.0, 1.0);
      final double pulse =
          0.55 + 0.45 * math.sin((along * 7.0 - phase * 6.283) * 1.0);

      _guide.color = tint.withValues(
        alpha: (0.26 + 0.22 * accuracy) * fade * pulse,
      );
      canvas.drawCircle(s, 3.4 * fade + 1.2, _guide);
    }

    // A solid marker on the landing point tells the player what gets hit.
    final Offset? end = _project(vp, points.last, halfW, halfH);
    if (end != null) {
      final double r = 9 + math.sin(time * 4.2) * 2.0 + accuracy * 3.0;
      _guide
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 + accuracy * 1.4
        ..color = tint.withValues(alpha: 0.45 + 0.35 * accuracy);
      canvas.drawCircle(end, r, _guide);
      _guide.style = PaintingStyle.fill;
    }
  }

  /// Pulsing ring on the ground under each object the player may tap.
  ///
  /// The 3D highlight alone is ambiguous on a white set — a brighter object
  /// could just be catching the light. A ring on the floor cannot be mistaken
  /// for anything but an affordance.
  void drawStarterRings(
    ui.Canvas canvas,
    ui.Size size,
    OrbitCamera camera,
    List<Vector3> groundPoints,
    double time,
  ) {
    if (groundPoints.isEmpty) return;
    final Float64List vp = camera.viewProj.storage;
    final double halfW = size.width * 0.5;
    final double halfH = size.height * 0.5;

    for (final Vector3 g in groundPoints) {
      final Offset? c = _project(vp, g, halfW, halfH);
      if (c == null) continue;
      // Sample a second point one ring-radius away in world space so the ring
      // scales with perspective instead of being a fixed pixel size.
      final Offset? edge = _project(
        vp,
        Vector3(g.x + 0.26, g.y, g.z),
        halfW,
        halfH,
      );
      if (edge == null) continue;
      final double rx = (edge - c).distance;
      if (rx < 2 || rx > 400) continue;

      for (int k = 0; k < 2; k++) {
        final double t = ((time * 0.85) + k * 0.5) % 1.0;
        final double grow = 0.55 + t * 0.65;
        _guide
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * (1.0 - t)
          ..color = Toy.blue.withValues(alpha: 0.42 * (1.0 - t));
        canvas.drawOval(
          Rect.fromCenter(
            center: c,
            width: rx * 2 * grow,
            height: rx * 0.92 * grow,
          ),
          _guide,
        );
      }
      _guide.style = PaintingStyle.fill;
    }
  }

  // ------------------------------------------------------------------- draw
  final Paint _paint = Paint()..isAntiAlias = true;

  /// Overlay pass: projects live puffs to screen and draws them.
  void draw(ui.Canvas canvas, ui.Size size, OrbitCamera camera) {
    final Float64List vp = camera.viewProj.storage;
    final double halfW = size.width * 0.5;
    final double halfH = size.height * 0.5;

    for (int k = 0; k < maxPuffs; k++) {
      final double life = _puffLife[k];
      if (life <= 0) continue;
      final int o = k * 3;
      final double x = _puffPos[o], y = _puffPos[o + 1], z = _puffPos[o + 2];

      final double cw = vp[3] * x + vp[7] * y + vp[11] * z + vp[15];
      if (cw < 0.05) continue;
      final double cx = vp[0] * x + vp[4] * y + vp[8] * z + vp[12];
      final double cy = vp[1] * x + vp[5] * y + vp[9] * z + vp[13];
      final double inv = 1.0 / cw;
      final double sx = halfW + cx * inv * halfW;
      final double sy = halfH - cy * inv * halfH;

      final double t = (life / _puffMax[k]).clamp(0.0, 1.0);
      // Grow while fading: reads as dispersing dust rather than a shrinking dot.
      final double r = _puffSize[k] * (1.35 - t * 0.55) * inv * 2.2;
      final int c = _puffColour[k];
      _paint.color = Color.fromARGB(
        (t * t * 150).round(),
        (c >> 16) & 0xff,
        (c >> 8) & 0xff,
        c & 0xff,
      );
      canvas.drawCircle(Offset(sx, sy), math.max(1.0, r), _paint);
    }
  }
}
