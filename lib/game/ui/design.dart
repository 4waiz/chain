import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/render/palette.dart';

/// The Chain Reaction City design system.
///
/// Everything is derived from `logo.png`: a bright near-white studio, soft
/// slate text, four saturated toy primaries, chunky rounded shapes and soft
/// low-contrast shadows. No dark surfaces, no gradients other than the studio
/// backdrop, no glass, no default-looking Material widgets.
class D {
  const D._();

  // ---------------------------------------------------------------- radius
  static const double rSm = 12;
  static const double rMd = 18;
  static const double rLg = 26;
  static const double rXl = 34;
  static const double rPill = 999;

  // --------------------------------------------------------------- spacing
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
  static const double s7 = 48;

  // ----------------------------------------------------------- typography
  /// Nunito, a rounded geometric sans that matches the wordmark. Registered
  /// as a variable font, so weights come from `fontVariations`.
  static TextStyle _t(
    double size,
    double weight,
    Color colour, {
    double height = 1.2,
    double spacing = 0,
  }) {
    return TextStyle(
      fontFamily: 'Toy',
      fontSize: size,
      color: colour,
      height: height,
      letterSpacing: spacing,
      fontVariations: <FontVariation>[FontVariation('wght', weight)],
    );
  }

  static TextStyle display(Color c) =>
      _t(40, 800, c, height: 1.05, spacing: -0.5);
  static TextStyle title(Color c) => _t(27, 800, c, height: 1.1, spacing: -0.2);
  static TextStyle heading(Color c) => _t(20, 700, c);
  static TextStyle body(Color c) => _t(15.5, 500, c, height: 1.35);
  static TextStyle label(Color c) => _t(13.5, 700, c, spacing: 0.2);
  static TextStyle number(Color c) => _t(22, 800, c, spacing: -0.3);
  static TextStyle tiny(Color c) => _t(11.5, 700, c, spacing: 0.5);

  // ---------------------------------------------------------------- shadow
  /// Soft, low-contrast, always straight down — the same contact shadow the
  /// 3D scene uses, so UI and diorama feel lit by one studio.
  static List<BoxShadow> lift({
    double y = 6,
    double blur = 18,
    double a = 0.10,
  }) => <BoxShadow>[
    BoxShadow(
      color: Toy.inkStrong.withValues(alpha: a),
      offset: Offset(0, y),
      blurRadius: blur,
    ),
  ];

  static List<BoxShadow> get card => lift(y: 8, blur: 24, a: 0.09);
  static List<BoxShadow> get chip => lift(y: 3, blur: 8, a: 0.08);

  static ThemeData theme() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Toy.studio,
      fontFamily: 'Toy',
      colorScheme: const ColorScheme.light(
        primary: Toy.blue,
        secondary: Toy.yellow,
        surface: Toy.white,
        error: Toy.red,
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }
}

/// The studio backdrop used behind every screen.
class StudioBackdrop extends StatelessWidget {
  const StudioBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.45),
          radius: 1.15,
          colors: <Color>[Toy.studioLift, Toy.studio, Toy.studioDeep],
          stops: <double>[0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// The primary chunky toy button.
class ToyButton extends StatefulWidget {
  const ToyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.colour = Toy.blue,
    this.textColour = Toy.white,
    this.icon,
    this.wide = false,
    this.big = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final Color colour;
  final Color textColour;
  final IconData? icon;
  final bool wide;
  final bool big;
  final bool enabled;

  @override
  State<ToyButton> createState() => _ToyButtonState();
}

class _ToyButtonState extends State<ToyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool on = widget.enabled && widget.onTap != null;
    final Color base = on ? widget.colour : Toy.grey;
    final double h = widget.big ? 68 : 54;

    return Semantics(
      button: true,
      enabled: on,
      label: widget.label,
      child: GestureDetector(
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapCancel: on ? () => setState(() => _down = false) : null,
        onTapUp: on
            ? (_) {
                setState(() => _down = false);
                widget.onTap!.call();
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          height: h,
          width: widget.wide ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: widget.big ? D.s6 : D.s5),
          // The press pushes the button down into its own shadow, the way a
          // physical toy button would.
          transform: Matrix4.translationValues(0, _down ? 3 : 0, 0),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(D.rLg),
            boxShadow: _down
                ? D.lift(y: 2, blur: 6, a: 0.12)
                : <BoxShadow>[
                    BoxShadow(
                      color: _darken(base, 0.18),
                      offset: const Offset(0, 5),
                      blurRadius: 0,
                    ),
                    ...D.lift(y: 8, blur: 18, a: 0.12),
                  ],
          ),
          child: Row(
            mainAxisSize: widget.wide ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                Icon(
                  widget.icon,
                  color: widget.textColour,
                  size: widget.big ? 26 : 21,
                ),
                const SizedBox(width: D.s3),
              ],
              Text(
                widget.label,
                style: (widget.big
                    ? D.title(widget.textColour)
                    : D.heading(widget.textColour)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _darken(Color c, double amount) {
    final HSLColor h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - amount).clamp(0.0, 1.0)).toColor();
  }
}

/// A small round icon button, used for pause/restart/back.
class ToyIconButton extends StatelessWidget {
  const ToyIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.colour = Toy.white,
    this.iconColour = Toy.ink,
    this.size = 46,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color colour;
  final Color iconColour;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            boxShadow: D.chip,
          ),
          child: Icon(icon, color: iconColour, size: size * 0.5),
        ),
      ),
    );
  }
}

/// White rounded panel used for every dialog and result sheet.
class ToyCard extends StatelessWidget {
  const ToyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(D.s5),
    this.colour = Toy.white,
    this.radius = D.rXl,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color colour;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: D.card,
      ),
      child: child,
    );
  }
}

/// Coin / star counter pill.
class ToyChip extends StatelessWidget {
  const ToyChip({
    super.key,
    required this.icon,
    required this.value,
    this.colour = Toy.yellow,
    this.background = Toy.white,
  });

  final IconData icon;
  final String value;
  final Color colour;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: D.s3, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(D.rPill),
        boxShadow: D.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: colour, size: 17),
          const SizedBox(width: 6),
          Text(value, style: D.label(Toy.inkStrong)),
        ],
      ),
    );
  }
}

/// Three-star rating display, with an optional pop-in animation.
class StarRow extends StatelessWidget {
  const StarRow({
    super.key,
    required this.earned,
    this.size = 30,
    this.total = 3,
    this.progress = 1.0,
  });

  final int earned;
  final double size;
  final int total;

  /// 0..1 reveal used by the results screen so stars land one at a time.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(total, (int i) {
        final bool on = i < earned;
        final double t = ((progress * total) - i).clamp(0.0, 1.0);
        final double scale = on
            ? (0.55 + 0.45 * Curves.elasticOut.transform(t))
            : 1.0;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.09),
          child: Transform.scale(
            scale: on ? scale : 1.0,
            child: Icon(
              on ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: on ? Toy.yellow : Toy.grey,
            ),
          ),
        );
      }),
    );
  }
}

/// A slim progress bar in the toy palette.
class ToyBar extends StatelessWidget {
  const ToyBar({
    super.key,
    required this.value,
    this.colour = Toy.green,
    this.height = 10,
    this.background = Toy.studioDeep,
  });

  final double value;
  final Color colour;
  final double height;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Container(color: background),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouncing toy pieces used behind result panels.
class BouncingPieces extends StatelessWidget {
  const BouncingPieces({super.key, required this.t, this.count = 14});

  final double t;
  final int count;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PiecesPainter(t, count),
        size: Size.infinite,
      ),
    );
  }
}

class _PiecesPainter extends CustomPainter {
  _PiecesPainter(this.t, this.count);
  final double t;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..isAntiAlias = true;
    for (int i = 0; i < count; i++) {
      // Deterministic layout: same celebration every time, no RNG.
      final double seed = (i * 0.6180339887) % 1.0;
      final double x = size.width * (0.06 + seed * 0.88);
      final double phase = t * (0.7 + seed * 0.6) + seed * 6.28;
      final double y =
          size.height * (0.10 + ((math.sin(phase) + 1) * 0.5) * 0.78);
      final double r = 7 + seed * 9;
      p.color = Toy.confetti[i % Toy.confetti.length].withValues(alpha: 0.85);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(phase * 0.8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: r * 2.1, height: r),
          Radius.circular(r * 0.5),
        ),
        p,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PiecesPainter old) => old.t != t;
}
