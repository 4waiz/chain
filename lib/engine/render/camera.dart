import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// The three-quarter "miniature product render" camera.
///
/// The camera is always described in orbit terms — a target point plus a
/// yaw/pitch/distance — because every camera move in the game (idle orbit,
/// following a reaction, punching in on an impact) is expressed as an
/// interpolation between two of these, which keeps motion smooth and stops
/// the camera ever rolling or flipping.
class OrbitCamera {
  OrbitCamera({
    Vector3? target,
    this.yaw = -0.62,
    this.pitch = 0.52,
    this.distance = 9.0,
    this.fovY = 0.60,
    this.near = 0.35,
    this.far = 120.0,
  }) : target = target ?? Vector3.zero();

  /// Point the camera looks at, in world space.
  Vector3 target;

  /// Rotation around the world Y axis, radians.
  double yaw;

  /// Elevation above the horizon, radians. Clamped away from the poles.
  double pitch;

  /// Distance from [target] to the eye.
  double distance;

  /// Vertical field of view, radians.
  double fovY;

  double near;
  double far;

  static const double minPitch = 0.12;
  static const double maxPitch = 1.35;

  final Matrix4 _view = Matrix4.identity();
  final Matrix4 _proj = Matrix4.identity();
  final Matrix4 _viewProj = Matrix4.identity();
  final Vector3 _eye = Vector3.zero();

  Vector3 get eye => _eye;
  Matrix4 get viewProj => _viewProj;
  Matrix4 get view => _view;

  OrbitCamera clone() => OrbitCamera(
    target: target.clone(),
    yaw: yaw,
    pitch: pitch,
    distance: distance,
    fovY: fovY,
    near: near,
    far: far,
  );

  void copyFrom(OrbitCamera other) {
    target.setFrom(other.target);
    yaw = other.yaw;
    pitch = other.pitch;
    distance = other.distance;
    fovY = other.fovY;
    near = other.near;
    far = other.far;
  }

  /// Spherical interpolation between two camera states. Yaw is interpolated on
  /// the shortest arc so the camera never spins the long way round.
  static void lerpInto(OrbitCamera out, OrbitCamera a, OrbitCamera b, double t) {
    double dy = b.yaw - a.yaw;
    while (dy > math.pi) {
      dy -= math.pi * 2;
    }
    while (dy < -math.pi) {
      dy += math.pi * 2;
    }
    out.yaw = a.yaw + dy * t;
    out.pitch = a.pitch + (b.pitch - a.pitch) * t;
    out.distance = a.distance + (b.distance - a.distance) * t;
    out.fovY = a.fovY + (b.fovY - a.fovY) * t;
    out.near = a.near + (b.near - a.near) * t;
    out.far = a.far + (b.far - a.far) * t;
    out.target
      ..setFrom(a.target)
      ..scale(1 - t)
      ..addScaled(b.target, t);
  }

  void clampPitch() {
    if (pitch < minPitch) pitch = minPitch;
    if (pitch > maxPitch) pitch = maxPitch;
  }

  /// Recomputes eye/view/projection. [aspect] is width / height.
  void update(double aspect) {
    clampPitch();
    final double cp = math.cos(pitch);
    final double sp = math.sin(pitch);
    final double cy = math.cos(yaw);
    final double sy = math.sin(yaw);

    _eye
      ..x = target.x + distance * cp * sy
      ..y = target.y + distance * sp
      ..z = target.z + distance * cp * cy;

    setViewMatrix(_view, _eye, target, _worldUp);
    setPerspectiveMatrix(_proj, fovY, aspect <= 0 ? 1.0 : aspect, near, far);
    _viewProj
      ..setFrom(_proj)
      ..multiply(_view);
  }

  static final Vector3 _worldUp = Vector3(0, 1, 0);

  /// Builds a ray from a point in *pixel* space into the world, used for
  /// picking a starter object with one tap.
  void screenRay(
    double px,
    double py,
    double width,
    double height,
    Vector3 outOrigin,
    Vector3 outDir,
  ) {
    final double ndcX = (px / width) * 2.0 - 1.0;
    final double ndcY = 1.0 - (py / height) * 2.0;

    final Matrix4 inv = Matrix4.copy(_viewProj)..invert();

    final Vector4 nearP = inv.transform(Vector4(ndcX, ndcY, -1.0, 1.0));
    final Vector4 farP = inv.transform(Vector4(ndcX, ndcY, 1.0, 1.0));

    if (nearP.w.abs() > 1e-9) nearP.scale(1.0 / nearP.w);
    if (farP.w.abs() > 1e-9) farP.scale(1.0 / farP.w);

    outOrigin.setValues(nearP.x, nearP.y, nearP.z);
    outDir
      ..setValues(farP.x - nearP.x, farP.y - nearP.y, farP.z - nearP.z)
      ..normalize();
  }

  /// Frames a world-space bounding box, keeping the existing yaw/pitch.
  /// [pad] > 1 leaves breathing room, which the art direction asks for.
  void frameBounds(
    Vector3 lo,
    Vector3 hi,
    double aspect, {
    double pad = 1.22,
    double verticalBias = 0.12,
  }) {
    target
      ..setValues((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
      ..y += (hi.y - lo.y) * verticalBias;

    final double ex = (hi.x - lo.x) * 0.5;
    final double ey = (hi.y - lo.y) * 0.5;
    final double ez = (hi.z - lo.z) * 0.5;
    final double radius = math.sqrt(ex * ex + ey * ey + ez * ez);

    final double fovX = 2.0 * math.atan(math.tan(fovY * 0.5) * (aspect <= 0 ? 1.0 : aspect));
    final double limiting = math.min(fovY, fovX);
    distance = (radius * pad) / math.max(0.05, math.sin(limiting * 0.5));
  }
}
