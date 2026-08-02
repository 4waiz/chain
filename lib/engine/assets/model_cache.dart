import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../render/glb_loader.dart';
import '../render/mesh.dart';

/// Loads and caches GLB models from the asset bundle.
///
/// Meshes are immutable once parsed and are shared by every instance that
/// references them, so a level with forty dominoes still holds exactly one
/// domino mesh in memory. Nothing is ever evicted during a session — the whole
/// library is a couple of megabytes — but [dropAll] exists for tests.
class ModelCache {
  ModelCache._();
  static final ModelCache instance = ModelCache._();

  final Map<String, Mesh> _meshes = <String, Mesh>{};
  final Map<String, Future<Mesh>> _inFlight = <String, Future<Mesh>>{};
  final Set<String> _missing = <String>{};

  int get loadedCount => _meshes.length;
  Iterable<String> get loadedSlugs => _meshes.keys;

  /// Slugs that were requested but could not be loaded. The level validator
  /// surfaces these rather than letting a level render with holes in it.
  Set<String> get missing => Set<String>.unmodifiable(_missing);

  bool isLoaded(String slug) => _meshes.containsKey(slug);

  /// Returns an already-loaded mesh, or null. Safe to call every frame.
  Mesh? peek(String slug) => _meshes[slug];

  Future<Mesh> load(String slug) {
    final Mesh? existing = _meshes[slug];
    if (existing != null) return Future<Mesh>.value(existing);

    return _inFlight.putIfAbsent(slug, () async {
      try {
        final ByteData data = await rootBundle.load('assets/models/$slug.glb');
        final Mesh mesh = GlbLoader.parse(data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ), name: slug);
        _meshes[slug] = mesh;
        _missing.remove(slug);
        return mesh;
      } catch (_) {
        _missing.add(slug);
        rethrow;
      } finally {
        _inFlight.remove(slug);
      }
    });
  }

  /// Loads many models concurrently, tolerating individual failures so one bad
  /// asset cannot block a whole level from opening.
  Future<void> loadAll(Iterable<String> slugs) async {
    final List<Future<void>> futures = <Future<void>>[];
    for (final String s in slugs) {
      if (_meshes.containsKey(s)) continue;
      futures.add(load(s).then<void>((_) {}, onError: (Object _) {}));
    }
    await Future.wait(futures);
  }

  /// Registers a mesh built at runtime (particles, debris) under a slug so it
  /// can be referenced from level data like any imported model.
  void put(String slug, Mesh mesh) => _meshes[slug] = mesh;

  void dropAll() {
    _meshes.clear();
    _inFlight.clear();
    _missing.clear();
  }

  /// Total triangles held in cache — surfaced in the performance overlay.
  int get totalTriangles {
    int n = 0;
    for (final Mesh m in _meshes.values) {
      n += m.triangleCount;
    }
    return n;
  }
}
