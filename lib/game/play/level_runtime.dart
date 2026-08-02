import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../../engine/assets/model_cache.dart';
import '../../engine/physics/body.dart';
import '../../engine/physics/world.dart';
import '../../engine/render/mesh.dart';
import '../../engine/render/render_instance.dart';
import '../../engine/render/scene_bounds.dart';
import '../level/level_spec.dart';
import 'devices.dart';
import 'level_object.dart';
import 'reaction_tracker.dart';
import 'scoring.dart';

enum RunPhase { inspecting, reacting, won, failed }

/// Owns one loaded level: its bodies, its instances, its devices and the
/// reaction being tracked across them.
///
/// The reset contract is the important part. [reset] restores every body
/// transform, every device latch and every tracker flag to spawn state and
/// wipes the solver's warm-start caches, so a retry re-runs the identical
/// simulation. That is what keeps "tap the same thing, get the same result"
/// true across an unlimited number of retries.
class LevelRuntime implements DeviceHost {
  LevelRuntime(this.spec)
    : world = PhysicsWorld(gravity: spec.gravity),
      tracker = ReactionTracker(spec);

  final LevelSpec spec;
  final PhysicsWorld world;
  final ReactionTracker tracker;

  final List<LevelObject> _objects = <LevelObject>[];
  final Map<String, LevelObject> _byId = <String, LevelObject>{};
  final Map<int, LevelObject> _byBodyId = <int, LevelObject>{};

  /// Live render list handed to the renderer, mutated in place.
  final List<RenderInstance> instances = <RenderInstance>[];

  final List<GameSignal> signals = <GameSignal>[];

  RunPhase phase = RunPhase.inspecting;
  double runTime = 0.0;
  double idleTime = 0.0;
  String? starterUsed;

  /// Bounds of the level at spawn, used to frame the camera.
  final SceneBounds bounds = SceneBounds();

  /// Emitted once the goal is reached and the celebration has had a beat.
  LevelResult? result;
  double _settleAfterWin = 0.0;

  static const double _impactThreshold = 0.012;
  static const double _stallSeconds = 2.4;

  @override
  Iterable<LevelObject> get objects => _objects;

  @override
  double get now => runTime;

  @override
  double get gravity => spec.gravity;

  @override
  LevelObject? find(String id) => _byId[id];

  @override
  void emit(GameSignal signal) => signals.add(signal);

  @override
  void activate(String id, {String? by}) {
    final LevelObject? o = _byId[id];
    if (o == null) {
      return;
    }
    final Device? d = o.device as Device?;
    if (d != null) {
      d.activate(this);
    } else {
      o.activated = true;
      o.activatedAt = runTime;
    }
    tracker.noteParticipation(id);
  }

  List<LevelObject> get starters =>
      _objects.where((LevelObject o) => o.isStarter).toList(growable: false);

  LevelObject? objectForBody(Body b) => _byBodyId[b.id];

  // ------------------------------------------------------------------ build
  /// Builds bodies and instances. Models must already be in [ModelCache].
  void build() {
    world.clear();
    _objects.clear();
    _byId.clear();
    _byBodyId.clear();
    instances.clear();
    signals.clear();
    bounds.reset();

    // Implicit studio floor. The renderer draws no floor geometry — the
    // backdrop is a seamless cyclorama — but contacts and shadows need a
    // plane at y = 0.
    world.create(
      kind: BodyKind.static_,
      shape: ShapeKind.box,
      position: Vector3(0, -0.5, 0),
      halfExtents: Vector3(40, 0.5, 40),
      friction: 0.62,
      restitution: 0.0,
      tag: 'floor',
      nodeId: '__floor',
    );

    for (final ObjectSpec o in spec.objects) {
      _buildObject(o);
    }

    for (final LevelObject o in _objects) {
      o.captureHome();
    }
    _syncInstances();
    bounds.addAll(instances);

    tracker.reset();
    phase = RunPhase.inspecting;
    runTime = 0;
    idleTime = 0;
    result = null;
    starterUsed = null;
    _settleAfterWin = 0;
  }

  void _buildObject(ObjectSpec o) {
    final LevelObject lo = LevelObject(spec: o);
    final Mesh? mesh = o.model == null
        ? null
        : ModelCache.instance.peek(o.model!);

    // ---- collider -------------------------------------------------------
    ShapeKind shape = ShapeKind.box;
    Vector3 half = Vector3(0.1, 0.1, 0.1);
    double radius = 0.1;

    if (o.shape == ColliderShape.sphere) {
      shape = ShapeKind.sphere;
      radius = o.radius ?? (mesh == null ? 0.1 : _meanRadius(mesh) * o.scale);
    } else if (o.shape == ColliderShape.box || o.shape == ColliderShape.auto) {
      shape = ShapeKind.box;
      if (o.halfExtents != null) {
        half = o.halfExtents! * o.scale;
      } else if (mesh != null) {
        half = Vector3(
          math.max(0.004, mesh.sizeX * 0.5 * o.scale),
          math.max(0.004, mesh.sizeY * 0.5 * o.scale),
          math.max(0.004, mesh.sizeZ * 0.5 * o.scale),
        );
      }
    }

    if (o.shape != ColliderShape.none) {
      final BodyKind kind = switch (o.kind) {
        ObjectKind.dynamicBody => BodyKind.dynamic_,
        ObjectKind.kinematic => BodyKind.kinematic,
        ObjectKind.staticBody => BodyKind.static_,
      };
      final Body b = world.create(
        kind: kind,
        shape: shape,
        position: Vector3.copy(o.position),
        orientation: o.orientation,
        halfExtents: half,
        radius: radius,
        mass: o.mass,
        friction: o.friction,
        restitution: o.restitution,
        tag: o.tag,
        nodeId: o.id,
        isSensor: o.sensor,
        gravityScale: o.gravityScale,
      );
      b.enabled = !o.hidden;
      lo.body = b;
      _byBodyId[b.id] = lo;
    }

    // ---- visuals --------------------------------------------------------
    if (mesh != null) {
      final Mesh use = o.colourOverride == null
          ? mesh
          : mesh.recoloured(o.colourOverride!);
      final RenderInstance ri = RenderInstance(
        mesh: use,
        castsShadow: o.castsShadow,
        visible: !o.hidden,
      );
      lo.instance = ri;
      instances.add(ri);
    }

    for (final AttachmentSpec a in o.attachments) {
      final Mesh? am = ModelCache.instance.peek(a.model);
      if (am == null) {
        continue;
      }
      final RenderInstance ri = RenderInstance(mesh: am, visible: !o.hidden);
      lo.attachments.add(ri);
      instances.add(ri);
    }

    // ---- device ---------------------------------------------------------
    if (o.device != null) {
      lo.device = Device.create(lo, o.device!);
    }

    _objects.add(lo);
    _byId[o.id] = lo;
  }

  static double _meanRadius(Mesh m) => (m.sizeX + m.sizeY + m.sizeZ) / 6.0;

  // ------------------------------------------------------------------ reset
  /// Restores the level to its exact spawn state.
  void reset() {
    world.resetSimulationState();
    for (final LevelObject o in _objects) {
      o.restoreHome();
      (o.device as Device?)?.reset();
    }
    tracker.reset();
    signals.clear();
    phase = RunPhase.inspecting;
    runTime = 0;
    idleTime = 0;
    result = null;
    starterUsed = null;
    _settleAfterWin = 0;
    _syncInstances();
  }

  // ------------------------------------------------------------------ input
  /// Attempts to begin the reaction by tapping a starter. Returns the id of
  /// the object that was started, or null.
  String? tapStarter(Vector3 rayOrigin, Vector3 rayDir) {
    if (phase != RunPhase.inspecting) {
      return null;
    }
    final Body? hit = world.raycast(
      rayOrigin,
      rayDir,
      120,
      filter: (Body b) {
        final LevelObject? o = _byBodyId[b.id];
        return o != null && o.isStarter && b.enabled;
      },
    );
    if (hit == null) {
      return null;
    }
    final LevelObject? o = _byBodyId[hit.id];
    if (o == null) {
      return null;
    }
    return start(o.id);
  }

  /// Begins the reaction from [id] without needing a ray. Used by tests and by
  /// the tutorial's auto-play.
  String? start(String id) {
    final LevelObject? o = _byId[id];
    if (o == null || !o.isStarter) {
      return null;
    }
    phase = RunPhase.reacting;
    starterUsed = id;
    runTime = 0;
    idleTime = 0;

    final Device? d = o.device as Device?;
    if (d != null) {
      d.activate(this);
    } else {
      o.activated = true;
      o.activatedAt = 0;
    }
    tracker.noteParticipation(id);
    for (final LevelObject lo in _objects) {
      lo.instance?.highlight = 0;
    }
    return id;
  }

  // ------------------------------------------------------------------ update
  final Set<String> _impactedThisTick = <String>{};

  void update(double dt) {
    signals.clear();

    if (phase == RunPhase.inspecting) {
      _pulseStarters(dt);
      _syncInstances();
      return;
    }

    runTime += dt;

    // 1. devices that push the simulation, before it steps
    for (final LevelObject o in _objects) {
      (o.device as Device?)?.update(this, dt);
    }

    // 2. simulate
    world.step(dt);
    world.collectImpacts(_impactThreshold);

    // 3. route contacts to devices, collectibles and the tracker
    _impactedThisTick.clear();
    for (final CollisionEvent e in world.events) {
      final LevelObject? a = _byBodyId[e.a.id];
      final LevelObject? b = _byBodyId[e.b.id];

      if (a != null) {
        _impactedThisTick.add(a.id);
        if (b != null) {
          (a.device as Device?)?.onImpact(this, e.b, e.impulse, e.point);
        }
        _maybeCollect(a, b);
      }
      if (b != null) {
        _impactedThisTick.add(b.id);
        if (a != null) {
          (b.device as Device?)?.onImpact(this, e.a, e.impulse, e.point);
        }
        _maybeCollect(b, a);
      }

      if (e.impulse >= _impactThreshold && a != null && b != null) {
        emit(
          GameSignal(
            SignalKind.impact,
            at: e.point,
            strength: e.impulse,
            objectId: a.id,
          ),
        );
      }
    }

    // 4. anything that moved meaningfully counts towards the chain
    for (final LevelObject o in _objects) {
      if (o.participated) {
        tracker.noteParticipation(o.id);
        continue;
      }
      if (o.displacement > 0.05 || o.tiltDegrees > 12) {
        o.participated = true;
        tracker.noteParticipation(o.id);
      }
    }

    // 5. advance the reaction graph
    tracker.update(dt, runTime, find, _impactedThisTick);

    // 6. resolve the run
    if (phase == RunPhase.reacting) {
      if (tracker.goalReached) {
        _settleAfterWin += dt;
        // Let the celebration breathe before the results screen.
        if (_settleAfterWin > 1.1) {
          _finish(won: true);
        }
      } else if (_isQuiet() && tracker.sinceLastEvent > _stallSeconds) {
        _finish(won: false);
      }
    }

    _syncInstances();
    _clearImpactMarks();
  }

  void _maybeCollect(LevelObject o, LevelObject? other) {
    if (o.spec.collectible == null || o.collected) {
      return;
    }
    // Only a moving participant collects; resting against a star does not.
    if (other == null || !(other.body?.isDynamic ?? false)) {
      return;
    }
    o.collected = true;
    o.instance?.visible = false;
    o.body?.enabled = false;
    emit(
      GameSignal(
        SignalKind.collect,
        at: o.body?.position,
        objectId: o.id,
        strength: o.spec.collectible == 'star' ? 1 : 0.5,
      ),
    );
  }

  /// True when nothing is meaningfully in motion any more.
  bool _isQuiet() {
    for (final LevelObject o in _objects) {
      final Body? b = o.body;
      if (b == null || !b.enabled || !b.isDynamic || b.sleeping) {
        continue;
      }
      if (b.linearVelocity.length2 > 0.006 ||
          b.angularVelocity.length2 > 0.05) {
        return false;
      }
    }
    // A device still running (a lift rising, a fan blowing) also counts as busy.
    for (final LevelObject o in _objects) {
      final Device? d = o.device as Device?;
      if (d is LifterDevice && d.running) {
        return false;
      }
      if (d is PusherDevice && d.fired && d.t < 1.0) {
        return false;
      }
    }
    return true;
  }

  void _finish({required bool won}) {
    phase = won ? RunPhase.won : RunPhase.failed;
    result = const Scoring().evaluate(
      level: spec,
      tracker: tracker,
      objects: _objects,
      timeSec: runTime,
      starterUsed: starterUsed,
      intendedStarter: _intendedStarter,
    );
    if (won) {
      emit(GameSignal(SignalKind.celebrate));
    }
  }

  String? get _intendedStarter {
    for (final ObjectSpec o in spec.objects) {
      if (o.starter && o.device?.flag('intended', fallback: false) == true) {
        return o.id;
      }
    }
    // Fall back to the first declared starter.
    for (final ObjectSpec o in spec.objects) {
      if (o.starter) {
        return o.id;
      }
    }
    return null;
  }

  void _clearImpactMarks() {
    for (final LevelObject o in _objects) {
      o.body?.lastImpactImpulse = 0;
    }
  }

  // ------------------------------------------------------------------ visual
  double _pulse = 0.0;

  void _pulseStarters(double dt) {
    _pulse += dt * 2.6;
    final double v = 0.5 + 0.5 * math.sin(_pulse);
    for (final LevelObject o in _objects) {
      if (o.isStarter) {
        o.instance?.highlight = 0.25 + v * 0.55;
      }
    }
  }

  /// Copies physics transforms into render transforms, and drives attachments.
  void _syncInstances() {
    for (final LevelObject o in _objects) {
      final Body? b = o.body;
      final RenderInstance? ri = o.instance;

      if (b != null && ri != null) {
        _composeInto(ri.transform, b.position, b.orientation, o.spec.scale);
        ri.visible = b.enabled && !o.collected;
      } else if (ri != null && b == null) {
        _composeInto(
          ri.transform,
          o.spec.position,
          o.spec.orientation,
          o.spec.scale,
        );
      }

      if (o.attachments.isEmpty) {
        continue;
      }
      // Wheels roll in proportion to how far the parent travelled.
      if (b != null) {
        final double speed = b.linearVelocity.length;
        o.spinAngle += speed * 0.016 * 6.0;
      }

      for (
        int i = 0;
        i < o.attachments.length && i < o.spec.attachments.length;
        i++
      ) {
        final AttachmentSpec a = o.spec.attachments[i];
        final RenderInstance ari = o.attachments[i];

        final Vector3 basePos = b?.position ?? o.spec.position;
        final Quaternion baseRot = b?.orientation ?? o.spec.orientation;

        final Vector3 offset = Vector3.copy(a.offset)..scale(o.spec.scale);
        baseRot.rotate(offset);
        final Vector3 world = basePos + offset;

        Quaternion rot = baseRot;
        if (a.rotation != null) {
          final Vector3 r = a.rotation!;
          rot =
              baseRot *
              Quaternion.euler(
                r.y * math.pi / 180,
                r.x * math.pi / 180,
                r.z * math.pi / 180,
              );
        }
        if (a.spin != SpinAxis.none) {
          final Vector3 axis = switch (a.spin) {
            SpinAxis.x => Vector3(1, 0, 0),
            SpinAxis.y => Vector3(0, 1, 0),
            _ => Vector3(0, 0, 1),
          };
          rot = rot * Quaternion.axisAngle(axis, o.spinAngle * a.spinScale);
        }

        _composeInto(ari.transform, world, rot, o.spec.scale);
        ari.visible = (b?.enabled ?? true) && (o.instance?.visible ?? true);
      }
    }
  }

  static void _composeInto(Matrix4 out, Vector3 p, Quaternion q, double scale) {
    out.setFromTranslationRotation(p, q);
    if (scale != 1.0) {
      out.scaleByVector3(Vector3.all(scale));
    }
  }
}
