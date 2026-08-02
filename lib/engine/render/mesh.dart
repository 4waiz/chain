import 'dart:math' as math;
import 'dart:typed_data';

/// A render-ready, flat-shaded, indexed triangle mesh.
///
/// The game's art direction is faceted low-poly with solid colours, so a mesh
/// only ever needs positions, per-*triangle* normals and a per-*triangle*
/// material slot. Storing normals per triangle rather than per vertex halves
/// the data and lets the renderer shade a whole face with one dot product.
///
/// All buffers are flat typed arrays; nothing here allocates per frame.
class Mesh {
  Mesh({
    required this.name,
    required this.positions,
    required this.indices,
    required this.faceNormals,
    required this.faceMaterial,
    required this.materials,
    required this.boundsMin,
    required this.boundsMax,
  });

  final String name;

  /// xyz per vertex.
  final Float32List positions;

  /// 3 vertex indices per triangle.
  final Uint16List indices;

  /// Normalised object-space xyz per triangle.
  final Float32List faceNormals;

  /// Index into [materials] per triangle.
  final Uint16List faceMaterial;

  /// Packed 0xAARRGGBB base colours.
  final Int32List materials;

  final Float32List boundsMin;
  final Float32List boundsMax;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
  int get materialCount => materials.length;

  double get radius {
    double maxSq = 0;
    for (int i = 0; i < positions.length; i += 3) {
      final double x = positions[i];
      final double y = positions[i + 1];
      final double z = positions[i + 2];
      final double d = x * x + y * y + z * z;
      if (d > maxSq) maxSq = d;
    }
    return math.sqrt(maxSq);
  }

  /// Size of the axis-aligned bounding box.
  double get sizeX => boundsMax[0] - boundsMin[0];
  double get sizeY => boundsMax[1] - boundsMin[1];
  double get sizeZ => boundsMax[2] - boundsMin[2];

  /// Derives face normals and bounds from raw geometry. Used by both the GLB
  /// loader and the procedural fallback builders.
  static Mesh build({
    required String name,
    required Float32List positions,
    required Uint16List indices,
    required Uint16List faceMaterial,
    required Int32List materials,
  }) {
    final int triCount = indices.length ~/ 3;
    final Float32List normals = Float32List(triCount * 3);

    for (int t = 0; t < triCount; t++) {
      final int ia = indices[t * 3] * 3;
      final int ib = indices[t * 3 + 1] * 3;
      final int ic = indices[t * 3 + 2] * 3;

      final double ax = positions[ia], ay = positions[ia + 1], az = positions[ia + 2];
      final double bx = positions[ib], by = positions[ib + 1], bz = positions[ib + 2];
      final double cx = positions[ic], cy = positions[ic + 1], cz = positions[ic + 2];

      final double e1x = bx - ax, e1y = by - ay, e1z = bz - az;
      final double e2x = cx - ax, e2y = cy - ay, e2z = cz - az;

      double nx = e1y * e2z - e1z * e2y;
      double ny = e1z * e2x - e1x * e2z;
      double nz = e1x * e2y - e1y * e2x;

      final double len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 1e-12) {
        nx /= len;
        ny /= len;
        nz /= len;
      } else {
        nx = 0;
        ny = 1;
        nz = 0;
      }
      normals[t * 3] = nx;
      normals[t * 3 + 1] = ny;
      normals[t * 3 + 2] = nz;
    }

    final Float32List lo = Float32List.fromList(<double>[1e30, 1e30, 1e30]);
    final Float32List hi = Float32List.fromList(<double>[-1e30, -1e30, -1e30]);
    for (int i = 0; i < positions.length; i += 3) {
      for (int a = 0; a < 3; a++) {
        final double v = positions[i + a];
        if (v < lo[a]) lo[a] = v;
        if (v > hi[a]) hi[a] = v;
      }
    }
    if (positions.isEmpty) {
      lo.setAll(0, <double>[0, 0, 0]);
      hi.setAll(0, <double>[0, 0, 0]);
    }

    return Mesh(
      name: name,
      positions: positions,
      indices: indices,
      faceNormals: normals,
      faceMaterial: faceMaterial,
      materials: materials,
      boundsMin: lo,
      boundsMax: hi,
    );
  }

  /// Returns a copy with every material slot remapped through [remap].
  /// Used by the cosmetics system to recolour a model without re-loading it.
  Mesh recoloured(Map<int, int> remap) {
    if (remap.isEmpty) return this;
    final Int32List next = Int32List.fromList(materials);
    remap.forEach((int slot, int argb) {
      if (slot >= 0 && slot < next.length) next[slot] = argb;
    });
    return Mesh(
      name: name,
      positions: positions,
      indices: indices,
      faceNormals: faceNormals,
      faceMaterial: faceMaterial,
      materials: next,
      boundsMin: boundsMin,
      boundsMax: boundsMax,
    );
  }
}
