import 'dart:convert';
import 'dart:io';

import 'package:chain_reaction_city/engine/assets/model_cache.dart';
import 'package:chain_reaction_city/engine/render/glb_loader.dart';
import 'package:chain_reaction_city/game/level/level_spec.dart';
import 'package:chain_reaction_city/game/level/level_validator.dart';
import 'package:chain_reaction_city/game/play/level_runtime.dart';
import 'package:chain_reaction_city/game/play/reaction_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads models straight off disk rather than through `rootBundle`, so these
/// tests run headlessly with no asset bundle and no widget binding.
Future<void> loadModelsFromDisk(Iterable<String> slugs) async {
  for (final String slug in slugs) {
    if (ModelCache.instance.isLoaded(slug)) continue;
    final File f = File('assets/models/$slug.glb');
    if (!f.existsSync()) continue;
    ModelCache.instance.put(
      slug,
      GlbLoader.parse(await f.readAsBytes(), name: slug),
    );
  }
}

LevelSpec loadLevel(String id) =>
    LevelSpec.parse(File('assets/levels/$id.json').readAsStringSync());

Set<String> allModelSlugs() {
  final Directory d = Directory('assets/models');
  if (!d.existsSync()) return <String>{};
  return d
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.glb'))
      .map((File f) => f.uri.pathSegments.last.replaceAll('.glb', ''))
      .toSet();
}

/// Plays a level headlessly at a fixed 60 Hz and reports what happened.
class PlayReport {
  PlayReport(this.runtime, this.frames);
  final LevelRuntime runtime;
  final int frames;

  bool get won => runtime.phase == RunPhase.won;
  double get seconds => runtime.runTime;

  String describe() {
    final StringBuffer b = StringBuffer();
    b.writeln(
      'phase=${runtime.phase.name} t=${seconds.toStringAsFixed(2)}s '
      'chain=${runtime.tracker.chainLength}',
    );
    for (final ReactionStageSpec s in runtime.spec.stages) {
      final StageRun? r = runtime.tracker.run(s.id);
      b.writeln(
        '  ${s.id.padRight(10)} ${r?.state.name}'
        '${r != null && r.firedAt >= 0 ? ' @${r.firedAt.toStringAsFixed(2)}s' : ''}',
      );
    }
    return b.toString();
  }
}

PlayReport playLevel(
  LevelSpec spec, {
  String? starter,
  double maxSeconds = 25,
}) {
  final LevelRuntime rt = LevelRuntime(spec);
  rt.build();
  rt.start(starter ?? spec.starters.first.id);

  const double dt = 1.0 / 60.0;
  final int limit = (maxSeconds / dt).round();
  int i = 0;
  while (i < limit && rt.phase == RunPhase.reacting) {
    rt.update(dt);
    i++;
  }
  return PlayReport(rt, i);
}

void main() {
  final Set<String> models = allModelSlugs();

  setUpAll(() async {
    await loadModelsFromDisk(models);
  });

  group('vertical slice — w1_l1', () {
    test('validates cleanly', () {
      final LevelSpec spec = loadLevel('w1_l1');
      final ValidationReport r = LevelValidator(
        knownModels: models,
      ).validate(spec);
      expect(r.ok, isTrue, reason: r.toString());
    });

    test('every referenced model exists on disk', () {
      final LevelSpec spec = loadLevel('w1_l1');
      for (final String slug in spec.requiredModels) {
        expect(models.contains(slug), isTrue, reason: 'missing model $slug');
      }
    });

    test('the full chain completes: cannon to flag', () {
      final LevelSpec spec = loadLevel('w1_l1');
      final PlayReport r = playLevel(spec);
      expect(r.won, isTrue, reason: r.describe());
      expect(r.runtime.result?.completed, isTrue);
      expect(
        r.runtime.tracker.chainLength,
        greaterThanOrEqualTo(8),
        reason: r.describe(),
      );
    });

    test('three stars are achievable in one clean run', () {
      final LevelSpec spec = loadLevel('w1_l1');
      final PlayReport r = playLevel(spec);
      expect(r.won, isTrue, reason: r.describe());
      final result = r.runtime.result!;
      expect(
        result.bonusesMet.length,
        spec.bonuses.length,
        reason:
            'unmet: ${spec.bonuses.map((BonusSpec b) => b.id).where((String id) => !result.bonusesMet.contains(id)).join(", ")}\n${r.describe()}',
      );
      expect(result.stars, 3);
    });

    test('the side branch fires: the tower collapses and frees the star', () {
      final LevelSpec spec = loadLevel('w1_l1');
      final PlayReport r = playLevel(spec);
      final tower = r.runtime.find('t2');
      final star = r.runtime.find('star1');
      expect(
        tower?.displacement,
        greaterThan(0.07),
        reason: 'tower never toppled\n${r.describe()}',
      );
      expect(star?.collected, isTrue, reason: 'star was not collected');
    });

    test('the reaction is repeatable across resets', () {
      final LevelSpec spec = loadLevel('w1_l1');
      final LevelRuntime rt = LevelRuntime(spec);
      rt.build();

      List<double> runOnce() {
        rt.reset();
        rt.start(spec.starters.first.id);
        for (int i = 0; i < 900 && rt.phase == RunPhase.reacting; i++) {
          rt.update(1 / 60);
        }
        final List<double> out = <double>[];
        for (final o in rt.objects) {
          final b = o.body;
          if (b == null) continue;
          out.addAll(<double>[b.position.x, b.position.y, b.position.z]);
        }
        return out;
      }

      final List<double> a = runOnce();
      final List<double> b = runOnce();
      final List<double> c = runOnce();

      expect(a.length, b.length);
      for (int i = 0; i < a.length; i++) {
        expect(b[i], equals(a[i]), reason: 'run 2 diverged at $i');
        expect(c[i], equals(a[i]), reason: 'run 3 diverged at $i');
      }
    });

    test('a fresh runtime reproduces the same result as a reset one', () {
      final LevelSpec spec = loadLevel('w1_l1');

      final PlayReport first = playLevel(spec);

      final LevelRuntime rt = LevelRuntime(spec);
      rt.build();
      rt.reset();
      rt.start(spec.starters.first.id);
      int i = 0;
      while (i < 1500 && rt.phase == RunPhase.reacting) {
        rt.update(1 / 60);
        i++;
      }

      expect(rt.phase, first.runtime.phase);
      expect(rt.runTime, closeTo(first.seconds, 1e-9));
      expect(rt.tracker.chainLength, first.runtime.tracker.chainLength);
    });
  });

  group('all shipped levels', () {
    test('every level file parses and validates', () {
      final Directory d = Directory('assets/levels');
      if (!d.existsSync()) return;
      final List<File> files =
          d
              .listSync()
              .whereType<File>()
              .where(
                (File f) =>
                    f.path.endsWith('.json') && !f.path.endsWith('index.json'),
              )
              .toList()
            ..sort((File a, File b) => a.path.compareTo(b.path));

      expect(files, isNotEmpty, reason: 'no level files found');

      final LevelValidator v = LevelValidator(knownModels: models);
      final List<String> failures = <String>[];
      for (final File f in files) {
        final LevelSpec spec = LevelSpec.fromJson(
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
        );
        final ValidationReport r = v.validate(spec);
        if (!r.ok) failures.add(r.toString());
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });
}
