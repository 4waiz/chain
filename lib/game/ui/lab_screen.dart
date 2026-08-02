import 'package:flutter/material.dart';

import '../../data/audio_service.dart';
import '../../data/save_service.dart';
import '../../engine/render/palette.dart';
import '../level/level_spec.dart';
import '../level/procedural.dart';
import '../play/scoring.dart';
import 'design.dart';
import 'play_screen.dart';

/// Reaction Lab.
///
/// Unlocked after ten campaign levels. Modular reaction sections are chained
/// into progressively longer runs; the goal is the longest chain and the
/// highest multiplier rather than simply finishing.
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  int _run = 0;
  LevelResult? _last;

  int get _seed => 0x5EED ^ (_run * 2654435761) & 0x7FFFFFFF;

  Future<void> _play() async {
    AudioService.instance.uiTap();
    final LevelSpec spec = ProceduralLevels.lab(_seed, _run);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayScreen.fromSpec(
          spec: spec,
          mode: PlayMode.lab,
          onFinished: (LevelResult r) async {
            _last = r;
            if (r.completed) {
              await SaveService.instance.recordLab(r.score, r.chainLength);
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      // Each completed run makes the next one longer.
      if (_last?.completed == true) _run++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SaveService save = SaveService.instance;

    return Scaffold(
      body: StudioBackdrop(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(D.s4, D.s3, D.s4, D.s2),
                child: Row(
                  children: <Widget>[
                    ToyIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () {
                        AudioService.instance.uiTap();
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: D.s3),
                    Expanded(
                      child: Text(
                        'Reaction Lab',
                        style: D.title(Toy.inkStrong),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(D.s4),
                  child: Column(
                    children: <Widget>[
                      ToyCard(
                        child: Column(
                          children: <Widget>[
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: Toy.purple.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(26),
                              ),
                              child: const Icon(
                                Icons.science_rounded,
                                size: 42,
                                color: Toy.purple,
                              ),
                            ),
                            const SizedBox(height: D.s4),
                            Text(
                              'Run ${_run + 1}',
                              style: D.heading(Toy.inkStrong),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Reaction sections chained end to end. Finish a run '
                              'and the next one gets longer.',
                              style: D.body(Toy.inkSoft),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: D.s5),
                            ToyButton(
                              label: 'Start run',
                              colour: Toy.purple,
                              icon: Icons.play_arrow_rounded,
                              wide: true,
                              big: true,
                              onTap: _play,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: D.s4),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _Stat(
                              icon: Icons.link_rounded,
                              label: 'Longest chain',
                              value: '${save.labBestChain}',
                              colour: Toy.blue,
                            ),
                          ),
                          const SizedBox(width: D.s3),
                          Expanded(
                            child: _Stat(
                              icon: Icons.emoji_events_rounded,
                              label: 'Best score',
                              value: '${save.labBestScore}',
                              colour: Toy.yellowDark,
                            ),
                          ),
                        ],
                      ),
                      if (_last != null) ...<Widget>[
                        const SizedBox(height: D.s4),
                        ToyCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('Last run', style: D.heading(Toy.inkStrong)),
                              const SizedBox(height: D.s2),
                              Text(
                                _last!.completed
                                    ? 'Completed with a chain of ${_last!.chainLength} '
                                          'at ${_last!.maxMultiplier.toStringAsFixed(1)}x'
                                    : 'The chain broke after ${_last!.chainLength} objects',
                                style: D.body(Toy.inkSoft),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
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
    return ToyCard(
      padding: const EdgeInsets.symmetric(vertical: D.s4, horizontal: D.s3),
      child: Column(
        children: <Widget>[
          Icon(icon, color: colour, size: 26),
          const SizedBox(height: 6),
          Text(value, style: D.number(Toy.inkStrong)),
          Text(label, style: D.tiny(Toy.inkSoft)),
        ],
      ),
    );
  }
}
