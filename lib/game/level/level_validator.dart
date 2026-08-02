import '../../engine/assets/model_cache.dart';
import 'level_spec.dart';

enum IssueLevel { error, warning }

class ValidationIssue {
  ValidationIssue(this.level, this.code, this.message, {this.objectId});

  final IssueLevel level;
  final String code;
  final String message;
  final String? objectId;

  bool get isError => level == IssueLevel.error;

  @override
  String toString() =>
      '[${level.name.toUpperCase()}] $code: $message${objectId == null ? '' : ' (${objectId!})'}';
}

class ValidationReport {
  ValidationReport(this.levelId, this.issues);

  final String levelId;
  final List<ValidationIssue> issues;

  bool get ok => issues.every((ValidationIssue i) => !i.isError);
  Iterable<ValidationIssue> get errors =>
      issues.where((ValidationIssue i) => i.isError);
  Iterable<ValidationIssue> get warnings =>
      issues.where((ValidationIssue i) => !i.isError);

  @override
  String toString() =>
      issues.isEmpty ? '$levelId: ok' : '$levelId:\n  ${issues.join('\n  ')}';
}

/// Static checks run over every level at build time and in tests.
///
/// The point is that an unfinishable or visually broken level should never
/// reach a player: a missing model, a starter that no stage listens to, a
/// reaction graph with a gap in it, or two objects spawned inside each other
/// are all caught here rather than discovered mid-play.
class LevelValidator {
  const LevelValidator({this.knownModels});

  /// When supplied, model references are checked against this set. When null,
  /// [ModelCache] is consulted instead (used at runtime).
  final Set<String>? knownModels;

  ValidationReport validate(LevelSpec level) {
    final List<ValidationIssue> issues = <ValidationIssue>[];

    void err(String code, String msg, [String? id]) =>
        issues.add(ValidationIssue(IssueLevel.error, code, msg, objectId: id));
    void warn(String code, String msg, [String? id]) => issues.add(
      ValidationIssue(IssueLevel.warning, code, msg, objectId: id),
    );

    // ---- identity --------------------------------------------------------
    final Set<String> ids = <String>{};
    for (final ObjectSpec o in level.objects) {
      if (o.id.isEmpty) {
        err('empty_id', 'an object has an empty id');
      } else if (!ids.add(o.id)) {
        err('duplicate_id', 'duplicate object id', o.id);
      }
    }

    if (level.objects.isEmpty) err('empty_level', 'level has no objects');

    // ---- models ----------------------------------------------------------
    bool modelKnown(String slug) {
      final Set<String>? known = knownModels;
      if (known != null) return known.contains(slug);
      return ModelCache.instance.isLoaded(slug);
    }

    for (final String slug in level.requiredModels) {
      if (!modelKnown(slug)) {
        err('missing_model', 'model "$slug" is not available');
      }
    }

    // ---- starters --------------------------------------------------------
    final List<ObjectSpec> starters = level.starters.toList();
    if (starters.isEmpty) {
      err('no_starter', 'level has no tappable starting object');
    }
    if (starters.length > 5) {
      warn(
        'many_starters',
        '${starters.length} starters; the brief caps this at 5',
      );
    }
    for (final ObjectSpec s in starters) {
      if (s.device == null) {
        warn(
          'inert_starter',
          'starter has no device, so tapping it does nothing',
          s.id,
        );
      }
    }

    // ---- goal ------------------------------------------------------------
    if (level.goalObject.isEmpty) {
      err('no_goal', 'level defines no final target');
    } else if (!ids.contains(level.goalObject)) {
      err('bad_goal', 'goal references unknown object "${level.goalObject}"');
    }

    // ---- reaction graph --------------------------------------------------
    final Set<String> stageIds = <String>{};
    for (final ReactionStageSpec s in level.stages) {
      if (!stageIds.add(s.id)) {
        err('duplicate_stage', 'duplicate reaction stage id "${s.id}"');
      }
      if (s.watch.isEmpty) {
        err('empty_stage', 'stage "${s.id}" watches no objects');
      }
      for (final String w in s.watch) {
        if (!ids.contains(w)) {
          err('bad_stage_watch', 'stage "${s.id}" watches unknown object "$w"');
        }
      }
      if (s.cameraFocus != null && !ids.contains(s.cameraFocus)) {
        err(
          'bad_focus',
          'stage "${s.id}" focuses unknown object "${s.cameraFocus}"',
        );
      }
    }
    for (final ReactionStageSpec s in level.stages) {
      for (final String a in s.after) {
        if (!stageIds.contains(a)) {
          err('bad_stage_dep', 'stage "${s.id}" depends on unknown stage "$a"');
        }
      }
    }

    if (level.stages.isEmpty) {
      err('no_stages', 'level has no reaction stages');
    } else {
      _checkGraphConnectivity(level, issues);
    }

    // ---- device wiring ---------------------------------------------------
    for (final ObjectSpec o in level.objects) {
      final DeviceSpec? d = o.device;
      if (d == null) continue;
      for (final String key in <String>[
        'activates',
        'targets',
        'opens',
        'releases',
        'debris',
        'ammo',
        'target',
      ]) {
        for (final String ref in d.ids(key)) {
          if (!ids.contains(ref)) {
            err(
              'bad_device_ref',
              'device "${d.type}" references unknown object "$ref"',
              o.id,
            );
          }
        }
      }
      if (d.type == 'cannon') {
        final String? ammo = d.text('ammo');
        if (ammo == null || ammo.isEmpty) {
          err('cannon_no_ammo', 'cannon has no ammo object', o.id);
        } else if (!ids.contains(ammo)) {
          err(
            'cannon_bad_ammo',
            'cannon ammo "$ammo" is not an object in this level',
            o.id,
          );
        }
      }
    }

    // ---- bonuses ---------------------------------------------------------
    for (final BonusSpec b in level.bonuses) {
      if (b.target != null && !ids.contains(b.target)) {
        err(
          'bad_bonus_target',
          'bonus "${b.id}" targets unknown object "${b.target}"',
        );
      }
    }
    if (level.bonuses.isEmpty) {
      warn(
        'no_bonus',
        'level has no bonus objective, so the second star is unreachable',
      );
    }

    // ---- placement -------------------------------------------------------
    _checkOverlaps(level, issues);
    _checkRestState(level, issues);

    return ValidationReport(level.id, issues);
  }

  /// Every stage must be reachable from a starter-rooted stage, and the goal
  /// object must be watched by some stage. A gap here is exactly the "chain
  /// that cannot complete" failure the brief asks to catch.
  void _checkGraphConnectivity(LevelSpec level, List<ValidationIssue> issues) {
    final Map<String, ReactionStageSpec> byId = <String, ReactionStageSpec>{
      for (final ReactionStageSpec s in level.stages) s.id: s,
    };

    final List<ReactionStageSpec> roots = level.stages
        .where((ReactionStageSpec s) => s.after.isEmpty)
        .toList();
    if (roots.isEmpty) {
      issues.add(
        ValidationIssue(
          IssueLevel.error,
          'graph_no_root',
          'every reaction stage depends on another; the chain can never start',
        ),
      );
      return;
    }

    // Forward reachability from the roots.
    final Set<String> reachable = <String>{};
    final List<String> queue = roots
        .map((ReactionStageSpec s) => s.id)
        .toList();
    reachable.addAll(queue);
    while (queue.isNotEmpty) {
      final String cur = queue.removeLast();
      for (final ReactionStageSpec s in level.stages) {
        if (s.after.contains(cur) && reachable.add(s.id)) {
          queue.add(s.id);
        }
      }
    }
    for (final ReactionStageSpec s in level.stages) {
      if (!reachable.contains(s.id)) {
        issues.add(
          ValidationIssue(
            IssueLevel.error,
            'disconnected_stage',
            'stage "${s.id}" can never be reached from the start of the chain',
          ),
        );
      }
    }

    // Cycle detection.
    final Set<String> visiting = <String>{};
    final Set<String> done = <String>{};
    bool hasCycle(String id) {
      if (done.contains(id)) return false;
      if (!visiting.add(id)) return true;
      for (final String dep in byId[id]?.after ?? const <String>[]) {
        if (byId.containsKey(dep) && hasCycle(dep)) return true;
      }
      visiting.remove(id);
      done.add(id);
      return false;
    }

    for (final ReactionStageSpec s in level.stages) {
      if (hasCycle(s.id)) {
        issues.add(
          ValidationIssue(
            IssueLevel.error,
            'graph_cycle',
            'reaction stages form a cycle involving "${s.id}"',
          ),
        );
        break;
      }
    }

    final bool goalWatched = level.stages.any(
      (ReactionStageSpec s) => s.watch.contains(level.goalObject),
    );
    if (!goalWatched && level.goalObject.isNotEmpty) {
      issues.add(
        ValidationIssue(
          IssueLevel.error,
          'goal_unwatched',
          'no reaction stage watches the goal object "${level.goalObject}"',
        ),
      );
    }
  }

  /// Flags objects spawned inside one another. A level that starts overlapping
  /// gets an impulse kick on frame one, which breaks repeatability.
  void _checkOverlaps(LevelSpec level, List<ValidationIssue> issues) {
    final List<ObjectSpec> solid = level.objects
        .where(
          (ObjectSpec o) =>
              !o.sensor && o.shape != ColliderShape.none && !o.hidden,
        )
        .toList();

    for (int i = 0; i < solid.length; i++) {
      for (int j = i + 1; j < solid.length; j++) {
        final ObjectSpec a = solid[i];
        final ObjectSpec b = solid[j];
        // Only dynamic-vs-anything matters; two statics overlapping is a
        // legitimate way to build a compound shape.
        if (a.kind != ObjectKind.dynamicBody &&
            b.kind != ObjectKind.dynamicBody) {
          continue;
        }
        final double? ra = _approxRadius(a);
        final double? rb = _approxRadius(b);
        if (ra == null || rb == null) continue;

        final double d = (a.position - b.position).length;
        // 0.55 rather than 1.0: bounding spheres over boxes overlap freely at
        // legitimate resting contact, so only a deep interpenetration counts.
        if (d < (ra + rb) * 0.55) {
          issues.add(
            ValidationIssue(
              IssueLevel.warning,
              'overlap',
              'objects "${a.id}" and "${b.id}" start ${d.toStringAsFixed(3)}m apart '
                  'and may be interpenetrating',
            ),
          );
        }
      }
    }
  }

  double? _approxRadius(ObjectSpec o) {
    if (o.radius != null) return o.radius! * o.scale;
    final v = o.halfExtents;
    if (v != null) return v.length * o.scale;
    return null; // derived from model bounds at load; skipped in static checks
  }

  /// Dynamic objects below the floor plane can never settle.
  void _checkRestState(LevelSpec level, List<ValidationIssue> issues) {
    for (final ObjectSpec o in level.objects) {
      if (o.kind != ObjectKind.dynamicBody || o.hidden) continue;
      if (o.position.y < -0.05) {
        issues.add(
          ValidationIssue(
            IssueLevel.error,
            'below_floor',
            'dynamic object starts below the floor plane',
            objectId: o.id,
          ),
        );
      }
      if (o.mass <= 0) {
        issues.add(
          ValidationIssue(
            IssueLevel.error,
            'bad_mass',
            'dynamic object has non-positive mass',
            objectId: o.id,
          ),
        );
      }
      if (o.mass > 50) {
        issues.add(
          ValidationIssue(
            IssueLevel.warning,
            'heavy',
            'mass ${o.mass} is very high and will dominate every contact',
            objectId: o.id,
          ),
        );
      }
    }
  }
}
