import 'dart:math' as math;

/// Soft three-point studio lighting.
///
/// `logo.png` is lit like a product photograph: a big soft key from the upper
/// left, a weak bounce fill from the right, and a sky/ground hemisphere that
/// keeps every downward face from going black. Top faces read almost white,
/// front faces read as the true hue, side faces sit a little darker. Those
/// three tiers are what make the toys look moulded rather than flat.
class StudioLight {
  const StudioLight({
    this.keyDir = const <double>[-0.34, 0.86, 0.38],
    this.fillDir = const <double>[0.72, 0.22, 0.56],
    this.ambient = 0.60,
    this.keyIntensity = 0.46,
    this.fillIntensity = 0.13,
    this.hemiIntensity = 0.20,
    this.highlightLift = 0.62,
  });

  /// Direction *towards* the key light.
  final List<double> keyDir;

  /// Direction *towards* the soft bounce fill.
  final List<double> fillDir;

  /// Base light every face receives, so nothing is ever pure black.
  final double ambient;
  final double keyIntensity;
  final double fillIntensity;
  final double hemiIntensity;

  /// How strongly over-bright faces are pulled towards white instead of
  /// simply clipping. This is what produces the soft satin sheen on the
  /// bevelled top edges rather than a blown-out flat colour.
  final double highlightLift;

  /// A dimmer, flatter variant used when "reduced motion"/low quality is on:
  /// fewer tiers means less per-face colour variance and cheaper eye strain.
  StudioLight get flattened => StudioLight(
    keyDir: keyDir,
    fillDir: fillDir,
    ambient: 0.72,
    keyIntensity: 0.30,
    fillIntensity: 0.08,
    hemiIntensity: 0.14,
    highlightLift: 0.45,
  );

  static List<double> normalise(List<double> v) {
    final double l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (l < 1e-9) return <double>[0, 1, 0];
    return <double>[v[0] / l, v[1] / l, v[2] / l];
  }

  /// World-space direction the ground shadow is cast along (away from key).
  /// Split into scalars because Dart cannot const-index a const list.
  static const double shadowX = 0.34;
  static const double shadowY = -0.86;
  static const double shadowZ = -0.38;
  static const List<double> shadowDir = <double>[shadowX, shadowY, shadowZ];
}
