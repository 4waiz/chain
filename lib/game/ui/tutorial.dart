import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/render/palette.dart';
import '../play/level_runtime.dart';
import 'design.dart';

/// What the tutorial is currently saying.
enum CoachStep { look, tap, watching, chain, done }

/// First-run coaching.
///
/// Deliberately three short beats and no modal gates. The brief asks for no
/// long text and no complicated tutorial, and a chain-reaction game teaches
/// itself if the player is looking at the right thing — so this points at
/// things and then gets out of the way. It never blocks input: the player can
/// tap the cannon during any step and the tutorial simply moves on.
class CoachOverlay extends StatelessWidget {
  const CoachOverlay({
    super.key,
    required this.step,
    required this.chainLength,
    required this.onDismiss,
  });

  final CoachStep step;
  final int chainLength;
  final VoidCallback onDismiss;

  /// Derives the step from the run state, so there is no separate state
  /// machine to keep in sync with what the player can actually see.
  static CoachStep stepFor(RunPhase phase, double sinceLoad, int chain) {
    if (phase == RunPhase.inspecting) {
      return sinceLoad < 2.0 ? CoachStep.look : CoachStep.tap;
    }
    if (phase == RunPhase.reacting) {
      return chain >= 4 ? CoachStep.chain : CoachStep.watching;
    }
    return CoachStep.done;
  }

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title, String body)? content = switch (step) {
      CoachStep.look => (
        Icons.swap_vert_rounded,
        'The cannon is aiming',
        'It sweeps up and down. The dotted arc is where the ball will land.',
      ),
      CoachStep.tap => (
        Icons.touch_app_rounded,
        'Tap to fire',
        'Wait for the arc to turn green, then tap anywhere.',
      ),
      CoachStep.chain => (
        Icons.link_rounded,
        'That is your chain',
        'Every object the reaction touches adds to your score.',
      ),
      CoachStep.watching || CoachStep.done => null,
    };

    if (content == null) return const SizedBox.shrink();
    final (IconData icon, String title, String body) c = content;

    return Positioned(
      left: D.s4,
      right: D.s4,
      bottom: 96,
      child: IgnorePointer(
        ignoring: false,
        child: _Card(
          key: ValueKey<CoachStep>(step),
          icon: c.$1,
          title: c.$2,
          body: c.$3,
          onDismiss: onDismiss,
        ),
      ),
    );
  }
}

class _Card extends StatefulWidget {
  const _Card({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onDismiss;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - t)),
            child: child,
          ),
        );
      },
      child: ToyCard(
        padding: const EdgeInsets.fromLTRB(D.s3, D.s3, D.s2, D.s3),
        child: Row(
          children: <Widget>[
            _Pulse(icon: widget.icon),
            const SizedBox(width: D.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.title, style: D.heading(Toy.inkStrong)),
                  const SizedBox(height: 2),
                  Text(widget.body, style: D.body(Toy.inkSoft)),
                ],
              ),
            ),
            IconButton(
              onPressed: widget.onDismiss,
              icon: const Icon(
                Icons.close_rounded,
                size: 20,
                color: Toy.inkSoft,
              ),
              tooltip: 'Skip tips',
            ),
          ],
        ),
      ),
    );
  }
}

/// A softly pulsing icon chip, so the card reads as live guidance.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.icon});
  final IconData icon;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, _) {
        final double s = 1.0 + 0.07 * math.sin(_c.value * math.pi * 2);
        return Transform.scale(
          scale: s,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Toy.blue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(widget.icon, color: Toy.blue, size: 24),
          ),
        );
      },
    );
  }
}
