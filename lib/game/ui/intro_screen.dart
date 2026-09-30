import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/audio_service.dart';
import '../../engine/render/palette.dart';
import 'design.dart';
import 'home_screen.dart';

/// The animated opening.
///
/// The whole sequence is under three seconds and skippable by tapping, because
/// a splash screen is a toll a returning player pays every session. It earns
/// its place by doing one useful thing: the logo lands with the same bounce and
/// the same confetti the game uses when you win a level, so the first thing a
/// player ever sees is the feel of the reward.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _leaving = false;

  static const Duration _total = Duration(milliseconds: 2900);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total)..forward();
    _c.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed) _go();
    });
    // The burst lands with the logo, not with the first frame.
    Future<void>.delayed(const Duration(milliseconds: 380), () {
      if (mounted) AudioService.instance.play('level_complete', volume: 0.55);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, Animation<double> a, _, Widget child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _go,
        child: StudioBackdrop(
          child: AnimatedBuilder(
            animation: _c,
            builder: (BuildContext context, _) {
              final double t = _c.value;

              // Logo: a held beat, then an elastic landing.
              final double landRaw = ((t - 0.06) / 0.44).clamp(0.0, 1.0);
              final double land = Curves.elasticOut.transform(landRaw);
              final double scale = 0.62 + 0.38 * land;
              final double logoFade = (t / 0.16).clamp(0.0, 1.0);

              // Tagline arrives after the logo has settled.
              final double tagT = ((t - 0.44) / 0.28).clamp(0.0, 1.0);
              final double tag = Curves.easeOutCubic.transform(tagT);

              // Everything fades together at the end so the hand-off to the
              // home screen is a dissolve rather than a cut.
              final double out = ((t - 0.86) / 0.14).clamp(0.0, 1.0);
              final double alpha = 1.0 - out;

              return Opacity(
                opacity: alpha,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(painter: _BurstPainter(landRaw)),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Opacity(
                          opacity: logoFade,
                          child: Transform.scale(
                            scale: scale,
                            child: SizedBox(
                              // Sized explicitly. A bare Image in an
                              // unbounded Column takes its intrinsic 1024 px
                              // and gets clipped on smaller screens.
                              width: math.min(
                                MediaQuery.sizeOf(context).width * 0.82,
                                420,
                              ),
                              child: Image.asset(
                                'logo.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: D.s4),
                        Opacity(
                          opacity: tag,
                          child: Transform.translate(
                            offset: Offset(0, 14 * (1 - tag)),
                            child: Text(
                              'One tap. Total chaos.',
                              style: D.heading(Toy.ink),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: D.s7,
                      child: Opacity(
                        opacity: (tag * 0.6).clamp(0.0, 0.6),
                        child: Text('tap to skip', style: D.tiny(Toy.inkSoft)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Toy capsules thrown outward from behind the logo as it lands.
class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.t);

  /// 0..1, matching the logo's landing.
  final double t;

  static const int _count = 22;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.02) return;
    final Paint p = Paint()..isAntiAlias = true;
    final Offset centre = Offset(size.width * 0.5, size.height * 0.44);

    // Deterministic layout — the same burst every launch, no RNG.
    for (int i = 0; i < _count; i++) {
      final double seed = (i * 0.6180339887) % 1.0;
      final double ang = (i / _count) * math.pi * 2 + seed * 0.6;
      final double speed = size.shortestSide * (0.34 + seed * 0.52);

      // Ease out and fall, so pieces decelerate outward and sag under gravity.
      final double e = Curves.easeOutCubic.transform(t);
      final double dist = speed * e;
      final double sag = size.height * 0.22 * e * e * (0.4 + seed);

      final Offset at =
          centre +
          Offset(math.cos(ang) * dist, math.sin(ang) * dist * 0.72 + sag);

      final double fade = (1.0 - t).clamp(0.0, 1.0);
      if (fade <= 0.01) continue;

      final double w = 9 + seed * 11;
      p.color = Toy.confetti[i % Toy.confetti.length].withValues(
        alpha: 0.9 * fade,
      );

      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(ang + e * 5.0 * (0.5 + seed));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w * 2.0, height: w),
          Radius.circular(w * 0.5),
        ),
        p,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}
