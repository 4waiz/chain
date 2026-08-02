import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'body.dart';

/// One point of contact within a [Manifold].
class ContactPoint {
  final Vector3 position = Vector3.zero();

  /// Offsets from each body's centre of mass to [position].
  final Vector3 rA = Vector3.zero();
  final Vector3 rB = Vector3.zero();

  double penetration = 0.0;

  /// Accumulated impulses, carried across steps for warm starting. Warm
  /// starting is what lets a stack of blocks settle instead of sinking.
  double normalImpulse = 0.0;
  double tangentImpulse1 = 0.0;
  double tangentImpulse2 = 0.0;

  /// Split-impulse (pseudo-velocity) accumulator for position correction.
  double positionImpulse = 0.0;

  /// Identifies which pair of features produced this point, so the same
  /// physical contact can be matched between steps.
  int featureId = 0;

  // Pre-solve cache.
  double normalMass = 0.0;
  double tangentMass1 = 0.0;
  double tangentMass2 = 0.0;
  double velocityBias = 0.0;

  void reset() {
    penetration = 0;
    normalImpulse = 0;
    tangentImpulse1 = 0;
    tangentImpulse2 = 0;
    positionImpulse = 0;
    featureId = 0;
    velocityBias = 0;
  }
}

/// A contact between two bodies, holding up to four points.
///
/// Four is enough to fully constrain a face-on-face box contact, which is the
/// case that matters for stacked blocks and resting dominoes.
class Manifold {
  Manifold();

  late Body a;
  late Body b;

  /// Unit normal, pointing from [a] towards [b].
  final Vector3 normal = Vector3(0, 1, 0);
  final Vector3 tangent1 = Vector3(1, 0, 0);
  final Vector3 tangent2 = Vector3(0, 0, 1);

  final List<ContactPoint> points = <ContactPoint>[
    ContactPoint(),
    ContactPoint(),
    ContactPoint(),
    ContactPoint(),
  ];
  int pointCount = 0;

  double friction = 0.5;
  double restitution = 0.0;

  /// True when either body is a sensor: the contact is reported but never
  /// solved. Used for finish buttons, trigger volumes and bonus pickups.
  bool sensorOnly = false;

  /// Stable key for warm-start lookup. Body ids are assigned sequentially and
  /// a level never approaches 2^20 bodies.
  int get key => (a.id << 20) | b.id;

  void begin(Body bodyA, Body bodyB) {
    a = bodyA;
    b = bodyB;
    pointCount = 0;
    sensorOnly = bodyA.isSensor || bodyB.isSensor;
    // Geometric mean: a slippery object stays slippery against everything,
    // which is easier to author levels against than an arithmetic average.
    friction = math.sqrt(bodyA.friction * bodyB.friction);
    restitution = math.max(bodyA.restitution, bodyB.restitution);
  }

  ContactPoint? push() {
    if (pointCount >= 4) return null;
    final ContactPoint p = points[pointCount++];
    p.reset();
    return p;
  }

  /// Rebuilds an orthonormal tangent basis around [normal].
  void buildTangents() {
    // Pick the seed axis least aligned with the normal to avoid degeneracy.
    if (normal.x.abs() >= 0.57735) {
      tangent1.setValues(normal.y, -normal.x, 0.0);
    } else {
      tangent1.setValues(0.0, normal.z, -normal.y);
    }
    tangent1.normalize();
    normal.crossInto(tangent1, tangent2);
    tangent2.normalize();
  }

  /// Copies accumulated impulses from the previous step's manifold wherever a
  /// feature id matches, so persistent contacts keep their solved state.
  void warmStartFrom(Manifold old) {
    for (int i = 0; i < pointCount; i++) {
      final ContactPoint p = points[i];
      for (int j = 0; j < old.pointCount; j++) {
        final ContactPoint q = old.points[j];
        if (q.featureId == p.featureId) {
          p.normalImpulse = q.normalImpulse;
          p.tangentImpulse1 = q.tangentImpulse1;
          p.tangentImpulse2 = q.tangentImpulse2;
          break;
        }
      }
    }
  }
}
