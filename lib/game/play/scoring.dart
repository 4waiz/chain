import 'dart:math' as math;

import '../level/level_spec.dart';
import 'level_object.dart';
import 'reaction_tracker.dart';

/// The result of one attempt.
class LevelResult {
  LevelResult({
    required this.completed,
    required this.stars,
    required this.score,
    required this.coins,
    required this.chainLength,
    required this.objectsActivated,
    required this.timeSec,
    required this.usedIntendedStarter,
    required this.stalled,
    required this.bonusesMet,
    required this.starsCollected,
    required this.maxMultiplier,
  });

  final bool completed;
  final int stars;
  final int score;
  final int coins;
  final int chainLength;
  final int objectsActivated;
  final double timeSec;
  final bool usedIntendedStarter;
  final bool stalled;

  /// Ids of the bonus objectives satisfied this run.
  final List<String> bonusesMet;
  final int starsCollected;
  final double maxMultiplier;

  static LevelResult failed({
    required int chainLength,
    required double timeSec,
    required bool stalled,
  }) => LevelResult(
    completed: false,
    stars: 0,
    score: 0,
    coins: 0,
    chainLength: chainLength,
    objectsActivated: chainLength,
    timeSec: timeSec,
    usedIntendedStarter: false,
    stalled: stalled,
    bonusesMet: const <String>[],
    starsCollected: 0,
    maxMultiplier: 1.0,
  );
}

/// Turns a finished run into stars, score and coins.
///
/// The three-star rule follows the brief exactly:
///   one star   — complete the level
///   two stars  — complete a bonus objective
///   three stars— complete the optimal reaction (every bonus, no stall)
class Scoring {
  const Scoring();

  static const int _completionBase = 500;
  static const int _perChainLink = 40;
  static const int _perCollectedStar = 150;
  static const int _noStallBonus = 200;
  static const int _intendedStarterBonus = 150;

  /// Multiplier shown climbing during the reaction. Grows with chain length
  /// and is capped so late levels stay legible.
  static double multiplierFor(int chainLength) =>
      math.min(9.9, 1.0 + chainLength * 0.22);

  LevelResult evaluate({
    required LevelSpec level,
    required ReactionTracker tracker,
    required Iterable<LevelObject> objects,
    required double timeSec,
    required String? starterUsed,
    required String? intendedStarter,
  }) {
    if (!tracker.goalReached) {
      return LevelResult.failed(
        chainLength: tracker.chainLength,
        timeSec: timeSec,
        stalled: tracker.stalled,
      );
    }

    final int collected = objects
        .where((LevelObject o) => o.spec.collectible == 'star' && o.collected)
        .length;
    final int coinsPicked = objects
        .where((LevelObject o) => o.spec.collectible == 'coin' && o.collected)
        .length;

    final bool intended =
        intendedStarter == null || starterUsed == intendedStarter;
    final List<String> met = <String>[];
    for (final BonusSpec b in level.bonuses) {
      if (_bonusMet(b, level, tracker, objects, timeSec, intended)) {
        met.add(b.id);
      }
    }

    // Stars.
    int stars = 1;
    if (met.isNotEmpty) {
      stars = 2;
    }
    if (level.bonuses.isNotEmpty &&
        met.length == level.bonuses.length &&
        !tracker.stalled) {
      stars = 3;
    }

    int score = _completionBase;
    score += tracker.chainLength * _perChainLink;
    score += collected * _perCollectedStar;
    if (!tracker.stalled) {
      score += _noStallBonus;
    }
    if (intended) {
      score += _intendedStarterBonus;
    }
    // Speed: full marks at or under par, tapering to zero at triple par.
    final double speedRatio = (level.parTimeSec / math.max(0.5, timeSec)).clamp(
      0.0,
      2.0,
    );
    score += (speedRatio * 180).round();

    score = (score * multiplierFor(tracker.chainLength)).round();

    final int coins =
        12 + coinsPicked * 8 + stars * 10 + (tracker.chainLength ~/ 3);

    return LevelResult(
      completed: true,
      stars: stars,
      score: score,
      coins: coins,
      chainLength: tracker.chainLength,
      objectsActivated: objects.where((LevelObject o) => o.participated).length,
      timeSec: timeSec,
      usedIntendedStarter: intended,
      stalled: tracker.stalled,
      bonusesMet: met,
      starsCollected: collected,
      maxMultiplier: multiplierFor(tracker.chainLength),
    );
  }

  bool _bonusMet(
    BonusSpec b,
    LevelSpec level,
    ReactionTracker tracker,
    Iterable<LevelObject> objects,
    double timeSec,
    bool intendedStarter,
  ) {
    switch (b.type) {
      case 'collect_all':
        final Iterable<LevelObject> stars = objects.where(
          (LevelObject o) => o.spec.collectible == 'star',
        );
        return stars.isNotEmpty && stars.every((LevelObject o) => o.collected);
      case 'activate':
        final LevelObject? t = objects
            .where((LevelObject o) => o.id == b.target)
            .firstOrNull;
        return t?.activated ?? false;
      case 'break_all':
        final Iterable<LevelObject> breakables = objects.where(
          (LevelObject o) => o.spec.device?.type == 'breakable',
        );
        return breakables.isNotEmpty &&
            breakables.every((LevelObject o) => o.activated);
      case 'intended_starter':
        return intendedStarter;
      case 'no_stall':
        return !tracker.stalled;
      case 'under_time':
        return timeSec <= (b.value > 0 ? b.value : level.parTimeSec);
      case 'chain_at_least':
        return tracker.chainLength >= b.value.round();
      default:
        return false;
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
