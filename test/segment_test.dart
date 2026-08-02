import 'dart:math' as math;

import 'package:chain_reaction_city/game/level/level_spec.dart';
import 'package:chain_reaction_city/game/play/level_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'level_play_test.dart' show allModelSlugs, loadModelsFromDisk;

/// Characterises the reusable chain segments in isolation.
///
/// Level authoring depends on knowing exactly how far a fired ball travels,
/// how long a domino run stays reliable, and how far a shoved car slides.
/// These are the measurements the level factory is built on, so they are
/// asserted here rather than assumed.
ObjectSpec _cannon(double x, {double aim = 13.0, double power = 4.55}) =>
    ObjectSpec(
      id: 'cannon',
      model: 'cannon_barrel',
      position: Vector3(x, 0.248, 0),
      rotationDeg: Vector3(0, 0, aim),
      starter: true,
      device: DeviceSpec(
        type: 'cannon',
        params: <String, dynamic>{
          'power': power,
          'aim': <double>[
            math.cos(aim * math.pi / 180),
            math.sin(aim * math.pi / 180),
            0,
          ],
          'ammo': 'ball',
          'muzzle': <double>[0.245, 0.02, 0],
        },
      ),
    );

ObjectSpec _ball(double x, {double friction = 0.05}) => ObjectSpec(
  id: 'ball',
  model: 'cannonball',
  kind: ObjectKind.dynamicBody,
  shape: ColliderShape.sphere,
  position: Vector3(x + 0.245, 0.30, 0),
  radius: 0.0738,
  mass: 0.26,
  friction: friction,
  restitution: 0.24,
  hidden: true,
  tag: 'ball',
);

LevelSpec _spec(List<ObjectSpec> objects) => LevelSpec(
  id: 'seg',
  world: 0,
  index: 0,
  name: 'seg',
  objects: objects,
  stages: <ReactionStageSpec>[
    ReactionStageSpec(id: 's', watch: <String>['ball']),
  ],
  goalObject: 'ball',
);

/// Runs a raw simulation without the win/fail logic getting in the way.
LevelRuntime _sim(List<ObjectSpec> objects, double seconds) {
  final LevelRuntime rt = LevelRuntime(_spec(objects))..build();
  rt.start('cannon');
  final int n = (seconds * 60).round();
  for (int i = 0; i < n; i++) {
    rt.update(1 / 60);
  }
  return rt;
}

void main() {
  setUpAll(() async => loadModelsFromDisk(allModelSlugs()));

  test('measure: how far a fired cannonball actually travels', () {
    final LevelRuntime rt = _sim(<ObjectSpec>[_cannon(-1.5), _ball(-1.5)], 6.0);
    final double reach = rt.find('ball')!.body!.position.x - (-1.5 + 0.245);
    // ignore: avoid_print
    print(
      'BALL REACH: ${reach.toStringAsFixed(3)} m '
      'final x=${rt.find('ball')!.body!.position.x.toStringAsFixed(3)}',
    );
    expect(
      reach,
      greaterThan(0.5),
      reason: 'a fired ball must clear its own muzzle',
    );
  });

  test('measure: reliable domino run length at 0.26 spacing', () {
    for (final int count in <int>[5, 6, 7, 8, 10, 12]) {
      final List<ObjectSpec> objs = <ObjectSpec>[_cannon(-1.62), _ball(-1.62)];
      for (int i = 0; i < count; i++) {
        objs.add(
          ObjectSpec(
            id: 'd$i',
            model: 'domino_blue',
            kind: ObjectKind.dynamicBody,
            position: Vector3(-0.72 + 0.26 * i, 0.21, 0),
            mass: 0.13,
            friction: 0.58,
            restitution: 0.02,
          ),
        );
      }
      final LevelRuntime rt = _sim(objs, 8.0);
      int fell = 0;
      for (int i = 0; i < count; i++) {
        if (rt.find('d$i')!.tiltDegrees > 40) fell++;
      }
      // ignore: avoid_print
      print(
        'DOMINOES count=$count fell=$fell '
        'lastTilt=${rt.find('d${count - 1}')!.tiltDegrees.toStringAsFixed(0)}',
      );
    }
  });

  test('measure: how far a heavy domino shoves a light car', () {
    final List<ObjectSpec> objs = <ObjectSpec>[_cannon(-1.62), _ball(-1.62)];
    for (int i = 0; i < 5; i++) {
      objs.add(
        ObjectSpec(
          id: 'd$i',
          model: 'domino_blue',
          kind: ObjectKind.dynamicBody,
          position: Vector3(-0.72 + 0.26 * i, 0.21, 0),
          mass: 0.13,
          friction: 0.58,
          restitution: 0.02,
        ),
      );
    }
    objs.add(
      ObjectSpec(
        id: 'dh',
        model: 'domino_heavy',
        kind: ObjectKind.dynamicBody,
        position: Vector3(0.60, 0.22, 0),
        mass: 0.55,
        friction: 0.58,
        restitution: 0.02,
      ),
    );
    objs.add(
      ObjectSpec(
        id: 'car',
        model: 'toy_car_body',
        kind: ObjectKind.dynamicBody,
        position: Vector3(0.95, 0.109, 0),
        halfExtents: Vector3(0.193, 0.109, 0.102),
        mass: 0.16,
        friction: 0.025,
        restitution: 0.04,
      ),
    );
    final LevelRuntime rt = _sim(objs, 10.0);
    final double travel = rt.find('car')!.body!.position.x - 0.95;
    // ignore: avoid_print
    print(
      'CAR TRAVEL: ${travel.toStringAsFixed(3)} m '
      '(front face reaches ${(0.95 + travel + 0.193).toStringAsFixed(3)})',
    );
    expect(travel, greaterThan(0.05));
  });
}
