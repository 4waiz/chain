import 'package:flutter/material.dart';

import '../../engine/render/palette.dart';
import '../level/level_spec.dart';
import '../play/reaction_tracker.dart';
import '../play/scoring.dart';
import 'design.dart';

/// Shared dimmed backdrop for every in-play sheet.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.child, this.t = 1.0});
  final Widget child;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        // Tinted with the ink slate rather than the studio grey: on a
        // near-white backdrop a light scrim is invisible and the white result
        // card has nothing to sit against.
        color: Toy.inkStrong.withValues(alpha: 0.34 * t.clamp(0.0, 1.0)),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(D.s5),
          child: Transform.translate(
            offset: Offset(
              0,
              (1 - Curves.easeOutBack.transform(t.clamp(0.0, 1.0))) * 40,
            ),
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          ),
        ),
      ),
    );
  }
}

class PauseSheet extends StatelessWidget {
  const PauseSheet({
    super.key,
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
  });

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return _Scrim(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ToyCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Paused', style: D.title(Toy.inkStrong)),
              const SizedBox(height: D.s5),
              ToyButton(
                label: 'Resume',
                colour: Toy.green,
                wide: true,
                onTap: onResume,
              ),
              const SizedBox(height: D.s3),
              ToyButton(
                label: 'Restart',
                colour: Toy.blue,
                wide: true,
                onTap: onRestart,
              ),
              const SizedBox(height: D.s3),
              ToyButton(
                label: 'Level map',
                colour: Toy.white,
                textColour: Toy.ink,
                wide: true,
                onTap: onQuit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when a reaction stalls. The priority is getting back in fast: retry
/// is the biggest thing on screen and one tap away.
class FailSheet extends StatelessWidget {
  const FailSheet({
    super.key,
    required this.t,
    required this.breakdown,
    required this.chain,
    required this.onRetry,
    required this.onMenu,
    this.showHint = false,
    this.hint = '',
  });

  final double t;
  final StageRun? breakdown;
  final int chain;
  final VoidCallback onRetry;
  final VoidCallback onMenu;
  final bool showHint;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final String where = breakdown?.spec.label ?? 'The reaction stopped';

    return _Scrim(
      t: t,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ToyCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  color: Toy.studioDeep,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.link_off_rounded,
                  color: Toy.greyDark,
                  size: 30,
                ),
              ),
              const SizedBox(height: D.s4),
              Text('Chain broke', style: D.title(Toy.inkStrong)),
              const SizedBox(height: D.s2),
              Text(
                'It stopped at: $where',
                style: D.body(Toy.inkSoft),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: D.s3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ToyChip(
                    icon: Icons.auto_awesome_motion_rounded,
                    value: '$chain activated',
                    colour: Toy.blue,
                    background: Toy.studio,
                  ),
                ],
              ),
              if (showHint && hint.isNotEmpty) ...<Widget>[
                const SizedBox(height: D.s4),
                Container(
                  padding: const EdgeInsets.all(D.s3),
                  decoration: BoxDecoration(
                    color: Toy.yellow.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(D.rMd),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.lightbulb_rounded,
                        color: Toy.yellowDark,
                        size: 20,
                      ),
                      const SizedBox(width: D.s2),
                      Expanded(child: Text(hint, style: D.body(Toy.inkStrong))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: D.s5),
              ToyButton(
                label: 'Try again',
                colour: Toy.blue,
                icon: Icons.refresh_rounded,
                wide: true,
                big: true,
                onTap: onRetry,
              ),
              const SizedBox(height: D.s3),
              ToyButton(
                label: 'Level map',
                colour: Toy.white,
                textColour: Toy.ink,
                wide: true,
                onTap: onMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompleteSheet extends StatelessWidget {
  const CompleteSheet({
    super.key,
    required this.t,
    required this.result,
    required this.spec,
    required this.onRetry,
    required this.onContinue,
  });

  final double t;
  final LevelResult result;
  final LevelSpec spec;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: BouncingPieces(t: t * 6)),
        _Scrim(
          t: t,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: ToyCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(spec.name, style: D.title(Toy.inkStrong)),
                  const SizedBox(height: D.s4),
                  StarRow(earned: result.stars, size: 46, progress: t),
                  const SizedBox(height: D.s5),
                  _StatRow(
                    icon: Icons.link_rounded,
                    label: 'Chain',
                    value: '${result.chainLength}',
                    colour: Toy.blue,
                  ),
                  _StatRow(
                    icon: Icons.bolt_rounded,
                    label: 'Multiplier',
                    value: '${result.maxMultiplier.toStringAsFixed(1)}x',
                    colour: Toy.orange,
                  ),
                  _StatRow(
                    icon: Icons.timer_rounded,
                    label: 'Time',
                    value: '${result.timeSec.toStringAsFixed(1)}s',
                    colour: Toy.green,
                  ),
                  _StatRow(
                    icon: Icons.star_rounded,
                    label: 'Score',
                    value: '${result.score}',
                    colour: Toy.yellow,
                  ),
                  _StatRow(
                    icon: Icons.monetization_on_rounded,
                    label: 'Coins',
                    value: '+${result.coins}',
                    colour: Toy.yellowDark,
                  ),
                  if (spec.bonuses.isNotEmpty) ...<Widget>[
                    const SizedBox(height: D.s4),
                    const Divider(color: Toy.studioDeep, height: 1),
                    const SizedBox(height: D.s3),
                    for (final BonusSpec b in spec.bonuses)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              result.bonusesMet.contains(b.id)
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 19,
                              color: result.bonusesMet.contains(b.id)
                                  ? Toy.green
                                  : Toy.grey,
                            ),
                            const SizedBox(width: D.s2),
                            Expanded(
                              child: Text(
                                b.description,
                                style: D.body(
                                  result.bonusesMet.contains(b.id)
                                      ? Toy.inkStrong
                                      : Toy.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: D.s5),
                  Row(
                    children: <Widget>[
                      ToyIconButton(
                        icon: Icons.refresh_rounded,
                        onTap: onRetry,
                        size: 54,
                        colour: Toy.studio,
                        tooltip: 'Retry',
                      ),
                      const SizedBox(width: D.s3),
                      Expanded(
                        child: ToyButton(
                          label: 'Continue',
                          colour: Toy.green,
                          wide: true,
                          big: true,
                          onTap: onContinue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colour,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: colour),
          ),
          const SizedBox(width: D.s3),
          Expanded(child: Text(label, style: D.body(Toy.inkSoft))),
          Text(value, style: D.heading(Toy.inkStrong)),
        ],
      ),
    );
  }
}
