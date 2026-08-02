import 'dart:math' as math;

import '../level/level_spec.dart';
import 'level_object.dart';

enum StageState { waiting, pending, fired, timedOut }

class StageRun {
  StageRun(this.spec);

  final ReactionStageSpec spec;
  StageState state = StageState.waiting;
  double pendingFor = 0.0;
  double firedAt = -1;

  void reset() {
    state = StageState.waiting;
    pendingFor = 0;
    firedAt = -1;
  }
}

/// Follows the authored reaction as the simulation plays it out.
///
/// This does not drive anything physical. It watches the objects a stage names
/// and decides when that beat has happened, which gives the game four things
/// it cannot get from raw physics: where the camera should look, how long the
/// chain is, whether the reaction has stalled, and whether the level is won.
class ReactionTracker {
  ReactionTracker(this.level)
    : _runs = <String, StageRun>{
        for (final ReactionStageSpec s in level.stages) s.id: StageRun(s),
      },
      _order = level.stages
          .map((ReactionStageSpec s) => s.id)
          .toList(growable: false);

  final LevelSpec level;
  final Map<String, StageRun> _runs;
  final List<String> _order;

  /// Stage ids in the order they actually fired.
  final List<String> firedOrder = <String>[];

  /// Distinct objects that took part, in first-touch order. This is the chain
  /// length the score and multiplier are built from.
  final List<String> chain = <String>[];
  final Set<String> _inChain = <String>{};

  bool goalReached = false;
  double goalAt = -1;
  bool stalled = false;

  /// Time since the most recent chain event. The fail check uses this rather
  /// than a global timer, so a long but healthy reaction is never cut off.
  double sinceLastEvent = 0.0;

  int get chainLength => chain.length;
  int get stagesFired => firedOrder.length;
  int get stageCount => _order.length;

  StageRun? run(String id) => _runs[id];

  /// The stage the camera should currently favour.
  StageRun? get activeStage {
    StageRun? best;
    for (final String id in _order) {
      final StageRun r = _runs[id]!;
      if (r.state == StageState.pending) {
        best = r;
        break;
      }
    }
    if (best != null) {
      return best;
    }
    for (int i = firedOrder.length - 1; i >= 0; i--) {
      final StageRun r = _runs[firedOrder[i]]!;
      if (r.spec.cameraFocus != null) {
        return r;
      }
    }
    return null;
  }

  void reset() {
    for (final StageRun r in _runs.values) {
      r.reset();
    }
    firedOrder.clear();
    chain.clear();
    _inChain.clear();
    goalReached = false;
    goalAt = -1;
    stalled = false;
    sinceLastEvent = 0;
  }

  void noteParticipation(String objectId) {
    if (_inChain.add(objectId)) {
      chain.add(objectId);
      sinceLastEvent = 0;
    }
  }

  /// Advances stage states. [lookup] resolves an object id to its runtime
  /// state; [impacts] holds ids that received a significant hit this tick.
  void update(
    double dt,
    double now,
    LevelObject? Function(String) lookup,
    Set<String> impacts,
  ) {
    sinceLastEvent += dt;

    for (final String id in _order) {
      final StageRun r = _runs[id]!;
      if (r.state == StageState.fired) {
        continue;
      }
      final bool depsMet = r.spec.after.every(
        (String d) => _runs[d]?.state == StageState.fired,
      );
      if (!depsMet) {
        continue;
      }
      if (r.state == StageState.waiting) {
        r.state = StageState.pending;
        r.pendingFor = 0;
      }

      if (_isSatisfied(r.spec, lookup, impacts)) {
        r.state = StageState.fired;
        r.firedAt = now;
        firedOrder.add(id);
        sinceLastEvent = 0;
        for (final String w in r.spec.watch) {
          noteParticipation(w);
        }
        if (r.spec.watch.contains(level.goalObject) && !goalReached) {
          goalReached = true;
          goalAt = now;
        }
      } else {
        r.pendingFor += dt;
        if (r.pendingFor > r.spec.timeoutSec) {
          r.state = StageState.timedOut;
        }
      }
    }

    // The goal object may also be reached without a stage naming it first.
    final LevelObject? goal = lookup(level.goalObject);
    if (!goalReached && goal != null && goal.activated) {
      goalReached = true;
      goalAt = now;
      noteParticipation(goal.id);
    }

    if (!goalReached) {
      final bool anyPending = _runs.values.any(
        (StageRun r) => r.state == StageState.pending,
      );
      final bool allTimedOut = _runs.values.every(
        (StageRun r) => r.state != StageState.pending,
      );
      if (allTimedOut && !anyPending) {
        stalled = true;
      }
    }
  }

  bool _isSatisfied(
    ReactionStageSpec s,
    LevelObject? Function(String) lookup,
    Set<String> impacts,
  ) {
    for (final String id in s.watch) {
      final LevelObject? o = lookup(id);
      if (o == null) {
        continue;
      }
      final bool hit = switch (s.trigger) {
        'impact' =>
          impacts.contains(id) &&
              (o.body?.lastImpactImpulse ?? 0) >= math.max(0.001, s.threshold),
        'activated' => o.activated,
        'destroyed' => o.activated,
        'fell' => o.tiltDegrees >= (s.threshold <= 0 ? 45.0 : s.threshold),
        'entered' => o.collected || o.activated,
        _ => o.displacement >= (s.threshold <= 0 ? 0.06 : s.threshold),
      };
      if (hit) {
        return true;
      }
    }
    return false;
  }

  /// The stage that was still pending when everything stopped — this is what
  /// the failure screen points at to show the player where it broke down.
  StageRun? get breakdownStage {
    for (final String id in _order) {
      final StageRun r = _runs[id]!;
      if (r.state == StageState.pending || r.state == StageState.timedOut) {
        return r;
      }
    }
    return null;
  }
}
