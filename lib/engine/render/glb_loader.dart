import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'mesh.dart';

class GlbException implements Exception {
  GlbException(this.message);
  final String message;
  @override
  String toString() => 'GlbException: $message';
}

/// Minimal, allocation-conscious binary glTF reader.
///
/// The pipeline only ever exports what this game needs — static meshes,
/// flat-shaded, one solid `baseColorFactor` per material, no textures, no
/// skins, no animations — so the loader deliberately supports exactly that
/// and fails loudly on anything else rather than silently mis-rendering.
class GlbLoader {
  static const int _magic = 0x46546C67; // 'glTF'
  static const int _chunkJson = 0x4E4F534A; // 'JSON'
  static const int _chunkBin = 0x004E4942; // 'BIN\0'

  /// Parses [bytes] into a single merged [Mesh] named [name].
  ///
  /// Every primitive in every node of the default scene is baked into one
  /// buffer with its node transform applied. Merging at load time means an
  /// asset made of a dozen Blender objects still costs exactly one instance
  /// and one bounding box at runtime.
  static Mesh parse(Uint8List bytes, {required String name}) {
    final ByteData bd = ByteData.sublistView(bytes);
    if (bytes.length < 12) throw GlbException('$name: file too short');
    if (bd.getUint32(0, Endian.little) != _magic) {
      throw GlbException('$name: not a GLB (bad magic)');
    }
    final int version = bd.getUint32(4, Endian.little);
    if (version != 2) throw GlbException('$name: unsupported glTF version $version');

    Map<String, dynamic>? json;
    Uint8List? bin;

    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final int chunkLen = bd.getUint32(offset, Endian.little);
      final int chunkType = bd.getUint32(offset + 4, Endian.little);
      final int dataStart = offset + 8;
      if (dataStart + chunkLen > bytes.length) {
        throw GlbException('$name: truncated chunk');
      }
      if (chunkType == _chunkJson) {
        json = jsonDecode(utf8.decode(Uint8List.sublistView(bytes, dataStart, dataStart + chunkLen)))
            as Map<String, dynamic>;
      } else if (chunkType == _chunkBin) {
        bin = Uint8List.sublistView(bytes, dataStart, dataStart + chunkLen);
      }
      offset = dataStart + chunkLen;
      if (offset % 4 != 0) offset += 4 - (offset % 4);
    }

    if (json == null) throw GlbException('$name: missing JSON chunk');
    return _build(json, bin, name);
  }

  static Mesh _build(Map<String, dynamic> g, Uint8List? bin, String name) {
    final List<dynamic> accessors = (g['accessors'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> views = (g['bufferViews'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> meshes = (g['meshes'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> nodes = (g['nodes'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> materials = (g['materials'] as List<dynamic>?) ?? const <dynamic>[];

    // Material slots, in glTF order, converted to display-space ARGB.
    final Int32List matColors = Int32List(math.max(1, materials.length));
    if (materials.isEmpty) {
      matColors[0] = 0xFFCCCCCC;
    }
    for (int i = 0; i < materials.length; i++) {
      matColors[i] = _materialColor(materials[i] as Map<String, dynamic>);
    }

    final List<double> outPos = <double>[];
    final List<int> outIdx = <int>[];
    final List<int> outMat = <int>[];

    // Resolve the node hierarchy of the default scene.
    final int sceneIndex = (g['scene'] as int?) ?? 0;
    final List<dynamic> scenes = (g['scenes'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> roots = scenes.isEmpty
        ? List<dynamic>.generate(nodes.length, (int i) => i)
        : (((scenes[sceneIndex] as Map<String, dynamic>)['nodes'] as List<dynamic>?) ??
              const <dynamic>[]);

    void visit(int nodeIndex, Matrix4 parent) {
      if (nodeIndex < 0 || nodeIndex >= nodes.length) return;
      final Map<String, dynamic> node = nodes[nodeIndex] as Map<String, dynamic>;
      final Matrix4 local = _nodeMatrix(node);
      final Matrix4 world = parent.clone()..multiply(local);

      final int? meshIndex = node['mesh'] as int?;
      if (meshIndex != null && meshIndex < meshes.length) {
        final Map<String, dynamic> m = meshes[meshIndex] as Map<String, dynamic>;
        for (final dynamic primRaw in (m['primitives'] as List<dynamic>?) ?? const <dynamic>[]) {
          final Map<String, dynamic> prim = primRaw as Map<String, dynamic>;
          final int mode = (prim['mode'] as int?) ?? 4;
          if (mode != 4) continue; // triangles only
          _appendPrimitive(prim, accessors, views, bin, world, outPos, outIdx, outMat, name);
        }
      }

      for (final dynamic c in (node['children'] as List<dynamic>?) ?? const <dynamic>[]) {
        visit(c as int, world);
      }
    }

    final Matrix4 identity = Matrix4.identity();
    for (final dynamic r in roots) {
      visit(r as int, identity);
    }

    if (outIdx.isEmpty) throw GlbException('$name: no triangle geometry found');
    final int vertexCount = outPos.length ~/ 3;
    if (vertexCount > 65535) {
      throw GlbException('$name: $vertexCount vertices exceeds the 16-bit index budget');
    }

    return Mesh.build(
      name: name,
      positions: Float32List.fromList(outPos),
      indices: Uint16List.fromList(outIdx),
      faceMaterial: Uint16List.fromList(outMat),
      materials: matColors,
    );
  }

  static void _appendPrimitive(
    Map<String, dynamic> prim,
    List<dynamic> accessors,
    List<dynamic> views,
    Uint8List? bin,
    Matrix4 world,
    List<double> outPos,
    List<int> outIdx,
    List<int> outMat,
    String name,
  ) {
    final Map<String, dynamic> attrs = prim['attributes'] as Map<String, dynamic>;
    final int? posAcc = attrs['POSITION'] as int?;
    if (posAcc == null) return;

    final Float32List pos = _readFloats(posAcc, accessors, views, bin, 3, name);
    final int baseVertex = outPos.length ~/ 3;
    final int count = pos.length ~/ 3;

    final Float64List m = world.storage;
    for (int i = 0; i < count; i++) {
      final double x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
      outPos.add(m[0] * x + m[4] * y + m[8] * z + m[12]);
      outPos.add(m[1] * x + m[5] * y + m[9] * z + m[13]);
      outPos.add(m[2] * x + m[6] * y + m[10] * z + m[14]);
    }

    final int matSlot = (prim['material'] as int?) ?? 0;
    final int? idxAcc = prim['indices'] as int?;

    // A mirrored node transform flips triangle winding; undo it so back-face
    // culling in the renderer stays correct.
    final bool flip = world.determinant() < 0;

    if (idxAcc == null) {
      for (int i = 0; i + 2 < count; i += 3) {
        _pushTri(outIdx, baseVertex + i, baseVertex + i + 1, baseVertex + i + 2, flip);
        outMat.add(matSlot);
      }
    } else {
      final Uint32List idx = _readIndices(idxAcc, accessors, views, bin, name);
      for (int i = 0; i + 2 < idx.length; i += 3) {
        _pushTri(outIdx, baseVertex + idx[i], baseVertex + idx[i + 1], baseVertex + idx[i + 2], flip);
        outMat.add(matSlot);
      }
    }
  }

  static void _pushTri(List<int> out, int a, int b, int c, bool flip) {
    out.add(a);
    if (flip) {
      out.add(c);
      out.add(b);
    } else {
      out.add(b);
      out.add(c);
    }
  }

  static Matrix4 _nodeMatrix(Map<String, dynamic> node) {
    final List<dynamic>? mat = node['matrix'] as List<dynamic>?;
    if (mat != null && mat.length == 16) {
      final Matrix4 m = Matrix4.zero();
      for (int i = 0; i < 16; i++) {
        m.storage[i] = (mat[i] as num).toDouble();
      }
      return m;
    }
    final List<dynamic>? t = node['translation'] as List<dynamic>?;
    final List<dynamic>? r = node['rotation'] as List<dynamic>?;
    final List<dynamic>? s = node['scale'] as List<dynamic>?;

    final Matrix4 m = Matrix4.identity();
    if (t != null && t.length == 3) {
      m.setTranslation(
        Vector3((t[0] as num).toDouble(), (t[1] as num).toDouble(), (t[2] as num).toDouble()),
      );
    }
    if (r != null && r.length == 4) {
      // glTF stores quaternions xyzw.
      final Quaternion q = Quaternion(
        (r[0] as num).toDouble(),
        (r[1] as num).toDouble(),
        (r[2] as num).toDouble(),
        (r[3] as num).toDouble(),
      );
      m.setRotation(q.asRotationMatrix());
    }
    if (s != null && s.length == 3) {
      m.multiply(
        Matrix4.diagonal3(
          Vector3((s[0] as num).toDouble(), (s[1] as num).toDouble(), (s[2] as num).toDouble()),
        ),
      );
    }
    return m;
  }

  // ------------------------------------------------------------ accessors
  static const Map<int, int> _componentSize = <int, int>{
    5120: 1, // BYTE
    5121: 1, // UNSIGNED_BYTE
    5122: 2, // SHORT
    5123: 2, // UNSIGNED_SHORT
    5125: 4, // UNSIGNED_INT
    5126: 4, // FLOAT
  };

  static const Map<String, int> _typeComponents = <String, int>{
    'SCALAR': 1,
    'VEC2': 2,
    'VEC3': 3,
    'VEC4': 4,
    'MAT4': 16,
  };

  static Float32List _readFloats(
    int accessorIndex,
    List<dynamic> accessors,
    List<dynamic> views,
    Uint8List? bin,
    int expectedComponents,
    String name,
  ) {
    final Map<String, dynamic> acc = accessors[accessorIndex] as Map<String, dynamic>;
    if (acc['sparse'] != null) {
      throw GlbException('$name: sparse accessors are not supported by this pipeline');
    }
    final int compType = acc['componentType'] as int;
    if (compType != 5126) {
      throw GlbException('$name: expected FLOAT positions, got componentType $compType');
    }
    final String type = acc['type'] as String;
    final int comps = _typeComponents[type] ?? 0;
    if (comps != expectedComponents) {
      throw GlbException('$name: expected $expectedComponents components, got $type');
    }
    final int count = acc['count'] as int;
    final Float32List out = Float32List(count * comps);

    final int? viewIndex = acc['bufferView'] as int?;
    if (viewIndex == null) return out; // all zeroes, per spec

    final Map<String, dynamic> view = views[viewIndex] as Map<String, dynamic>;
    if (bin == null) throw GlbException('$name: geometry references a missing BIN chunk');

    final int viewOffset = (view['byteOffset'] as int?) ?? 0;
    final int accOffset = (acc['byteOffset'] as int?) ?? 0;
    final int stride = (view['byteStride'] as int?) ?? (comps * 4);
    final int start = viewOffset + accOffset;
    final ByteData bd = ByteData.sublistView(bin);

    for (int i = 0; i < count; i++) {
      final int base = start + i * stride;
      for (int c = 0; c < comps; c++) {
        out[i * comps + c] = bd.getFloat32(base + c * 4, Endian.little);
      }
    }
    return out;
  }

  static Uint32List _readIndices(
    int accessorIndex,
    List<dynamic> accessors,
    List<dynamic> views,
    Uint8List? bin,
    String name,
  ) {
    final Map<String, dynamic> acc = accessors[accessorIndex] as Map<String, dynamic>;
    final int compType = acc['componentType'] as int;
    final int size = _componentSize[compType] ?? 0;
    if (size == 0) throw GlbException('$name: bad index componentType $compType');

    final int count = acc['count'] as int;
    final Uint32List out = Uint32List(count);

    final int? viewIndex = acc['bufferView'] as int?;
    if (viewIndex == null) return out;
    if (bin == null) throw GlbException('$name: indices reference a missing BIN chunk');

    final Map<String, dynamic> view = views[viewIndex] as Map<String, dynamic>;
    final int start = ((view['byteOffset'] as int?) ?? 0) + ((acc['byteOffset'] as int?) ?? 0);
    final int stride = (view['byteStride'] as int?) ?? size;
    final ByteData bd = ByteData.sublistView(bin);

    for (int i = 0; i < count; i++) {
      final int at = start + i * stride;
      out[i] = switch (compType) {
        5121 => bd.getUint8(at),
        5123 => bd.getUint16(at, Endian.little),
        5125 => bd.getUint32(at, Endian.little),
        5122 => bd.getInt16(at, Endian.little),
        5120 => bd.getInt8(at),
        _ => 0,
      };
    }
    return out;
  }

  // ------------------------------------------------------------- material
  static int _materialColor(Map<String, dynamic> mat) {
    final Map<String, dynamic>? pbr = mat['pbrMetallicRoughness'] as Map<String, dynamic>?;
    final List<dynamic>? f = pbr?['baseColorFactor'] as List<dynamic>?;
    double r = 0.8, g = 0.8, b = 0.8, a = 1.0;
    if (f != null && f.length >= 3) {
      r = (f[0] as num).toDouble();
      g = (f[1] as num).toDouble();
      b = (f[2] as num).toDouble();
      if (f.length >= 4) a = (f[3] as num).toDouble();
    }
    // glTF baseColorFactor is linear; the renderer works in display space.
    return ((a * 255).round().clamp(0, 255) << 24) |
        (_linearToSrgb(r) << 16) |
        (_linearToSrgb(g) << 8) |
        _linearToSrgb(b);
  }

  static int _linearToSrgb(double c) {
    if (c <= 0) return 0;
    if (c >= 1) return 255;
    final double s = c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
    return (s * 255.0).round().clamp(0, 255);
  }
}
