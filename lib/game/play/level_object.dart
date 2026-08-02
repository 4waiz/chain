import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../../engine/physics/body.dart';
import '../../engine/render/render_instance.dart';
import '../level/level_spec.dart';

/// Runtime pairing of a level's authored object with its physics body, its
/// render instances and its device behaviour.
class LevelObject {
  LevelObject({required this.spec});

  final ObjectSpec spec;
  String get id => spec.id;

  Body? body;
  RenderInstance? instance;

  /// Visual-only children (wheels, flags). Index-aligned with
  /// `spec.attachments`.
  final List<RenderInstance> attachments = <RenderInstance>[];

  /// Accumulated roll for spinning attachments, radians.
  double spinAngle = 0.0;

  Object? device;

  /// Set once when this object's device fires or its goal condition is met.
  bool activated = false;
  double activatedAt = -1;

  /// Set when this object has moved far enough from home to count as having
  /// taken part in the chain. Drives the chain multiplier.
  bool participated = false;

  /// Collectibles.
  bool collected = false;

  /// Home transform, captured at build time and restored on reset.
  final Vector3 homePosition = Vector3.zero();
  final Quaternion homeOrientation = Quaternion.identity();

  bool get isStarter => spec.starter;

  void captureHome() {
    final Body? b = body;
    if (b != null) {
      homePosition.setFrom(b.position);
      homeOrientation.setFrom(b.orientation);
    } else {
      homePosition.setFrom(spec.position);
      homeOrientation.setFrom(spec.orientation);
    }
  }

  /// Restores the exact spawn state. Everything transient is cleared, which is
  /// what makes a retry byte-for-byte identical to the first attempt.
  void restoreHome() {
    activated = false;
    activatedAt = -1;
    participated = false;
    collected = false;
    spinAngle = 0.0;

    final Body? b = body;
    if (b != null) {
      b.position.setFrom(homePosition);
      b.orientation.setFrom(homeOrientation);
      b.stop();
      b.sleeping = false;
      b.sleepTimer = 0;
      b.lastImpactImpulse = 0;
      b.enabled = !spec.hidden;
      b.refresh();
    }
    final RenderInstance? ri = instance;
    if (ri != null) {
      ri.visible = !spec.hidden;
      ri.highlight = 0;
      ri.opacity = 1;
      ri.tintAmount = 0;
    }
    for (final RenderInstance a in attachments) {
      a.visible = !spec.hidden;
      a.opacity = 1;
      a.highlight = 0;
    }
  }

  /// Distance travelled from the spawn point.
  double get displacement {
    final Body? b = body;
    if (b == null) return 0;
    return (b.position - homePosition).length;
  }

  /// Tilt away from the spawn orientation, in degrees. Used by the 'fell'
  /// trigger to tell a toppled domino from a standing one.
  double get tiltDegrees {
    final Body? b = body;
    if (b == null) return 0;
    final Vector3 spawnUp = homeOrientation.rotated(Vector3(0, 1, 0));
    final Vector3 nowUp = b.orientation.rotated(Vector3(0, 1, 0));
    final double d = spawnUp.dot(nowUp).clamp(-1.0, 1.0);
    return math.acos(d) * 180.0 / math.pi;
  }
}
