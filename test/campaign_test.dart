import 'dart:convert';
import 'dart:io';

import 'package:chain_reaction_city/game/level/level_spec.dart';
import 'package:chain_reaction_city/game/level/level_validator.dart';
import 'package:chain_reaction_city/game/level/procedural.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_play_test.dart'
    show allModelSlugs, loadModelsFromDisk, playLevel, PlayReport;

/// Campaign-wide guarantees.
///
/// Every shipped level must be completable by tapping its intended starter,
/// must validate, and must reach its goal within a sane time. A level that
/// fails here is unshippable — the player would be stuck with no way through.
void main() {
  final Set<String> models = allModelSlugs();

  List<({String id, LevelSpec spec})> loadAll() {
    final Directory d = Directory('assets/levels');
    if (!d.existsSync()) {
      return const <({String id, LevelSpec spec})>[];
    }
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
    return files.map((File f) {
      final LevelSpec s = LevelSpec.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      );
      return (id: s.id, spec: s);
    }).toList();
  }

  setUpAll(() async => loadModelsFromDisk(models));

  test('the campaign ships the full 5 worlds x 10 levels', () {
    final Map<String, dynamic> index =
        jsonDecode(File('assets/levels/index.json').readAsStringSync())
            as Map<String, dynamic>;
    final Map<String, dynamic> worlds = index['worlds'] as Map<String, dynamic>;

    expect(worlds.keys.length, 5, reason: 'expected 5 worlds');
    for (int w = 1; w <= 5; w++) {
      expect(
        (worlds['$w'] as List<dynamic>).length,
        10,
        reason: 'world $w should have 10 levels',
      );
    }
    expect(index['count'], 50);
  });

  test('every level validates with no errors', () {
    final LevelValidator v = LevelValidator(knownModels: models);
    final List<String> failures = <String>[];
    for (final ({String id, LevelSpec spec}) e in loadAll()) {
      final ValidationReport r = v.validate(e.spec);
      if (!r.ok) {
        failures.add(r.toString());
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('every level is completable from its intended starter', () {
    final List<String> failures = <String>[];
    for (final ({String id, LevelSpec spec}) e in loadAll()) {
      final PlayReport r = playLevel(e.spec, maxSeconds: 30);
      if (!r.won) {
        failures.add('${e.id}\n${r.describe()}');
      }
    }
    expect(
      failures,
      isEmpty,
      reason:
          '${failures.length} level(s) cannot be finished:\n'
          '${failures.join("\n")}',
    );
  });

  test('every level is deterministic across two independent runs', () {
    final List<String> failures = <String>[];
    for (final ({String id, LevelSpec spec}) e in loadAll()) {
      final PlayReport a = playLevel(e.spec, maxSeconds: 30);
      final PlayReport b = playLevel(e.spec, maxSeconds: 30);
      if (a.runtime.runTime != b.runtime.runTime ||
          a.runtime.tracker.chainLength != b.runtime.tracker.chainLength) {
        failures.add(e.id);
      }
    }
    expect(
      failures,
      isEmpty,
      reason: 'non-deterministic: ${failures.join(", ")}',
    );
  });

  test('no level finishes suspiciously fast or drags on', () {
    final List<String> notes = <String>[];
    for (final ({String id, LevelSpec spec}) e in loadAll()) {
      final PlayReport r = playLevel(e.spec, maxSeconds: 30);
      if (!r.won) {
        continue;
      }
      if (r.seconds < 0.8) {
        notes.add('${e.id} finished in ${r.seconds}s (too instant)');
      }
      if (r.seconds > 25) {
        notes.add('${e.id} took ${r.seconds}s (too slow)');
      }
    }
    expect(notes, isEmpty, reason: notes.join('\n'));
  });

  group('procedural modes', () {
    test('daily challenges are completable and stable for a given date', () {
      for (int day = 1; day <= 12; day++) {
        final DateTime d = DateTime(2026, 8, day);
        final LevelSpec a = ProceduralLevels.daily(d);
        final LevelSpec b = ProceduralLevels.daily(d);
        expect(
          a.objects.length,
          b.objects.length,
          reason: 'daily for $d is not stable',
        );

        final ValidationReport r = LevelValidator(
          knownModels: models,
        ).validate(a);
        expect(r.ok, isTrue, reason: '${a.id}: $r');

        final PlayReport p = playLevel(a, maxSeconds: 40);
        expect(p.won, isTrue, reason: 'daily $d unfinishable\n${p.describe()}');
      }
    });

    test('different dates give different puzzles', () {
      final LevelSpec a = ProceduralLevels.daily(DateTime(2026, 8, 3));
      final LevelSpec b = ProceduralLevels.daily(DateTime(2026, 8, 4));
      expect(a.id, isNot(b.id));
    });

    test('reaction lab runs are completable at every unlocked length', () {
      for (int run = 0; run < 5; run++) {
        final LevelSpec spec = ProceduralLevels.lab(0x5EED ^ (run * 7919), run);
        final ValidationReport r = LevelValidator(
          knownModels: models,
        ).validate(spec);
        expect(r.ok, isTrue, reason: 'lab run $run: $r');

        final PlayReport p = playLevel(spec, maxSeconds: 45);
        expect(
          p.won,
          isTrue,
          reason: 'lab run $run unfinishable\n${p.describe()}',
        );
      }
    });
  });
}
