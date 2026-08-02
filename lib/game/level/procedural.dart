import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'level_spec.dart';

/// A small, fully deterministic PRNG.
///
/// The daily puzzle has to be identical for every player and reproducible
/// offline, so generation never touches `Random()` or the system clock beyond
/// the date the seed is derived from.
class Rng {
  Rng(int seed) : _s = (seed == 0 ? 0x9E3779B9 : seed) & 0x7FFFFFFF;
  int _s;

  int nextInt(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return max <= 0 ? 0 : (_s >> 8) % max;
  }

  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return (_s >> 8) / 0x7FFFFF;
  }

  double range(double a, double b) => a + next() * (b - a);
  T pick<T>(List<T> xs) => xs[nextInt(xs.length)];
  bool chance(double p) => next() < p;
}

/// Builds daily challenges and Reaction Lab runs out of modular sections.
///
/// Each section is a self-contained chunk of chain — a domino run, a ramp and
/// ball, a spring hop — that hands off along +X to the next one. Because the
/// hand-off point and momentum are fixed by the section contract, sections can
/// be shuffled freely and the result is always solvable.
class ProceduralLevels {
  const ProceduralLevels._();

  static const List<String> _dominoColours = <String>[
    'domino_red',
    'domino_blue',
    'domino_yellow',
    'domino_green',
  ];

  /// Stable YYYY-MM-DD key for a date.
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Deterministic seed from a date. Same day, same puzzle, everywhere.
  static int seedForDay(DateTime d) {
    final int n = d.year * 10000 + d.month * 100 + d.day;
    int h = 0x811C9DC5;
    for (int i = 0; i < 8; i++) {
      h ^= (n >> (i * 4)) & 0xF;
      h = (h * 16777619) & 0x7FFFFFFF;
    }
    return h;
  }

  static LevelSpec daily(DateTime date) => _generate(
    id: 'daily_${dayKey(date)}',
    seed: seedForDay(date),
    sections: 4,
    name: 'Daily Challenge',
    world: 0,
  );

  /// Reaction Lab: longer, and its length grows with the run number so the
  /// mode keeps escalating.
  static LevelSpec lab(int seed, int runIndex) => _generate(
    id: 'lab_$runIndex',
    seed: seed,
    sections: (4 + runIndex).clamp(4, 8),
    name: 'Reaction Lab',
    world: 0,
  );

  // --------------------------------------------------------------- builder
  static LevelSpec _generate({
    required String id,
    required int seed,
    required int sections,
    required String name,
    required int world,
  }) {
    final Rng r = Rng(seed);
    final List<ObjectSpec> objects = <ObjectSpec>[];
    final List<ReactionStageSpec> stages = <ReactionStageSpec>[];

    double x = -1.75;
    int n = 0;
    String? previousStage;

    // Every run opens with the cannon, so the tap target is never ambiguous.
    final double aim = r.range(11, 17);
    final double power = r.range(4.3, 4.9);
    objects.addAll(_cannon('c', x, aim, power));
    stages.add(
      ReactionStageSpec(
        id: 's0',
        watch: <String>['c_ball'],
        trigger: 'moved',
        threshold: 0.15,
        cameraFocus: 'c_ball',
        label: 'Cannon fires',
      ),
    );
    previousStage = 's0';
    x += 0.95;

    final List<String> kinds = <String>[
      'dominoes',
      'dominoes',
      'ramp',
      'spring',
      'blocks',
    ];

    for (int i = 0; i < sections; i++) {
      final String kind = i == 0 ? 'dominoes' : r.pick(kinds);
      final String sid = 's${i + 1}';
      final (double, String) out = switch (kind) {
        'ramp' => _rampSection(objects, 'r$n', x, r),
        'spring' => _springSection(objects, 'p$n', x, r),
        'blocks' => _blockSection(objects, 'b$n', x, r),
        _ => _dominoSection(objects, 'd$n', x, r),
      };
      x = out.$1;
      stages.add(
        ReactionStageSpec(
          id: sid,
          watch: <String>[out.$2],
          after: <String>[previousStage!],
          trigger: 'moved',
          threshold: 0.07,
          cameraFocus: out.$2,
          label: 'Section ${i + 1}',
          timeoutSec: 7.0,
        ),
      );
      previousStage = sid;
      n++;
    }

    // Finish: a big button that raises a flag.
    objects.add(
      ObjectSpec(
        id: 'finish',
        model: 'push_button',
        position: Vector3(x + 0.30, 0.0625, 0),
        device: DeviceSpec(
          type: 'button',
          params: <String, dynamic>{
            'minImpulse': 0.008,
            'activates': <String>['goalflag'],
          },
        ),
      ),
    );
    objects.add(
      ObjectSpec(
        id: 'goalflag_pole',
        model: 'flag_base',
        position: Vector3(x + 0.78, 0.3688, 0),
      ),
    );
    objects.add(
      ObjectSpec(
        id: 'goalflag',
        model: 'flag_cloth',
        kind: ObjectKind.kinematic,
        shape: ColliderShape.none,
        position: Vector3(x + 0.80, 0.16, 0),
        device: DeviceSpec(
          type: 'lifter',
          params: <String, dynamic>{
            'travel': <double>[0, 0.48, 0],
            'duration': 0.85,
            'isFlag': true,
          },
        ),
      ),
    );

    stages
      ..add(
        ReactionStageSpec(
          id: 'sfinish',
          watch: <String>['finish'],
          after: <String>[previousStage!],
          trigger: 'activated',
          cameraFocus: 'finish',
          label: 'Finish button',
        ),
      )
      ..add(
        ReactionStageSpec(
          id: 'sflag',
          watch: <String>['goalflag'],
          after: <String>['sfinish'],
          trigger: 'activated',
          cameraFocus: 'goalflag',
          label: 'Flag raised',
        ),
      );

    return LevelSpec(
      id: id,
      world: world,
      index: 0,
      name: name,
      objects: objects,
      stages: stages,
      goalObject: 'goalflag',
      camera: const CameraSpec(yaw: -0.58, pitch: 0.42, pad: 1.12, orbit: 0.12),
      parChain: 8 + sections * 3,
      parTimeSec: 6.0 + sections * 2.5,
      bonuses: <BonusSpec>[
        BonusSpec(
          id: 'b_nostall',
          type: 'no_stall',
          description: 'Keep the chain going',
        ),
        BonusSpec(
          id: 'b_chain',
          type: 'chain_at_least',
          description: 'Activate at least ${6 + sections * 2} objects',
          value: (6 + sections * 2).toDouble(),
        ),
      ],
      hint: 'Tap the cannon. Everything else follows.',
    );
  }

  static List<ObjectSpec> _cannon(
    String id,
    double x,
    double aimDeg,
    double power,
  ) {
    final double a = aimDeg * math.pi / 180.0;
    return <ObjectSpec>[
      ObjectSpec(
        id: '${id}_carriage',
        model: 'cannon_carriage',
        position: Vector3(x - 0.06, 0.115, 0),
      ),
      ObjectSpec(
        id: '${id}_wheelp',
        model: 'cannon_wheel',
        shape: ColliderShape.none,
        position: Vector3(x - 0.09, 0.108, 0.115),
      ),
      ObjectSpec(
        id: '${id}_wheeln',
        model: 'cannon_wheel',
        shape: ColliderShape.none,
        position: Vector3(x - 0.09, 0.108, -0.115),
      ),
      ObjectSpec(
        id: id,
        model: 'cannon_barrel',
        position: Vector3(x, 0.248, 0),
        rotationDeg: Vector3(0, 0, aimDeg),
        starter: true,
        device: DeviceSpec(
          type: 'cannon',
          params: <String, dynamic>{
            'power': power,
            'aim': <double>[math.cos(a), math.sin(a), 0],
            'ammo': '${id}_ball',
            'muzzle': <double>[0.245, 0.02, 0],
            'intended': true,
          },
        ),
      ),
      ObjectSpec(
        id: '${id}_ball',
        model: 'cannonball',
        kind: ObjectKind.dynamicBody,
        shape: ColliderShape.sphere,
        position: Vector3(x + 0.245, 0.30, 0),
        radius: 0.0738,
        mass: 0.26,
        friction: 0.35,
        restitution: 0.22,
        hidden: true,
        tag: 'ball',
      ),
    ];
  }

  /// Returns (nextX, lastObjectId).
  static (double, String) _dominoSection(
    List<ObjectSpec> out,
    String id,
    double x,
    Rng r,
  ) {
    final int count = 4 + r.nextInt(4);
    const double spacing = 0.26;
    String last = '';
    for (int i = 0; i < count; i++) {
      last = '$id$i';
      out.add(
        ObjectSpec(
          id: last,
          model: r.pick(_dominoColours),
          kind: ObjectKind.dynamicBody,
          position: Vector3(x + spacing * i, 0.21, 0),
          mass: 0.13,
          friction: 0.58,
          restitution: 0.02,
          tag: 'domino',
        ),
      );
    }
    // The final piece is heavy so it hands off enough momentum to whatever
    // follows, whichever section that turns out to be.
    out.add(
      ObjectSpec(
        id: '${id}h',
        model: 'domino_heavy',
        kind: ObjectKind.dynamicBody,
        position: Vector3(x + spacing * count, 0.22, 0),
        mass: 0.55,
        friction: 0.58,
        restitution: 0.02,
        tag: 'domino',
      ),
    );
    return (x + spacing * count + 0.42, '${id}h');
  }

  static (double, String) _rampSection(
    List<ObjectSpec> out,
    String id,
    double x,
    Rng r,
  ) {
    out.add(
      ObjectSpec(
        id: '${id}_ramp',
        model: 'ramp_gentle',
        position: Vector3(x + 0.55, 0.08, 0),
        friction: 0.30,
      ),
    );
    out.add(
      ObjectSpec(
        id: id,
        model: 'ball_small',
        kind: ObjectKind.dynamicBody,
        shape: ColliderShape.sphere,
        position: Vector3(x + 0.18, 0.30, 0),
        radius: 0.0472,
        mass: 0.10,
        friction: 0.22,
        restitution: 0.30,
        tag: 'ball',
      ),
    );
    return (x + 1.20, id);
  }

  static (double, String) _springSection(
    List<ObjectSpec> out,
    String id,
    double x,
    Rng r,
  ) {
    out.add(
      ObjectSpec(
        id: '${id}_pad',
        model: 'spring_launcher',
        position: Vector3(x + 0.25, 0.0725, 0),
        device: DeviceSpec(
          type: 'spring',
          params: <String, dynamic>{
            'power': r.range(2.2, 3.0),
            'dir': <double>[0.72, 0.68, 0],
          },
        ),
      ),
    );
    out.add(
      ObjectSpec(
        id: id,
        model: 'ball_crystal',
        kind: ObjectKind.dynamicBody,
        shape: ColliderShape.sphere,
        position: Vector3(x + 0.25, 0.20, 0),
        radius: 0.0659,
        mass: 0.14,
        friction: 0.25,
        restitution: 0.35,
        tag: 'ball',
      ),
    );
    return (x + 0.95, id);
  }

  static (double, String) _blockSection(
    List<ObjectSpec> out,
    String id,
    double x,
    Rng r,
  ) {
    const List<String> cubes = <String>[
      'cube_red',
      'cube_blue',
      'cube_yellow',
      'cube_green',
    ];
    final int h = 2 + r.nextInt(2);
    String last = '';
    for (int i = 0; i < h; i++) {
      last = '$id$i';
      out.add(
        ObjectSpec(
          id: last,
          model: r.pick(cubes),
          kind: ObjectKind.dynamicBody,
          position: Vector3(x + 0.20, 0.13 + i * 0.26, 0),
          mass: 0.26,
          friction: 0.55,
          restitution: 0.03,
          tag: 'block',
        ),
      );
    }
    return (x + 0.72, last);
  }
}
