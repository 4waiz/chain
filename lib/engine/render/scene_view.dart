import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'camera.dart';
import 'render_instance.dart';
import 'renderer.dart';

/// Drives a [Renderer] from a [Ticker] and paints it into the widget tree.
///
/// The 3D view is a plain `CustomPaint`, which means the whole game surface is
/// ordinary Flutter: the HUD composes over it with real widgets, hit-testing is
/// normal, and there is no platform view or texture bridge to go wrong.
class SceneView extends StatefulWidget {
  const SceneView({
    super.key,
    required this.camera,
    required this.instances,
    required this.renderer,
    this.onFrame,
    this.onTapWorld,
    this.onPan,
    this.groundY = 0.0,
    this.paused = false,
    this.overlay,
  });

  final OrbitCamera camera;

  /// Live list, read every frame. The gameplay layer mutates it in place.
  final List<RenderInstance> instances;

  final Renderer renderer;

  /// Called once per frame with the delta in seconds, before painting.
  final void Function(double dt)? onFrame;

  /// Tap in local widget coordinates, plus the widget size, so callers can
  /// build a pick ray.
  final void Function(Offset local, Size size)? onTapWorld;

  /// Horizontal/vertical drag in pixels, for limited camera inspection.
  final void Function(Offset delta)? onPan;

  final double groundY;
  final bool paused;

  /// Painted on top of the 3D scene in screen space (particles, markers).
  final void Function(Canvas canvas, Size size)? overlay;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  double _fpsAccum = 0;
  int _fpsFrames = 0;
  double fps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(SceneView old) {
    super.didUpdateWidget(old);
    if (widget.paused != old.paused) {
      if (widget.paused) {
        _ticker.stop();
      } else {
        _last = Duration.zero;
        _ticker.start();
      }
    }
  }

  void _tick(Duration now) {
    double dt = 0;
    if (_last != Duration.zero) {
      dt = (now - _last).inMicroseconds / 1e6;
    }
    _last = now;
    // Clamp so a dropped frame or a resume from background cannot teleport the
    // simulation; the fixed-step physics loop handles catch-up itself.
    if (dt > 0.05) dt = 0.05;

    _fpsAccum += dt;
    _fpsFrames++;
    if (_fpsAccum >= 0.5) {
      fps = _fpsFrames / _fpsAccum;
      _fpsAccum = 0;
      _fpsFrames = 0;
    }

    widget.onFrame?.call(dt);
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Size size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails d) => widget.onTapWorld?.call(d.localPosition, size),
          onPanUpdate: (DragUpdateDetails d) => widget.onPan?.call(d.delta),
          child: CustomPaint(
            size: size,
            isComplex: true,
            willChange: true,
            painter: _ScenePainter(
              repaint: _repaint,
              camera: widget.camera,
              instances: widget.instances,
              renderer: widget.renderer,
              groundY: widget.groundY,
              overlay: widget.overlay,
            ),
          ),
        );
      },
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required Listenable repaint,
    required this.camera,
    required this.instances,
    required this.renderer,
    required this.groundY,
    this.overlay,
  }) : super(repaint: repaint);

  final OrbitCamera camera;
  final List<RenderInstance> instances;
  final Renderer renderer;
  final double groundY;
  final void Function(Canvas canvas, Size size)? overlay;

  @override
  void paint(Canvas canvas, Size size) {
    renderer.drawBackdrop(canvas, size);
    camera.update(size.height <= 0 ? 1.0 : size.width / size.height);
    renderer.render(canvas, size, camera, instances, groundY: groundY);
    overlay?.call(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => true;
}
