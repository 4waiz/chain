import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'render_instance.dart';

/// World-space bounds of a set of instances.
///
/// Used by the camera to frame a level on load and by the camera director to
/// decide how far to pull back during a big multi-stage reaction.
class SceneBounds {
  final Vector3 lo = Vector3.all(double.infinity);
  final Vector3 hi = Vector3.all(-double.infinity);

  bool get isEmpty => lo.x > hi.x;

  Vector3 get centre => (lo + hi)..scale(0.5);
  Vector3 get size => hi - lo;

  void reset() {
    lo.setValues(double.infinity, double.infinity, double.infinity);
    hi.setValues(-double.infinity, -double.infinity, -double.infinity);
  }

  void addPoint(double x, double y, double z) {
    if (x < lo.x) lo.x = x;
    if (y < lo.y) lo.y = y;
    if (z < lo.z) lo.z = z;
    if (x > hi.x) hi.x = x;
    if (y > hi.y) hi.y = y;
    if (z > hi.z) hi.z = z;
  }

  /// Expands to cover an instance's transformed bounding box.
  void addInstance(RenderInstance inst) {
    if (!inst.visible) return;
    final Float64List m = inst.transform.storage;
    final Float32List blo = inst.mesh.boundsMin;
    final Float32List bhi = inst.mesh.boundsMax;
    for (int c = 0; c < 8; c++) {
      final double ox = (c & 1) == 0 ? blo[0] : bhi[0];
      final double oy = (c & 2) == 0 ? blo[1] : bhi[1];
      final double oz = (c & 4) == 0 ? blo[2] : bhi[2];
      addPoint(
        m[0] * ox + m[4] * oy + m[8] * oz + m[12],
        m[1] * ox + m[5] * oy + m[9] * oz + m[13],
        m[2] * ox + m[6] * oy + m[10] * oz + m[14],
      );
    }
  }

  void addAll(Iterable<RenderInstance> instances) {
    for (final RenderInstance i in instances) {
      addInstance(i);
    }
  }

  /// Grows the box outwards by [m] on every axis.
  void expand(double m) {
    if (isEmpty) return;
    lo.setValues(lo.x - m, lo.y - m, lo.z - m);
    hi.setValues(hi.x + m, hi.y + m, hi.z + m);
  }

  static SceneBounds of(Iterable<RenderInstance> instances) {
    final SceneBounds b = SceneBounds();
    b.addAll(instances);
    return b;
  }
}
