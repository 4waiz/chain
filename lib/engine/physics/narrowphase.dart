import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'body.dart';
import 'manifold.dart';

/// Contact generation for the two collider shapes the game uses.
///
/// Everything here writes into caller-owned scratch and never allocates, so
/// the narrowphase can run at a 240 Hz fixed step without producing garbage.
class Narrowphase {
  // Scratch reused across every call. Single-threaded by construction.
  final Vector3 _d = Vector3.zero();
  final Vector3 _closest = Vector3.zero();
  final Vector3 _local = Vector3.zero();
  final Vector3 _tmp = Vector3.zero();
  final Vector3 _tmp2 = Vector3.zero();

  final Float64List _c = Float64List(9); // relative rotation A^T * B
  final Float64List _absC = Float64List(9);
  final Float64List _t = Float64List(3); // translation in A's frame
  final Float64List _ea = Float64List(3);
  final Float64List _eb = Float64List(3);

  final Float64List _incident = Float64List(12); // 4 verts x xyz
  final Float64List _clipA = Float64List(24);
  final Float64List _clipB = Float64List(24);
  final Int32List _clipIdA = Int32List(8);
  final Int32List _clipIdB = Int32List(8);

  /// Fills [m] with contacts between [a] and [b]. Returns true if touching.
  ///
  /// The manifold normal always points from [a] towards [b].
  bool collide(Body a, Body b, Manifold m) {
    if (a.shape == ShapeKind.sphere && b.shape == ShapeKind.sphere) {
      m.begin(a, b);
      return _sphereSphere(a, b, m);
    }
    if (a.shape == ShapeKind.sphere && b.shape == ShapeKind.box) {
      m.begin(a, b);
      return _sphereBox(a, b, m, flip: false);
    }
    if (a.shape == ShapeKind.box && b.shape == ShapeKind.sphere) {
      m.begin(a, b);
      return _sphereBox(b, a, m, flip: true);
    }
    m.begin(a, b);
    return _boxBox(a, b, m);
  }

  // ------------------------------------------------------------- sphere x2
  bool _sphereSphere(Body a, Body b, Manifold m) {
    _d
      ..setFrom(b.position)
      ..sub(a.position);
    final double r = a.radius + b.radius;
    final double d2 = _d.length2;
    if (d2 > r * r) return false;

    final double d = math.sqrt(d2);
    if (d > 1e-9) {
      m.normal
        ..setFrom(_d)
        ..scale(1.0 / d);
    } else {
      m.normal.setValues(0, 1, 0);
    }

    final ContactPoint? p = m.push();
    if (p == null) return false;
    p.penetration = r - d;
    p.featureId = 0;
    p.position
      ..setFrom(a.position)
      ..addScaled(m.normal, a.radius - p.penetration * 0.5);
    m.buildTangents();
    return true;
  }

  // ---------------------------------------------------------- sphere x box
  /// [flip] is set when the caller's `a` was the box, so the emitted normal
  /// still runs from the manifold's own `a` to its `b`.
  bool _sphereBox(Body sphere, Body box, Manifold m, {required bool flip}) {
    // Sphere centre in the box's local frame.
    _d
      ..setFrom(sphere.position)
      ..sub(box.position);
    final Float64List r = box.rotation.storage;
    _local.setValues(
      _d.x * r[0] + _d.y * r[1] + _d.z * r[2],
      _d.x * r[3] + _d.y * r[4] + _d.z * r[5],
      _d.x * r[6] + _d.y * r[7] + _d.z * r[8],
    );

    final Vector3 e = box.halfExtents;
    final double cx = _local.x.clamp(-e.x, e.x);
    final double cy = _local.y.clamp(-e.y, e.y);
    final double cz = _local.z.clamp(-e.z, e.z);

    final bool inside = cx == _local.x && cy == _local.y && cz == _local.z;
    double nx, ny, nz, dist;

    if (inside) {
      // Centre is within the box: push out along the nearest face.
      final double dx = e.x - _local.x.abs();
      final double dy = e.y - _local.y.abs();
      final double dz = e.z - _local.z.abs();
      if (dx <= dy && dx <= dz) {
        nx = _local.x < 0 ? -1.0 : 1.0;
        ny = 0;
        nz = 0;
        dist = -dx;
      } else if (dy <= dz) {
        nx = 0;
        ny = _local.y < 0 ? -1.0 : 1.0;
        nz = 0;
        dist = -dy;
      } else {
        nx = 0;
        ny = 0;
        nz = _local.z < 0 ? -1.0 : 1.0;
        dist = -dz;
      }
      _closest.setValues(_local.x, _local.y, _local.z);
    } else {
      nx = _local.x - cx;
      ny = _local.y - cy;
      nz = _local.z - cz;
      final double l2 = nx * nx + ny * ny + nz * nz;
      if (l2 > sphere.radius * sphere.radius) return false;
      dist = math.sqrt(l2);
      if (dist > 1e-9) {
        nx /= dist;
        ny /= dist;
        nz /= dist;
      } else {
        nx = 0;
        ny = 1;
        nz = 0;
      }
      _closest.setValues(cx, cy, cz);
    }

    // Local normal and contact point back to world space.
    _tmp.setValues(
      r[0] * nx + r[3] * ny + r[6] * nz,
      r[1] * nx + r[4] * ny + r[7] * nz,
      r[2] * nx + r[5] * ny + r[8] * nz,
    );
    _tmp2
      ..setValues(
        r[0] * _closest.x + r[3] * _closest.y + r[6] * _closest.z,
        r[1] * _closest.x + r[4] * _closest.y + r[7] * _closest.z,
        r[2] * _closest.x + r[5] * _closest.y + r[8] * _closest.z,
      )
      ..add(box.position);

    // _tmp currently points box -> sphere.
    if (flip) {
      // Manifold a == box, b == sphere: normal must point box -> sphere.
      m.normal.setFrom(_tmp);
    } else {
      // Manifold a == sphere, b == box: invert.
      m.normal
        ..setFrom(_tmp)
        ..negate();
    }
    m.normal.normalize();

    final ContactPoint? p = m.push();
    if (p == null) return false;
    p.penetration = sphere.radius - dist;
    if (p.penetration < 0) p.penetration = 0;
    p.featureId = 0;
    p.position.setFrom(_tmp2);
    m.buildTangents();
    return true;
  }

  // ------------------------------------------------------------- box x box
  /// Separating-axis test over all 15 axes for rejection, then face clipping
  /// on the best face axis to build the manifold.
  ///
  /// Contacts are generated from face axes only. Edge-edge axes still take
  /// part in the separation test (so genuinely disjoint boxes are rejected),
  /// but generating an edge contact adds a rarely-exercised code path for
  /// little benefit at toy scale; a small bias keeps face axes preferred.
  bool _boxBox(Body a, Body b, Manifold m) {
    final Float64List ra = a.rotation.storage;
    final Float64List rb = b.rotation.storage;
    final Vector3 ea = a.halfExtents;
    final Vector3 eb = b.halfExtents;

    // C = A^T * B, stored row-major as c[row*3 + col].
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        _c[i * 3 + j] =
            ra[i * 3] * rb[j * 3] +
            ra[i * 3 + 1] * rb[j * 3 + 1] +
            ra[i * 3 + 2] * rb[j * 3 + 2];
        _absC[i * 3 + j] = _c[i * 3 + j].abs() + 1e-9;
      }
    }

    _d
      ..setFrom(b.position)
      ..sub(a.position);
    _t[0] = _d.x * ra[0] + _d.y * ra[1] + _d.z * ra[2];
    _t[1] = _d.x * ra[3] + _d.y * ra[4] + _d.z * ra[5];
    _t[2] = _d.x * ra[6] + _d.y * ra[7] + _d.z * ra[8];

    final Float64List eaa = _ea..setAll(0, <double>[ea.x, ea.y, ea.z]);
    final Float64List ebb = _eb..setAll(0, <double>[eb.x, eb.y, eb.z]);

    int bestAxis = -1;
    double bestSep = -double.infinity;
    bool bestFromA = true;

    // Face axes of A.
    for (int i = 0; i < 3; i++) {
      final double s =
          _t[i].abs() -
          (eaa[i] +
              ebb[0] * _absC[i * 3] +
              ebb[1] * _absC[i * 3 + 1] +
              ebb[2] * _absC[i * 3 + 2]);
      if (s > 0) return false;
      if (s > bestSep) {
        bestSep = s;
        bestAxis = i;
        bestFromA = true;
      }
    }

    // Face axes of B. Bias slightly so a near-tie resolves to A's face,
    // which keeps normals stable frame to frame for resting contacts.
    for (int j = 0; j < 3; j++) {
      final double proj = _t[0] * _c[j] + _t[1] * _c[3 + j] + _t[2] * _c[6 + j];
      final double s =
          proj.abs() -
          (ebb[j] +
              eaa[0] * _absC[j] +
              eaa[1] * _absC[3 + j] +
              eaa[2] * _absC[6 + j]);
      if (s > 0) return false;
      if (s > bestSep + 1e-5) {
        bestSep = s;
        bestAxis = j;
        bestFromA = false;
      }
    }

    // Edge-edge axes: rejection only.
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        final int i1 = (i + 1) % 3, i2 = (i + 2) % 3;
        final int j1 = (j + 1) % 3, j2 = (j + 2) % 3;
        final double ra_ =
            eaa[i1] * _absC[i2 * 3 + j] + eaa[i2] * _absC[i1 * 3 + j];
        final double rb_ =
            ebb[j1] * _absC[i * 3 + j2] + ebb[j2] * _absC[i * 3 + j1];
        final double proj = _t[i2] * _c[i1 * 3 + j] - _t[i1] * _c[i2 * 3 + j];
        if (proj.abs() > ra_ + rb_) return false;
      }
    }

    if (bestAxis < 0) return false;

    // ---- reference / incident selection ---------------------------------
    final Body refBody = bestFromA ? a : b;
    final Body incBody = bestFromA ? b : a;
    final Float64List refR = refBody.rotation.storage;
    final Vector3 refE = refBody.halfExtents;

    // Reference face normal in world space, pointing from ref towards inc.
    _tmp.setValues(
      refR[bestAxis * 3],
      refR[bestAxis * 3 + 1],
      refR[bestAxis * 3 + 2],
    );
    _tmp2
      ..setFrom(incBody.position)
      ..sub(refBody.position);
    final bool negate = _tmp.dot(_tmp2) < 0;
    if (negate) _tmp.negate();

    // Manifold normal must run a -> b.
    m.normal.setFrom(_tmp);
    if (!bestFromA) m.normal.negate();
    m.normal.normalize();

    _buildIncidentFace(incBody, _tmp);
    final int n = _clipIncidentToReference(refBody, bestAxis, negate, _tmp);
    if (n == 0) return false;

    // Emit the clipped points that are actually below the reference plane.
    final double refD = _tmp.dot(refBody.position) + _refExtent(refE, bestAxis);
    for (int i = 0; i < n; i++) {
      final double px = _clipA[i * 3],
          py = _clipA[i * 3 + 1],
          pz = _clipA[i * 3 + 2];
      final double sep = _tmp.x * px + _tmp.y * py + _tmp.z * pz - refD;
      if (sep > 0.0) continue;
      final ContactPoint? p = m.push();
      if (p == null) break;
      p.penetration = -sep;
      p.featureId = (bestAxis << 8) | _clipIdA[i] | (bestFromA ? 0 : 0x10000);
      // Place the point midway inside the overlap so the solver's torque arm
      // matches where the surfaces actually meet.
      p.position.setValues(
        px - _tmp.x * sep * 0.5,
        py - _tmp.y * sep * 0.5,
        pz - _tmp.z * sep * 0.5,
      );
    }

    if (m.pointCount == 0) return false;
    m.buildTangents();
    return true;
  }

  static double _refExtent(Vector3 e, int axis) =>
      axis == 0 ? e.x : (axis == 1 ? e.y : e.z);

  /// Finds the face of [inc] most anti-parallel to [refNormal] and writes its
  /// four world-space corners into [_incident].
  void _buildIncidentFace(Body inc, Vector3 refNormal) {
    final Float64List r = inc.rotation.storage;
    final Vector3 e = inc.halfExtents;

    int axis = 0;
    double best = double.infinity;
    double sign = 1.0;
    for (int i = 0; i < 3; i++) {
      final double d =
          refNormal.x * r[i * 3] +
          refNormal.y * r[i * 3 + 1] +
          refNormal.z * r[i * 3 + 2];
      if (d < best) {
        best = d;
        axis = i;
        sign = 1.0;
      }
      if (-d < best) {
        best = -d;
        axis = i;
        sign = -1.0;
      }
    }

    final int u = (axis + 1) % 3;
    final int v = (axis + 2) % 3;
    final double eAxis = axis == 0 ? e.x : (axis == 1 ? e.y : e.z);
    final double eU = u == 0 ? e.x : (u == 1 ? e.y : e.z);
    final double eV = v == 0 ? e.x : (v == 1 ? e.y : e.z);

    const List<int> su = <int>[-1, 1, 1, -1];
    const List<int> sv = <int>[-1, -1, 1, 1];

    for (int k = 0; k < 4; k++) {
      final double la = eAxis * sign;
      final double lu = eU * su[k];
      final double lv = eV * sv[k];
      // local = la*axis + lu*u + lv*v, then rotate + translate.
      final double lx =
          la * _basis(axis, 0) + lu * _basis(u, 0) + lv * _basis(v, 0);
      final double ly =
          la * _basis(axis, 1) + lu * _basis(u, 1) + lv * _basis(v, 1);
      final double lz =
          la * _basis(axis, 2) + lu * _basis(u, 2) + lv * _basis(v, 2);
      _incident[k * 3] = r[0] * lx + r[3] * ly + r[6] * lz + inc.position.x;
      _incident[k * 3 + 1] = r[1] * lx + r[4] * ly + r[7] * lz + inc.position.y;
      _incident[k * 3 + 2] = r[2] * lx + r[5] * ly + r[8] * lz + inc.position.z;
    }
  }

  static double _basis(int axis, int component) =>
      axis == component ? 1.0 : 0.0;

  /// Sutherland-Hodgman clip of the incident quad against the four side planes
  /// of the reference face. Result lands in [_clipA] with ids in [_clipIdA].
  int _clipIncidentToReference(
    Body ref,
    int axis,
    bool negate,
    Vector3 refNormal,
  ) {
    final Float64List r = ref.rotation.storage;
    final Vector3 e = ref.halfExtents;

    int n = 4;
    for (int k = 0; k < 4; k++) {
      _clipA[k * 3] = _incident[k * 3];
      _clipA[k * 3 + 1] = _incident[k * 3 + 1];
      _clipA[k * 3 + 2] = _incident[k * 3 + 2];
      _clipIdA[k] = k;
    }

    final int u = (axis + 1) % 3;
    final int v = (axis + 2) % 3;

    for (int which = 0; which < 2; which++) {
      final int sideAxis = which == 0 ? u : v;
      final double ext = sideAxis == 0 ? e.x : (sideAxis == 1 ? e.y : e.z);
      final double nx = r[sideAxis * 3];
      final double ny = r[sideAxis * 3 + 1];
      final double nz = r[sideAxis * 3 + 2];
      final double centre =
          nx * ref.position.x + ny * ref.position.y + nz * ref.position.z;

      for (int side = 0; side < 2; side++) {
        final double s = side == 0 ? 1.0 : -1.0;
        final double planeD = (centre + ext * s) * s;
        int out = 0;
        for (int i = 0; i < n; i++) {
          final int j = (i + 1) % n;
          final double xi = _clipA[i * 3],
              yi = _clipA[i * 3 + 1],
              zi = _clipA[i * 3 + 2];
          final double xj = _clipA[j * 3],
              yj = _clipA[j * 3 + 1],
              zj = _clipA[j * 3 + 2];
          final double di = (nx * xi + ny * yi + nz * zi) * s - planeD;
          final double dj = (nx * xj + ny * yj + nz * zj) * s - planeD;

          if (di <= 0) {
            if (out < 8) {
              _clipB[out * 3] = xi;
              _clipB[out * 3 + 1] = yi;
              _clipB[out * 3 + 2] = zi;
              _clipIdB[out] = _clipIdA[i];
              out++;
            }
          }
          if ((di <= 0) != (dj <= 0)) {
            final double t = di / (di - dj);
            if (out < 8) {
              _clipB[out * 3] = xi + (xj - xi) * t;
              _clipB[out * 3 + 1] = yi + (yj - yi) * t;
              _clipB[out * 3 + 2] = zi + (zj - zi) * t;
              _clipIdB[out] = _clipIdA[i] | (_clipIdA[j] << 3) | 0x40;
              out++;
            }
          }
        }
        n = out;
        if (n == 0) return 0;
        for (int i = 0; i < n; i++) {
          _clipA[i * 3] = _clipB[i * 3];
          _clipA[i * 3 + 1] = _clipB[i * 3 + 1];
          _clipA[i * 3 + 2] = _clipB[i * 3 + 2];
          _clipIdA[i] = _clipIdB[i];
        }
      }
    }
    return n;
  }
}
