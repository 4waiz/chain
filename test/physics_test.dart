import 'package:chain_reaction_city/engine/physics/body.dart';
import 'package:chain_reaction_city/engine/physics/world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

/// Builds a world with a large static floor whose top surface sits at y = 0.
PhysicsWorld _worldWithFloor() {
  final PhysicsWorld w = PhysicsWorld();
  w.create(
    kind: BodyKind.static_,
    shape: ShapeKind.box,
    position: Vector3(0, -0.5, 0),
    halfExtents: Vector3(20, 0.5, 20),
    friction: 0.7,
    restitution: 0.0,
  );
  return w;
}

void _run(PhysicsWorld w, double seconds) {
  const double frame = 1.0 / 60.0;
  final int frames = (seconds / frame).round();
  for (int i = 0; i < frames; i++) {
    w.step(frame);
  }
}

void main() {
  group('resting and stacking', () {
    test('a sphere dropped on the floor comes to rest on its surface', () {
      final PhysicsWorld w = _worldWithFloor();
      final Body ball = w.create(
        kind: BodyKind.dynamic_,
        shape: ShapeKind.sphere,
        position: Vector3(0, 1.2, 0),
        radius: 0.075,
        mass: 0.2,
        restitution: 0.1,
      );

      _run(w, 3.0);

      // Rest height is the radius, within the solver's allowed slop.
      expect(ball.position.y, closeTo(0.075, 0.006));
      expect(ball.position.x.abs(), lessThan(0.02));
      expect(ball.position.z.abs(), lessThan(0.02));
      expect(ball.linearVelocity.length, lessThan(0.05));
    });

    test('a box settles flat on the floor without sinking or jittering', () {
      final PhysicsWorld w = _worldWithFloor();
      final Body box = w.create(
        kind: BodyKind.dynamic_,
        shape: ShapeKind.box,
        position: Vector3(0, 0.8, 0),
        halfExtents: Vector3(0.13, 0.13, 0.13),
        mass: 0.35,
      );

      _run(w, 3.0);

      expect(box.position.y, closeTo(0.13, 0.006));
      expect(box.linearVelocity.length, lessThan(0.05));
      expect(box.angularVelocity.length, lessThan(0.10));
    });

    test('a three-block tower stays standing', () {
      final PhysicsWorld w = _worldWithFloor();
      final List<Body> blocks = <Body>[];
      for (int i = 0; i < 3; i++) {
        blocks.add(
          w.create(
            kind: BodyKind.dynamic_,
            shape: ShapeKind.box,
            position: Vector3(0, 0.13 + i * 0.264, 0),
            halfExtents: Vector3(0.13, 0.13, 0.13),
            mass: 0.35,
          ),
        );
      }

      _run(w, 4.0);

      for (int i = 0; i < blocks.length; i++) {
        expect(
          blocks[i].position.y,
          closeTo(0.13 + i * 0.26, 0.03),
          reason: 'block $i sank or was pushed out of the stack',
        );
        expect(
          blocks[i].position.x.abs(),
          lessThan(0.04),
          reason: 'block $i drifted sideways',
        );
      }
    });
  });

  group('chain reactions', () {
    /// The core gameplay case: a nudged domino must topple its neighbours all
    /// the way down the line.
    test('a nudged domino topples an eight-piece run', () {
      final PhysicsWorld w = _worldWithFloor();

      // Matches the exported domino: 0.083 thick, 0.42 tall, 0.20 wide.
      const double thick = 0.083, half = 0.21, spacing = 0.26;
      final List<Body> run = <Body>[];
      for (int i = 0; i < 8; i++) {
        run.add(
          w.create(
            kind: BodyKind.dynamic_,
            shape: ShapeKind.box,
            position: Vector3(i * spacing, half, 0),
            halfExtents: Vector3(thick / 2, half, 0.10),
            mass: 0.12,
            friction: 0.6,
            restitution: 0.02,
            nodeId: 'd$i',
          ),
        );
      }

      // Let them settle, then tip the first one.
      _run(w, 0.5);
      run.first.applyImpulse(Vector3(0.09, 0, 0), Vector3(0, half * 0.9, 0));

      _run(w, 6.0);

      // Every domino should have fallen: a standing piece has its centre near
      // `half`, a fallen one is near half its thickness.
      for (int i = 0; i < run.length; i++) {
        expect(
          run[i].position.y,
          lessThan(0.20),
          reason: 'domino $i did not fall (y=${run[i].position.y})',
        );
      }
      // And the chain should have travelled forwards, not scattered backwards.
      expect(run.last.position.x, greaterThan(7 * spacing - 0.1));
    });

    test('a ball rolls down a ramp and keeps going along the floor', () {
      final PhysicsWorld w = _worldWithFloor();
      // 20-degree ramp descending towards +X: rotating about +Z by a negative
      // angle tips the local +X axis downwards.
      w.create(
        kind: BodyKind.static_,
        shape: ShapeKind.box,
        position: Vector3(-0.6, 0.30, 0),
        halfExtents: Vector3(0.7, 0.03, 0.25),
        orientation: Quaternion.axisAngle(Vector3(0, 0, 1), -0.35),
        friction: 0.4,
      );
      final Body ball = w.create(
        kind: BodyKind.dynamic_,
        shape: ShapeKind.sphere,
        position: Vector3(-1.05, 0.62, 0),
        radius: 0.07,
        mass: 0.2,
        friction: 0.3,
        restitution: 0.05,
      );

      _run(w, 4.0);

      expect(
        ball.position.y,
        closeTo(0.07, 0.02),
        reason: 'ball should have reached the floor',
      );
      expect(
        ball.position.x,
        greaterThan(-0.4),
        reason: 'ball should have rolled forward off the ramp',
      );
    });
  });

  group('determinism', () {
    /// The whole game design rests on this: the same tap must always give the
    /// same reaction.
    List<double> fingerprint() {
      final PhysicsWorld w = _worldWithFloor();
      final List<Body> run = <Body>[];
      for (int i = 0; i < 10; i++) {
        run.add(
          w.create(
            kind: BodyKind.dynamic_,
            shape: ShapeKind.box,
            position: Vector3(i * 0.26, 0.21, 0),
            halfExtents: Vector3(0.0415, 0.21, 0.10),
            mass: 0.12,
          ),
        );
      }
      final Body ball = w.create(
        kind: BodyKind.dynamic_,
        shape: ShapeKind.sphere,
        position: Vector3(-0.8, 0.5, 0),
        radius: 0.075,
        mass: 0.25,
      );

      _run(w, 0.4);
      ball.applyCentralImpulse(Vector3(1.4, 0.15, 0));
      _run(w, 6.0);

      final List<double> out = <double>[];
      for (final Body b in run) {
        out.addAll(<double>[b.position.x, b.position.y, b.position.z]);
      }
      out.addAll(<double>[ball.position.x, ball.position.y, ball.position.z]);
      return out;
    }

    test('identical setups produce bit-identical results', () {
      final List<double> a = fingerprint();
      final List<double> b = fingerprint();
      expect(a.length, b.length);
      for (int i = 0; i < a.length; i++) {
        expect(a[i], equals(b[i]), reason: 'divergence at index $i');
      }
    });

    test('variable frame pacing does not change the outcome', () {
      // Same simulation, but fed in uneven chunks the way a real device with a
      // dropped frame would. The fixed-step accumulator must absorb this.
      PhysicsWorld build() {
        final PhysicsWorld w = _worldWithFloor();
        w.create(
          kind: BodyKind.dynamic_,
          shape: ShapeKind.sphere,
          position: Vector3(0, 1.0, 0),
          radius: 0.075,
          mass: 0.2,
          nodeId: 'ball',
        );
        return w;
      }

      final PhysicsWorld even = build();
      for (int i = 0; i < 120; i++) {
        even.step(1 / 60);
      }

      final PhysicsWorld uneven = build();
      double fed = 0;
      const double target = 120 / 60;
      final List<double> pattern = <double>[
        1 / 60,
        1 / 30,
        1 / 120,
        1 / 60,
        1 / 45,
      ];
      int k = 0;
      while (fed < target - 1e-9) {
        double dt = pattern[k++ % pattern.length];
        if (fed + dt > target) dt = target - fed;
        uneven.step(dt);
        fed += dt;
      }

      expect(even.stepCount, uneven.stepCount);
      expect(
        uneven.bodies[1].position.y,
        closeTo(even.bodies[1].position.y, 1e-9),
      );
    });
  });

  group('picking', () {
    test('a ray selects the nearest body it hits', () {
      final PhysicsWorld w = PhysicsWorld();
      final Body near = w.create(
        kind: BodyKind.static_,
        shape: ShapeKind.box,
        position: Vector3(0, 0, 2),
        halfExtents: Vector3(0.3, 0.3, 0.3),
      );
      w.create(
        kind: BodyKind.static_,
        shape: ShapeKind.box,
        position: Vector3(0, 0, 6),
        halfExtents: Vector3(0.3, 0.3, 0.3),
      );

      final Body? hit = w.raycast(Vector3(0, 0, -5), Vector3(0, 0, 1), 50);
      expect(hit, same(near));
      expect(w.lastRayDistance, closeTo(6.7, 0.05));
    });

    test('a ray that misses returns null', () {
      final PhysicsWorld w = PhysicsWorld();
      w.create(
        kind: BodyKind.static_,
        shape: ShapeKind.sphere,
        position: Vector3(0, 0, 2),
        radius: 0.3,
      );
      expect(w.raycast(Vector3(3, 0, -5), Vector3(0, 0, 1), 50), isNull);
    });
  });

  group('sleeping', () {
    test('a settled body sleeps, and a new impact wakes it', () {
      final PhysicsWorld w = _worldWithFloor();
      final Body box = w.create(
        kind: BodyKind.dynamic_,
        shape: ShapeKind.box,
        position: Vector3(0, 0.14, 0),
        halfExtents: Vector3(0.13, 0.13, 0.13),
        mass: 0.35,
      );

      _run(w, 3.0);
      expect(box.sleeping, isTrue, reason: 'a resting box should sleep');

      final Body ball = w.create(
        kind: BodyKind.dynamic_,
        shape: ShapeKind.sphere,
        position: Vector3(-0.8, 0.13, 0),
        radius: 0.075,
        mass: 0.4,
      );
      ball.applyCentralImpulse(Vector3(1.2, 0, 0));
      _run(w, 1.5);

      expect(
        box.position.x,
        greaterThan(0.02),
        reason: 'the sleeping box should have been knocked forward',
      );
    });
  });
}
