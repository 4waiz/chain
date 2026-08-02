import 'dart:convert';
import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// Physics body role for a level object.
enum ObjectKind { staticBody, kinematic, dynamicBody }

/// Collider shape. `auto` derives a box from the model's bounding box.
enum ColliderShape { auto, box, sphere, none }

ObjectKind _kindFrom(String? s) => switch (s) {
  'dynamic' => ObjectKind.dynamicBody,
  'kinematic' => ObjectKind.kinematic,
  _ => ObjectKind.staticBody,
};

ColliderShape _shapeFrom(String? s) => switch (s) {
  'box' => ColliderShape.box,
  'sphere' => ColliderShape.sphere,
  'none' => ColliderShape.none,
  _ => ColliderShape.auto,
};

Vector3 _vec(dynamic v, [Vector3? fallback]) {
  if (v is List && v.length >= 3) {
    return Vector3(
      (v[0] as num).toDouble(),
      (v[1] as num).toDouble(),
      (v[2] as num).toDouble(),
    );
  }
  return fallback ?? Vector3.zero();
}

double _num(dynamic v, double fallback) => v is num ? v.toDouble() : fallback;

/// A visual-only child attached to a parent object — car wheels, cannon
/// wheels, a flag on a pole. These render and animate but carry no collider,
/// which keeps the physics body count low.
class AttachmentSpec {
  AttachmentSpec({
    required this.model,
    required this.offset,
    this.rotation,
    this.spin = SpinAxis.none,
    this.spinScale = 1.0,
  });

  final String model;
  final Vector3 offset;
  final Vector3? rotation;

  /// Which local axis this part rolls about, derived from the parent's motion.
  final SpinAxis spin;
  final double spinScale;

  factory AttachmentSpec.fromJson(Map<String, dynamic> j) => AttachmentSpec(
    model: j['model'] as String,
    offset: _vec(j['offset']),
    rotation: j['rot'] == null ? null : _vec(j['rot']),
    spin: switch (j['spin'] as String?) {
      'x' => SpinAxis.x,
      'y' => SpinAxis.y,
      'z' => SpinAxis.z,
      _ => SpinAxis.none,
    },
    spinScale: _num(j['spinScale'], 1.0),
  );
}

enum SpinAxis { none, x, y, z }

/// Everything the game needs to build one object in a level.
class ObjectSpec {
  ObjectSpec({
    required this.id,
    this.model,
    this.kind = ObjectKind.staticBody,
    this.shape = ColliderShape.auto,
    Vector3? position,
    Vector3? rotationDeg,
    this.scale = 1.0,
    this.mass = 1.0,
    this.friction = 0.55,
    this.restitution = 0.06,
    this.halfExtents,
    this.radius,
    this.sensor = false,
    this.tag = '',
    this.starter = false,
    this.device,
    this.attachments = const <AttachmentSpec>[],
    this.collectible,
    this.castsShadow = true,
    this.gravityScale = 1.0,
    this.colourOverride,
    this.hidden = false,
  }) : position = position ?? Vector3.zero(),
       rotationDeg = rotationDeg ?? Vector3.zero();

  final String id;

  /// GLB slug under `assets/models/`. Null means an invisible collider or
  /// trigger volume.
  final String? model;

  final ObjectKind kind;
  final ColliderShape shape;
  final Vector3 position;
  final Vector3 rotationDeg;
  final double scale;

  final double mass;
  final double friction;
  final double restitution;

  /// Explicit collider half-extents / radius, overriding the model bounds.
  final Vector3? halfExtents;
  final double? radius;

  final bool sensor;
  final String tag;

  /// Whether the player may tap this to begin the reaction.
  final bool starter;

  final DeviceSpec? device;
  final List<AttachmentSpec> attachments;

  /// 'star' or 'coin' — awarded when touched during a reaction.
  final String? collectible;

  final bool castsShadow;
  final double gravityScale;

  /// Recolours a material slot at load time, used by cosmetics.
  final Map<int, int>? colourOverride;

  /// Spawned hidden — projectiles waiting in a cannon, debris waiting to be
  /// revealed when a breakable shatters.
  final bool hidden;

  Quaternion get orientation {
    final double rx = rotationDeg.x * math.pi / 180.0;
    final double ry = rotationDeg.y * math.pi / 180.0;
    final double rz = rotationDeg.z * math.pi / 180.0;
    return Quaternion.euler(ry, rx, rz);
  }

  factory ObjectSpec.fromJson(Map<String, dynamic> j) {
    Map<int, int>? colours;
    final dynamic co = j['colours'];
    if (co is Map) {
      colours = <int, int>{};
      co.forEach((dynamic k, dynamic v) {
        colours![int.parse(k as String)] = (v as num).toInt();
      });
    }
    return ObjectSpec(
      id: j['id'] as String,
      model: j['model'] as String?,
      kind: _kindFrom(j['kind'] as String?),
      shape: _shapeFrom(j['shape'] as String?),
      position: _vec(j['pos']),
      rotationDeg: _vec(j['rot']),
      scale: _num(j['scale'], 1.0),
      mass: _num(j['mass'], 1.0),
      friction: _num(j['friction'], 0.55),
      restitution: _num(j['restitution'], 0.06),
      halfExtents: j['size'] == null ? null : _vec(j['size']),
      radius: j['radius'] == null ? null : _num(j['radius'], 0.1),
      sensor: j['sensor'] == true,
      tag: (j['tag'] as String?) ?? '',
      starter: j['starter'] == true,
      device: j['device'] == null
          ? null
          : DeviceSpec.fromJson(j['device'] as Map<String, dynamic>),
      attachments: ((j['attach'] as List<dynamic>?) ?? const <dynamic>[])
          .map(
            (dynamic a) => AttachmentSpec.fromJson(a as Map<String, dynamic>),
          )
          .toList(growable: false),
      collectible: j['collect'] as String?,
      castsShadow: j['shadow'] != false,
      gravityScale: _num(j['gravityScale'], 1.0),
      colourOverride: colours,
      hidden: j['hidden'] == true,
    );
  }
}

/// A scripted behaviour attached to an object.
///
/// Devices are what keep reactions readable. Pure physics is used wherever it
/// is stable and satisfying — falling dominoes, rolling balls, tipping
/// seesaws — and a device takes over wherever raw simulation would be fragile
/// or random, such as a cannon's muzzle velocity or a flag rising on cue.
class DeviceSpec {
  DeviceSpec({required this.type, required this.params});

  final String type;
  final Map<String, dynamic> params;

  double number(String key, double fallback) => _num(params[key], fallback);
  int integer(String key, int fallback) =>
      params[key] is num ? (params[key] as num).toInt() : fallback;
  bool flag(String key, {bool fallback = false}) =>
      params[key] is bool ? params[key] as bool : fallback;
  String? text(String key) => params[key] as String?;
  Vector3 vector(String key, [Vector3? fallback]) =>
      _vec(params[key], fallback);

  List<String> ids(String key) {
    final dynamic v = params[key];
    if (v is List) {
      return v.map((dynamic e) => e.toString()).toList(growable: false);
    }
    if (v is String) {
      return <String>[v];
    }
    return const <String>[];
  }

  factory DeviceSpec.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> p = Map<String, dynamic>.from(j);
    p.remove('type');
    return DeviceSpec(type: j['type'] as String, params: p);
  }
}

/// One stage of the expected reaction.
///
/// The graph does not drive the simulation — physics does. It describes the
/// chain so the game can follow it with the camera, score its length, detect a
/// stall, and validate at author time that the level is actually connected.
class ReactionStageSpec {
  ReactionStageSpec({
    required this.id,
    required this.watch,
    this.after = const <String>[],
    this.trigger = 'moved',
    this.threshold = 0.0,
    this.label,
    this.cameraFocus,
    this.timeoutSec = 6.0,
  });

  final String id;

  /// Object ids whose behaviour marks this stage as reached.
  final List<String> watch;

  /// Stage ids that must fire first.
  final List<String> after;

  /// 'moved' | 'impact' | 'activated' | 'fell' | 'entered' | 'destroyed'
  final String trigger;

  /// Meaning depends on [trigger]: impulse for 'impact', distance for 'moved',
  /// tilt in degrees for 'fell'.
  final double threshold;

  final String? label;

  /// Object the camera should favour while this stage is live.
  final String? cameraFocus;

  /// How long this stage may stay pending before the reaction counts as
  /// stalled.
  final double timeoutSec;

  factory ReactionStageSpec.fromJson(Map<String, dynamic> j) =>
      ReactionStageSpec(
        id: j['id'] as String,
        watch: ((j['watch'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        after: ((j['after'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        trigger: (j['trigger'] as String?) ?? 'moved',
        threshold: _num(j['threshold'], 0.0),
        label: j['label'] as String?,
        cameraFocus: j['focus'] as String?,
        timeoutSec: _num(j['timeout'], 6.0),
      );
}

/// A secondary objective worth the second star.
class BonusSpec {
  BonusSpec({
    required this.id,
    required this.type,
    required this.description,
    this.target,
    this.value = 0,
  });

  final String id;

  /// 'collect_all' | 'activate' | 'break_all' | 'intended_starter' |
  /// 'no_stall' | 'under_time' | 'chain_at_least'
  final String type;
  final String description;
  final String? target;
  final double value;

  factory BonusSpec.fromJson(Map<String, dynamic> j) => BonusSpec(
    id: j['id'] as String,
    type: j['type'] as String,
    description: (j['desc'] as String?) ?? '',
    target: j['target'] as String?,
    value: _num(j['value'], 0),
  );
}

class CameraSpec {
  /// Defaults tuned for a portrait phone.
  ///
  /// Levels run left-to-right and are much wider than they are deep, while the
  /// screen is much taller than it is wide. Two things fix that. A wider
  /// vertical FOV widens the horizontal one too (fovX is derived from fovY and
  /// the aspect, and on a 9:20 screen the horizontal is the binding
  /// constraint). And a yaw further round from head-on throws the level's long
  /// axis diagonally across the frame instead of straight across its narrow
  /// width.
  const CameraSpec({
    this.yaw = -0.86,
    this.pitch = 0.50,
    this.pad = 1.06,
    this.verticalBias = 0.10,
    this.fov = 0.75,
    this.orbit = 0.14,
  });

  final double yaw;
  final double pitch;

  /// Framing slack around the level bounds.
  final double pad;
  final double verticalBias;
  final double fov;

  /// Amplitude of the gentle pre-tap orbit, radians.
  final double orbit;

  factory CameraSpec.fromJson(Map<String, dynamic>? j) {
    if (j == null) {
      return const CameraSpec();
    }
    return CameraSpec(
      yaw: _num(j['yaw'], -0.62),
      pitch: _num(j['pitch'], 0.46),
      pad: _num(j['pad'], 1.18),
      verticalBias: _num(j['bias'], 0.10),
      fov: _num(j['fov'], 0.52),
      orbit: _num(j['orbit'], 0.16),
    );
  }
}

/// A complete, self-describing level.
class LevelSpec {
  LevelSpec({
    required this.id,
    required this.world,
    required this.index,
    required this.name,
    required this.objects,
    required this.stages,
    required this.goalObject,
    this.bonuses = const <BonusSpec>[],
    this.camera = const CameraSpec(),
    this.gravity = -9.81,
    this.parChain = 8,
    this.parTimeSec = 12.0,
    this.hint = '',
    this.teaches = const <String>[],
  });

  final String id;
  final int world;
  final int index;
  final String name;

  final List<ObjectSpec> objects;
  final List<ReactionStageSpec> stages;

  /// The object whose activation completes the level.
  final String goalObject;

  final List<BonusSpec> bonuses;
  final CameraSpec camera;
  final double gravity;

  /// Chain length that earns full marks, and the time target for the speed
  /// bonus.
  final int parChain;
  final double parTimeSec;

  /// Shown only after repeated failures.
  final String hint;

  /// Mechanic tags introduced here, used by the campaign pacing report.
  final List<String> teaches;

  ObjectSpec? object(String id) {
    for (final ObjectSpec o in objects) {
      if (o.id == id) {
        return o;
      }
    }
    return null;
  }

  Iterable<ObjectSpec> get starters =>
      objects.where((ObjectSpec o) => o.starter);

  /// Every model slug this level needs, for preloading.
  Set<String> get requiredModels {
    final Set<String> s = <String>{};
    for (final ObjectSpec o in objects) {
      if (o.model != null) {
        s.add(o.model!);
      }
      for (final AttachmentSpec a in o.attachments) {
        s.add(a.model);
      }
      // Ammo and debris are ordinary objects in the level with their own
      // `model` fields, so they are already covered by the loop above.
    }
    return s;
  }

  factory LevelSpec.fromJson(Map<String, dynamic> j) => LevelSpec(
    id: j['id'] as String,
    world: (j['world'] as num).toInt(),
    index: (j['index'] as num).toInt(),
    name: (j['name'] as String?) ?? '',
    objects: ((j['objects'] as List<dynamic>?) ?? const <dynamic>[])
        .map((dynamic o) => ObjectSpec.fromJson(o as Map<String, dynamic>))
        .toList(growable: false),
    stages: ((j['stages'] as List<dynamic>?) ?? const <dynamic>[])
        .map(
          (dynamic s) => ReactionStageSpec.fromJson(s as Map<String, dynamic>),
        )
        .toList(growable: false),
    goalObject: (j['goal'] as String?) ?? '',
    bonuses: ((j['bonus'] as List<dynamic>?) ?? const <dynamic>[])
        .map((dynamic b) => BonusSpec.fromJson(b as Map<String, dynamic>))
        .toList(growable: false),
    camera: CameraSpec.fromJson(j['camera'] as Map<String, dynamic>?),
    gravity: _num(j['gravity'], -9.81),
    parChain: (j['parChain'] as num?)?.toInt() ?? 8,
    parTimeSec: _num(j['parTime'], 12.0),
    hint: (j['hint'] as String?) ?? '',
    teaches: ((j['teaches'] as List<dynamic>?) ?? const <dynamic>[])
        .map((dynamic e) => e.toString())
        .toList(growable: false),
  );

  static LevelSpec parse(String source) =>
      LevelSpec.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
