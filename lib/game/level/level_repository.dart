import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../engine/assets/model_cache.dart';
import 'level_spec.dart';

/// Metadata about the campaign, read once at startup from the level index.
class WorldInfo {
  const WorldInfo(this.id, this.name, this.subtitle, this.levelIds);
  final int id;
  final String name;
  final String subtitle;
  final List<String> levelIds;
}

/// Loads level JSON from the asset bundle and caches parsed specs.
class LevelRepository {
  LevelRepository._();
  static final LevelRepository instance = LevelRepository._();

  final Map<String, LevelSpec> _cache = <String, LevelSpec>{};
  List<WorldInfo> _worlds = const <WorldInfo>[];
  bool _indexed = false;

  List<WorldInfo> get worlds => _worlds;

  /// All campaign level ids in play order.
  List<String> get orderedIds => <String>[
    for (final WorldInfo w in _worlds) ...w.levelIds,
  ];

  int get levelCount => orderedIds.length;

  static const List<(int, String, String)> _worldMeta = <(int, String, String)>[
    (1, 'Toy Street', 'Cannons, dominoes and little cars'),
    (2, 'Playroom Factory', 'Conveyors, gears and grabby magnets'),
    (3, 'Mini Harbour', 'Boats, bridges and water wheels'),
    (4, 'Carnival Table', 'Balloons, springs and big bells'),
    (5, 'Builder City', 'Cranes, trucks and total demolition'),
  ];

  Future<void> loadIndex() async {
    if (_indexed) return;
    final String raw = await rootBundle.loadString('assets/levels/index.json');
    final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
    final Map<String, dynamic> byWorld = j['worlds'] as Map<String, dynamic>;

    _worlds = <WorldInfo>[
      for (final (int id, String name, String sub) in _worldMeta)
        WorldInfo(
          id,
          name,
          sub,
          ((byWorld['$id'] as List<dynamic>?) ?? const <dynamic>[])
              .map((dynamic e) => e.toString())
              .toList(growable: false),
        ),
    ];
    _indexed = true;
  }

  Future<LevelSpec> load(String id) async {
    final LevelSpec? hit = _cache[id];
    if (hit != null) return hit;
    final String raw = await rootBundle.loadString('assets/levels/$id.json');
    final LevelSpec spec = LevelSpec.parse(raw);
    _cache[id] = spec;
    return spec;
  }

  /// Celebration pieces are shared by every level and every mode.
  static const List<String> _sharedModels = <String>[
    'confetti',
    'capsule_yellow',
    'capsule_green',
    'capsule_blue',
    'capsule_red',
    'capsule_orange',
    'capsule_purple',
    'capsule_duo',
    'star',
    'coin',
  ];

  /// Loads a level and every model it needs, ready to build.
  Future<LevelSpec> prepare(String id) async => prepareSpec(await load(id));

  /// Loads the models for an already-parsed spec. Used by the procedurally
  /// generated Daily Challenge and Reaction Lab levels.
  Future<LevelSpec> prepareSpec(LevelSpec spec) async {
    await ModelCache.instance.loadAll(spec.requiredModels);
    await ModelCache.instance.loadAll(_sharedModels);
    return spec;
  }

  String? nextLevelId(String id) {
    final List<String> all = orderedIds;
    final int i = all.indexOf(id);
    if (i < 0 || i + 1 >= all.length) return null;
    return all[i + 1];
  }

  int worldOf(String id) {
    for (final WorldInfo w in _worlds) {
      if (w.levelIds.contains(id)) return w.id;
    }
    return 1;
  }

  /// 1-based index of a level within its world.
  int indexInWorld(String id) {
    for (final WorldInfo w in _worlds) {
      final int i = w.levelIds.indexOf(id);
      if (i >= 0) return i + 1;
    }
    return 1;
  }
}
