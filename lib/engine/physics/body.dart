import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

enum BodyKind {
  /// Never moves. Ramps, floors, walls, machine housings.
  static_,

  /// Moves under script control, pushes dynamics, is not pushed back.
  /// Conveyors, lifts, rotating platforms, the cannon barrel.
  kinematic,

  /// Fully simulated.
  dynamic_,
}

enum ShapeKind { sphere, box }

/// A rigid body with either a sphere or an oriented-box collider.
///
/// Two shapes cover the whole game: every toy is either round or blocky, and
/// keeping the shape set this small is what makes the simulation cheap enough
/// to run at a 240 Hz fixed step on a phone — which in turn is what makes long
/// domino chains repeatable.
class Body {
  Body({
    required this.id,
    required this.kind,
    required this.shape,
    Vector3? position,
    Quaternion? orientation,
    Vector3? halfExtents,
    this.radius = 0.1,
    double mass = 1.0,
    this.friction = 0.55,
    this.restitution = 0.06,
    this.linearDamping = 0.02,
    this.angularDamping = 0.06,
    this.tag = '',
    this.nodeId = '',
    this.gravityScale = 1.0,
    this.canSleep = true,
    this.isSensor = false,
  }) : position = position ?? Vector3.zero(),
       orientation = orientation ?? Quaternion.identity(),
       halfExtents = halfExtents ?? Vector3(0.1, 0.1, 0.1) {
    setMass(mass);
  }

  final int id;
  BodyKind kind;
  ShapeKind shape;

  /// Authoring identity — the level's node id. Contact events carry this so
  /// the reaction graph can talk in level terms, not body indices.
  String nodeId;
  String tag;

  final Vector3 position;
  final Quaternion orientation;
  final Vector3 linearVelocity = Vector3.zero();
  final Vector3 angularVelocity = Vector3.zero();

  final Vector3 halfExtents;
  double radius;

  double mass = 1.0;
  double invMass = 1.0;
  double gravityScale;

  double friction;
  double restitution;
  double linearDamping;
  double angularDamping;

  bool isSensor;
  bool canSleep;
  bool sleeping = false;
  double sleepTimer = 0.0;
  bool enabled = true;

  /// Cached orientation as a matrix, refreshed once per step.
  final Matrix3 rotation = Matrix3.identity();

  /// Inverse inertia in local space (diagonal) and its world-space form.
  final Vector3 invInertiaLocal = Vector3.zero();
  final Matrix3 invInertiaWorld = Matrix3.zero();

  // World AABB, refreshed once per step for the broadphase.
  final Vector3 aabbMin = Vector3.zero();
  final Vector3 aabbMax = Vector3.zero();

  /// Accumulated impulse magnitude this step — drives impact FX and audio.
  double lastImpactImpulse = 0.0;

  bool get isDynamic => kind == BodyKind.dynamic_;
  bool get movable => kind != BodyKind.static_;

  void setMass(double m) {
    if (kind != BodyKind.dynamic_ || m <= 0) {
      mass = 0.0;
      invMass = 0.0;
      invInertiaLocal.setZero();
      return;
    }
    mass = m;
    invMass = 1.0 / m;

    if (shape == ShapeKind.sphere) {
      final double i = 0.4 * m * radius * radius;
      final double inv = i > 0 ? 1.0 / i : 0.0;
      invInertiaLocal.setValues(inv, inv, inv);
    } else {
      final double w = halfExtents.x * 2,
          h = halfExtents.y * 2,
          d = halfExtents.z * 2;
      final double ix = (m / 12.0) * (h * h + d * d);
      final double iy = (m / 12.0) * (w * w + d * d);
      final double iz = (m / 12.0) * (w * w + h * h);
      invInertiaLocal.setValues(
        ix > 0 ? 1 / ix : 0,
        iy > 0 ? 1 / iy : 0,
        iz > 0 ? 1 / iz : 0,
      );
    }
  }

  /// Rebuilds [rotation], [invInertiaWorld] and the world AABB.
  void refresh() {
    orientation.normalize();
    _quatToMatrix(orientation, rotation);

    if (invMass > 0) {
      // I_world^-1 = R * I_local^-1 * R^T, with I_local^-1 diagonal.
      final Float64List r = rotation.storage;
      final double a = invInertiaLocal.x,
          b = invInertiaLocal.y,
          c = invInertiaLocal.z;
      final Float64List o = invInertiaWorld.storage;
      for (int col = 0; col < 3; col++) {
        for (int row = 0; row < 3; row++) {
          o[col * 3 + row] =
              r[0 * 3 + row] * a * r[0 * 3 + col] +
              r[1 * 3 + row] * b * r[1 * 3 + col] +
              r[2 * 3 + row] * c * r[2 * 3 + col];
        }
      }
    } else {
      invInertiaWorld.setZero();
    }

    if (shape == ShapeKind.sphere) {
      aabbMin.setValues(
        position.x - radius,
        position.y - radius,
        position.z - radius,
      );
      aabbMax.setValues(
        position.x + radius,
        position.y + radius,
        position.z + radius,
      );
    } else {
      final Float64List r = rotation.storage;
      final double ex =
          halfExtents.x * r[0].abs() +
          halfExtents.y * r[3].abs() +
          halfExtents.z * r[6].abs();
      final double ey =
          halfExtents.x * r[1].abs() +
          halfExtents.y * r[4].abs() +
          halfExtents.z * r[7].abs();
      final double ez =
          halfExtents.x * r[2].abs() +
          halfExtents.y * r[5].abs() +
          halfExtents.z * r[8].abs();
      aabbMin.setValues(position.x - ex, position.y - ey, position.z - ez);
      aabbMax.setValues(position.x + ex, position.y + ey, position.z + ez);
    }
  }

  void applyImpulse(Vector3 impulse, Vector3 relativePoint) {
    if (invMass <= 0) return;
    linearVelocity.addScaled(impulse, invMass);
    final Vector3 torque = relativePoint.cross(impulse);
    angularVelocity.add(invInertiaWorld.transformed(torque));
    wake();
  }

  void applyCentralImpulse(Vector3 impulse) {
    if (invMass <= 0) return;
    linearVelocity.addScaled(impulse, invMass);
    wake();
  }

  void applyAngularImpulse(Vector3 impulse) {
    if (invMass <= 0) return;
    angularVelocity.add(invInertiaWorld.transformed(impulse));
    wake();
  }

  void wake() {
    sleeping = false;
    sleepTimer = 0.0;
  }

  void stop() {
    linearVelocity.setZero();
    angularVelocity.setZero();
  }

  /// Largest distance from the centre to any point of the shape.
  double get boundingRadius =>
      shape == ShapeKind.sphere ? radius : halfExtents.length;

  static void _quatToMatrix(Quaternion q, Matrix3 out) {
    final double x = q.x, y = q.y, z = q.z, w = q.w;
    final double x2 = x + x, y2 = y + y, z2 = z + z;
    final double xx = x * x2, xy = x * y2, xz = x * z2;
    final double yy = y * y2, yz = y * z2, zz = z * z2;
    final double wx = w * x2, wy = w * y2, wz = w * z2;
    final Float64List m = out.storage;
    m[0] = 1.0 - (yy + zz);
    m[1] = xy + wz;
    m[2] = xz - wy;
    m[3] = xy - wz;
    m[4] = 1.0 - (xx + zz);
    m[5] = yz + wx;
    m[6] = xz + wy;
    m[7] = yz - wx;
    m[8] = 1.0 - (xx + yy);
  }

  /// Integrates the orientation quaternion by an angular velocity over [dt].
  static void integrateOrientation(Quaternion q, Vector3 w, double dt) {
    final double wx = w.x * dt * 0.5, wy = w.y * dt * 0.5, wz = w.z * dt * 0.5;
    final double qx = q.x, qy = q.y, qz = q.z, qw = q.w;
    q
      ..x = qx + (wx * qw + wy * qz - wz * qy)
      ..y = qy + (wy * qw + wz * qx - wx * qz)
      ..z = qz + (wz * qw + wx * qy - wy * qx)
      ..w = qw - (wx * qx + wy * qy + wz * qz);
    final double len = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
    if (len > 1e-12) {
      final double inv = 1.0 / len;
      q
        ..x = q.x * inv
        ..y = q.y * inv
        ..z = q.z * inv
        ..w = q.w * inv;
    } else {
      q.setValues(0, 0, 0, 1);
    }
  }
}
