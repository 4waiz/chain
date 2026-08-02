import 'package:vector_math/vector_math_64.dart';

import 'mesh.dart';

/// One drawable placement of a [Mesh] in the world.
///
/// Instances are pooled and mutated in place by the gameplay layer — a level
/// reset rewrites transforms rather than rebuilding the list — so this is a
/// mutable value object on purpose.
class RenderInstance {
  RenderInstance({
    required this.mesh,
    Matrix4? transform,
    this.visible = true,
    this.castsShadow = true,
    this.highlight = 0.0,
    this.tint = 0,
    this.opacity = 1.0,
    this.shadowScale = 1.0,
    this.sortBias = 0.0,
  }) : transform = transform ?? Matrix4.identity();

  Mesh mesh;

  /// Object → world.
  final Matrix4 transform;

  bool visible;

  /// Whether this instance contributes a soft contact shadow.
  bool castsShadow;

  /// 0 = normal, 1 = fully highlighted. Drives the pulsing "you can tap this"
  /// treatment on valid starter objects.
  double highlight;

  /// Packed 0xAARRGGBB. When the alpha byte is non-zero this colour is
  /// blended over every material of the mesh by [tintAmount].
  int tint;
  double tintAmount = 0.0;

  /// Fades the whole instance. Used by debris despawn and level intros.
  double opacity;

  /// Multiplies the projected ground-shadow size.
  double shadowScale;

  /// Nudges this instance's triangles in the depth sort. Positive pushes the
  /// instance further away. Used to resolve co-planar decals such as the
  /// floor plate under a target.
  double sortBias;

  void setTransform(Matrix4 m) => transform.setFrom(m);
}
