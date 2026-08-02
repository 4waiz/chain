import 'package:flutter/material.dart';

import '../../data/audio_service.dart';
import '../../data/save_service.dart';
import '../../engine/render/palette.dart';
import '../level/level_spec.dart';
import '../level/procedural.dart';
import '../play/scoring.dart';
import 'design.dart';
import 'play_screen.dart';

/// The Daily Challenge.
///
/// The puzzle is generated from the calendar date alone, so it needs no server
/// and no network: every player on a given day gets exactly the same chain,
/// and it can be replayed offline forever.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  late DateTime _today;
  late String _dayKey;
  late LevelSpec _spec;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _dayKey = ProceduralLevels.dayKey(_today);
    _spec = ProceduralLevels.daily(_today);
  }

  bool get _playedToday => SaveService.instance.lastDailyDay == _dayKey;

  Future<void> _play() async {
    AudioService.instance.uiTap();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayScreen.fromSpec(
          spec: _spec,
          mode: PlayMode.daily,
          onFinished: (LevelResult r) async {
            if (r.completed) {
              await SaveService.instance.recordDaily(_dayKey, r.score);
            }
          },
        ),
      ),
    );
    if (mounted) setState(() {});
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
                        'Daily Challenge',
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
                                color: Toy.red.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(26),
                              ),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    '${_today.day}',
                                    style: D.display(Toy.red),
                                  ),
                                  Text(
                                    _monthName(_today.month),
                                    style: D.tiny(Toy.red),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: D.s4),
                            Text(
                              _playedToday ? 'Done for today' : "Today's chain",
                              style: D.heading(Toy.inkStrong),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'A fresh puzzle every day, the same one for everyone.',
                              style: D.body(Toy.inkSoft),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: D.s5),
                            ToyButton(
                              label: _playedToday ? 'Play again' : 'Start',
                              colour: _playedToday ? Toy.blue : Toy.red,
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
                              icon: Icons.local_fire_department_rounded,
                              label: 'Streak',
                              value: '${save.dailyStreak}',
                              colour: Toy.orange,
                            ),
                          ),
                          const SizedBox(width: D.s3),
                          Expanded(
                            child: _Stat(
                              icon: Icons.emoji_events_rounded,
                              label: "Today's best",
                              value: _playedToday
                                  ? '${save.dailyBestScore}'
                                  : '—',
                              colour: Toy.yellowDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: D.s4),
                      ToyCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Bonus objectives',
                              style: D.heading(Toy.inkStrong),
                            ),
                            const SizedBox(height: D.s2),
                            for (final BonusSpec b in _spec.bonuses)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(
                                      Icons.circle_outlined,
                                      size: 16,
                                      color: Toy.grey,
                                    ),
                                    const SizedBox(width: D.s2),
                                    Expanded(
                                      child: Text(
                                        b.description,
                                        style: D.body(Toy.inkSoft),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: D.s3),
                            Text(
                              'Reward: 40 coins, plus 5 for each day of your streak.',
                              style: D.tiny(Toy.inkSoft),
                            ),
                          ],
                        ),
                      ),
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

  static String _monthName(int m) => const <String>[
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ][(m - 1).clamp(0, 11)];
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
