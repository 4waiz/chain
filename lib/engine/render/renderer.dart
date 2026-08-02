import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart';

import 'camera.dart';
import 'lighting.dart';
import 'mesh.dart';
import 'palette.dart';
import 'render_instance.dart';

/// Quality tiers. Lower tiers shed shadow quality and triangle budget first,
/// because on a white studio background those cost the most and are noticed
/// the least.
enum RenderQuality { low, medium, high }

class RenderStats {
  int trianglesSubmitted = 0;
  int trianglesDrawn = 0;
  int instancesDrawn = 0;
  int shadowsDrawn = 0;
  double lastFrameMs = 0;

  void reset() {
    trianglesSubmitted = 0;
    trianglesDrawn = 0;
    instancesDrawn = 0;
    shadowsDrawn = 0;
  }
}

/// A flat-shaded, depth-sorted software transform + GPU raster renderer.
///
/// Geometry is transformed and lit on the CPU into one big vertex buffer and
/// handed to the GPU as a *single* `drawVertices` call per frame. That is the
/// whole trick: the art direction is untextured faceted low-poly, so a face
/// only needs one colour, and one colour per face means the entire scene can
/// live in one batch no matter how many distinct objects it contains.
class Renderer {
  Renderer({this.quality = RenderQuality.high, StudioLight? light})
    : light = light ?? const StudioLight();

  RenderQuality quality;
  StudioLight light;

  final RenderStats stats = RenderStats();

  /// Vertex scratch: screen x, screen y, clip w — 3 floats per vertex.
  Float32List _vtx = Float32List(0);

  /// Per-triangle gather buffers, filled before the depth sort.
  Uint32List _triA = Uint32List(0);
  Uint32List _triB = Uint32List(0);
  Uint32List _triC = Uint32List(0);
  Int32List _triColor = Int32List(0);
  Float32List _triDepth = Float32List(0);
  int _triCount = 0;

  /// Sort working set.
  Uint32List _order = Uint32List(0);
  final Uint32List _bucketCount = Uint32List(_kBuckets + 1);

  /// Screen-space triangle positions in gather order.
  Float32List _outXY = Float32List(0);

  /// The same positions reordered back-to-front, plus matching colours. These
  /// two are what actually get handed to `drawVertices`.
  Float32List _sortedXY = Float32List(0);
  Int32List _outCol = Int32List(0);

  static const int _kBuckets = 2048;

  final Matrix4 _mvp = Matrix4.identity();
  final Paint _vertexPaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..isAntiAlias = false;
  final Paint _shadowPaint = Paint()..isAntiAlias = true;

  // Reusable shadow scratch so the shadow pass never allocates.
  final Float64List _shadowPts = Float64List(16);
  final Float64List _hull = Float64List(16);

  double get _shadowStrength => switch (quality) {
    RenderQuality.low => 0.0,
    RenderQuality.medium => 0.16,
    RenderQuality.high => 0.20,
  };

  bool get _shapedShadows => quality == RenderQuality.high;

  void _ensureVertexCapacity(int vertexCount) {
    if (_vtx.length < vertexCount * 3) {
      _vtx = Float32List(_grow(vertexCount * 3));
    }
  }

  void _ensureTriCapacity(int triCount) {
    if (_triA.length >= triCount) return;
    final int n = _grow(triCount);
    // Gather buffers hold no state between frames, so a plain realloc is safe;
    // _outXY does carry the current frame's already-emitted triangles.
    final Float32List prevXY = _outXY;
    final int keep = _triCount * 6;
    _triA = Uint32List(n);
    _triB = Uint32List(n);
    _triC = Uint32List(n);
    _triColor = Int32List(n);
    _triDepth = Float32List(n);
    _order = Uint32List(n);
    _outXY = Float32List(n * 6);
    _sortedXY = Float32List(n * 6);
    _outCol = Int32List(n * 3);
    if (keep > 0 && keep <= prevXY.length) {
      _outXY.setRange(0, keep, prevXY);
    }
  }

  static int _grow(int need) {
    int n = 1024;
    while (n < need) {
      n <<= 1;
    }
    return n;
  }

  /// Paints the studio backdrop. A barely-there radial lift in the upper
  /// centre reads as a soft-box cyclorama rather than a flat fill.
  void drawBackdrop(ui.Canvas canvas, ui.Size size) {
    final Rect r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.5, size.height * 0.34),
          size.longestSide * 0.85,
          <Color>[Toy.studioLift, Toy.studio, Toy.studioDeep],
          <double>[0.0, 0.55, 1.0],
        ),
    );
  }

  /// Renders one frame. [camera] must already have had `update(aspect)` called.
  void render(
    ui.Canvas canvas,
    ui.Size size,
    OrbitCamera camera,
    List<RenderInstance> instances, {
    double groundY = 0.0,
  }) {
    final Stopwatch sw = Stopwatch()..start();
    stats.reset();

    final double w = size.width;
    final double h = size.height;
    if (w <= 0 || h <= 0) return;

    if (_shadowStrength > 0) {
      _drawShadowPass(canvas, size, camera, instances, groundY);
    }

    _triCount = 0;
    for (final RenderInstance inst in instances) {
      if (!inst.visible || inst.opacity <= 0.01) continue;
      _gatherInstance(inst, camera, w, h);
      stats.instancesDrawn++;
    }

    if (_triCount == 0) {
      stats.lastFrameMs = sw.elapsedMicroseconds / 1000.0;
      return;
    }

    _sortAndEmit();

    final ui.Vertices verts = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_sortedXY, 0, _triCount * 6),
      colors: Int32List.sublistView(_outCol, 0, _triCount * 3),
    );
    // `modulate` multiplies the (white) paint colour with each vertex colour,
    // which passes the vertex colours through untouched regardless of which
    // side of the blend the backend treats as source.
    canvas.drawVertices(verts, ui.BlendMode.modulate, _vertexPaint);
    verts.dispose();

    stats.trianglesDrawn = _triCount;
    stats.lastFrameMs = sw.elapsedMicroseconds / 1000.0;
  }

  // ------------------------------------------------------------ geometry
  void _gatherInstance(RenderInstance inst, OrbitCamera camera, double w, double h) {
    final Mesh mesh = inst.mesh;
    final int vCount = mesh.vertexCount;
    final int tCount = mesh.triangleCount;
    stats.trianglesSubmitted += tCount;

    _ensureVertexCapacity(vCount);
    _ensureTriCapacity(_triCount + tCount);

    _mvp
      ..setFrom(camera.viewProj)
      ..multiply(inst.transform);

    final Float64List m = _mvp.storage;
    final double m0 = m[0], m1 = m[1], m3 = m[3];
    final double m4 = m[4], m5 = m[5], m7 = m[7];
    final double m8 = m[8], m9 = m[9], m11 = m[11];
    final double m12 = m[12], m13 = m[13], m15 = m[15];

    final Float32List pos = mesh.positions;
    final Float32List vtx = _vtx;

    final double halfW = w * 0.5;
    final double halfH = h * 0.5;
    const double nearW = 0.02;

    // Project every vertex once.
    for (int i = 0, o = 0; i < vCount; i++, o += 3) {
      final int p = i * 3;
      final double x = pos[p], y = pos[p + 1], z = pos[p + 2];
      final double cw = m3 * x + m7 * y + m11 * z + m15;
      if (cw < nearW) {
        vtx[o + 2] = -1.0; // flagged: behind the near plane
        continue;
      }
      final double cx = m0 * x + m4 * y + m8 * z + m12;
      final double cy = m1 * x + m5 * y + m9 * z + m13;
      final double inv = 1.0 / cw;
      vtx[o] = halfW + cx * inv * halfW;
      vtx[o + 1] = halfH - cy * inv * halfH;
      vtx[o + 2] = cw;
    }

    // Light directions are rotated *into object space* once per instance, so
    // shading a face costs two dot products and no per-face matrix work.
    final Float64List mm = inst.transform.storage;
    final List<double> kd = StudioLight.normalise(light.keyDir);
    final List<double> fd = StudioLight.normalise(light.fillDir);
    final List<double> kl = _invRotate(mm, kd[0], kd[1], kd[2]);
    final List<double> fl = _invRotate(mm, fd[0], fd[1], fd[2]);
    final List<double> up = _invRotate(mm, 0.0, 1.0, 0.0);

    final double ambient = light.ambient;
    final double keyI = light.keyIntensity;
    final double fillI = light.fillIntensity;
    final double hemiI = light.hemiIntensity;
    final double lift = light.highlightLift;

    final double hl = inst.highlight.clamp(0.0, 1.0);
    final int alpha = (inst.opacity.clamp(0.0, 1.0) * 255.0).round();
    final double tintAmt = inst.tintAmount.clamp(0.0, 1.0);
    final int tint = inst.tint;
    final int tr = (tint >> 16) & 0xff, tg = (tint >> 8) & 0xff, tb = tint & 0xff;

    final Uint16List idx = mesh.indices;
    final Float32List fn = mesh.faceNormals;
    final Uint16List fmat = mesh.faceMaterial;
    final Int32List mats = mesh.materials;

    final double bias = inst.sortBias;

    int tc = _triCount;
    for (int t = 0; t < tCount; t++) {
      final int i0 = idx[t * 3], i1 = idx[t * 3 + 1], i2 = idx[t * 3 + 2];
      final int a = i0 * 3, b = i1 * 3, c = i2 * 3;

      final double wa = vtx[a + 2];
      if (wa < 0) continue;
      final double wb = vtx[b + 2];
      if (wb < 0) continue;
      final double wc = vtx[c + 2];
      if (wc < 0) continue;

      final double ax = vtx[a], ay = vtx[a + 1];
      final double bx = vtx[b], by = vtx[b + 1];
      final double cx = vtx[c], cy = vtx[c + 1];

      // Back-face cull via signed screen area. Screen Y is flipped, so a
      // front face (CCW in world) ends up clockwise here — hence `>= 0`.
      final double area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
      if (area >= 0) continue;

      final int n = t * 3;
      final double nx = fn[n], ny = fn[n + 1], nz = fn[n + 2];

      double key = nx * kl[0] + ny * kl[1] + nz * kl[2];
      if (key < 0) key = 0;
      double fill = nx * fl[0] + ny * fl[1] + nz * fl[2];
      if (fill < 0) fill = 0;
      final double hemi = (nx * up[0] + ny * up[1] + nz * up[2]) * 0.5 + 0.5;

      double lum = ambient + key * keyI + fill * fillI + hemi * hemiI;
      if (hl > 0) lum += hl * 0.30;

      final int base = mats[fmat[t]];
      int r = (base >> 16) & 0xff;
      int g = (base >> 8) & 0xff;
      int bl = base & 0xff;

      if (tintAmt > 0) {
        r = (r + (tr - r) * tintAmt).round();
        g = (g + (tg - g) * tintAmt).round();
        bl = (bl + (tb - bl) * tintAmt).round();
      }

      if (lum <= 1.0) {
        r = (r * lum).round();
        g = (g * lum).round();
        bl = (bl * lum).round();
      } else {
        final double k = (lum - 1.0) * lift;
        r = (r + (255 - r) * k).round();
        g = (g + (255 - g) * k).round();
        bl = (bl + (255 - bl) * k).round();
      }
      if (r > 255) r = 255;
      if (g > 255) g = 255;
      if (bl > 255) bl = 255;
      if (r < 0) r = 0;
      if (g < 0) g = 0;
      if (bl < 0) bl = 0;

      _triA[tc] = a;
      _triB[tc] = b;
      _triC[tc] = c;
      _triColor[tc] = (alpha << 24) | (r << 16) | (g << 8) | bl;
      _triDepth[tc] = (wa + wb + wc) * 0.3333333333 + bias;
      tc++;
    }

    // The vertex scratch is shared between instances, so triangles must be
    // flushed into absolute output coordinates before the next instance
    // overwrites it. Emit positions now; only depth + colour are sorted later.
    for (int i = _triCount; i < tc; i++) {
      final int o = i * 6;
      final int a = _triA[i], b = _triB[i], c = _triC[i];
      _outXY[o] = vtx[a];
      _outXY[o + 1] = vtx[a + 1];
      _outXY[o + 2] = vtx[b];
      _outXY[o + 3] = vtx[b + 1];
      _outXY[o + 4] = vtx[c];
      _outXY[o + 5] = vtx[c + 1];
    }
    _triCount = tc;
  }

  /// Rotates a world vector into an instance's object space using the
  /// transpose of the model's 3x3 basis (valid for rigid + uniform scale).
  static List<double> _invRotate(Float64List m, double x, double y, double z) {
    final double rx = m[0] * x + m[1] * y + m[2] * z;
    final double ry = m[4] * x + m[5] * y + m[6] * z;
    final double rz = m[8] * x + m[9] * y + m[10] * z;
    final double l = math.sqrt(rx * rx + ry * ry + rz * rz);
    if (l < 1e-9) return <double>[0, 1, 0];
    return <double>[rx / l, ry / l, rz / l];
  }

  // ---------------------------------------------------------------- sort
  /// Counting sort on quantised depth: O(n) and fully deterministic, which
  /// matters because the same level must look identical on every replay.
  void _sortAndEmit() {
    final int n = _triCount;
    double lo = double.infinity;
    double hi = -double.infinity;
    for (int i = 0; i < n; i++) {
      final double d = _triDepth[i];
      if (d < lo) lo = d;
      if (d > hi) hi = d;
    }
    final double span = hi - lo;

    if (span < 1e-6) {
      for (int i = 0; i < n; i++) {
        _order[i] = i;
      }
    } else {
      final double scale = (_kBuckets - 1) / span;
      final Uint32List counts = _bucketCount;
      counts.fillRange(0, _kBuckets + 1, 0);

      // Bucket index is inverted so bucket 0 holds the *furthest* triangles;
      // painter's algorithm needs back-to-front.
      for (int i = 0; i < n; i++) {
        final int bIdx = _kBuckets - 1 - ((_triDepth[i] - lo) * scale).toInt();
        counts[bIdx + 1]++;
      }
      for (int b = 0; b < _kBuckets; b++) {
        counts[b + 1] += counts[b];
      }
      for (int i = 0; i < n; i++) {
        final int bIdx = _kBuckets - 1 - ((_triDepth[i] - lo) * scale).toInt();
        _order[counts[bIdx]++] = i;
      }
    }

    // Reorder positions + colours into draw order. Positions are already in
    // screen space, so this is a straight gather.
    final Float32List xy = _outXY;
    final Float32List dst = _sortedXY;
    final Int32List col = _outCol;
    for (int k = 0; k < n; k++) {
      final int src = _order[k];
      final int so = src * 6;
      final int dofs = k * 6;
      dst[dofs] = xy[so];
      dst[dofs + 1] = xy[so + 1];
      dst[dofs + 2] = xy[so + 2];
      dst[dofs + 3] = xy[so + 3];
      dst[dofs + 4] = xy[so + 4];
      dst[dofs + 5] = xy[so + 5];
      final int c = _triColor[src];
      final int co = k * 3;
      col[co] = c;
      col[co + 1] = c;
      col[co + 2] = c;
    }
  }

  // -------------------------------------------------------------- shadows
  /// Soft contact shadows: each instance's bounding box is projected onto the
  /// ground plane along the key light, hulled in screen space, then blurred.
  /// Cheap, shape-aware, and reads exactly like the reference photograph.
  void _drawShadowPass(
    ui.Canvas canvas,
    ui.Size size,
    OrbitCamera camera,
    List<RenderInstance> instances,
    double groundY,
  ) {
    final double strength = _shadowStrength;
    final Float64List vp = camera.viewProj.storage;
    final double halfW = size.width * 0.5;
    final double halfH = size.height * 0.5;

    const double lx = StudioLight.shadowX;
    const double ly = StudioLight.shadowY;
    const double lz = StudioLight.shadowZ;

    for (final RenderInstance inst in instances) {
      if (!inst.visible || !inst.castsShadow || inst.opacity <= 0.05) continue;

      final Mesh mesh = inst.mesh;
      final Float64List mt = inst.transform.storage;
      final Float32List lo = mesh.boundsMin;
      final Float32List bhi = mesh.boundsMax;

      double minY = double.infinity;
      int written = 0;

      for (int corner = 0; corner < 8; corner++) {
        final double ox = (corner & 1) == 0 ? lo[0] : bhi[0];
        final double oy = (corner & 2) == 0 ? lo[1] : bhi[1];
        final double oz = (corner & 4) == 0 ? lo[2] : bhi[2];

        final double wx = mt[0] * ox + mt[4] * oy + mt[8] * oz + mt[12];
        final double wy = mt[1] * ox + mt[5] * oy + mt[9] * oz + mt[13];
        final double wz = mt[2] * ox + mt[6] * oy + mt[10] * oz + mt[14];

        if (wy < minY) minY = wy;

        // Slide the corner down the light ray until it meets the ground.
        final double dy = wy - groundY;
        final double tHit = ly.abs() < 1e-6 ? 0.0 : dy / -ly;
        final double gx = wx + lx * tHit;
        final double gz = wz + lz * tHit;

        // Project the ground point to screen.
        final double cw = vp[3] * gx + vp[7] * groundY + vp[11] * gz + vp[15];
        if (cw < 0.02) continue;
        final double cx = vp[0] * gx + vp[4] * groundY + vp[8] * gz + vp[12];
        final double cy = vp[1] * gx + vp[5] * groundY + vp[9] * gz + vp[13];
        final double inv = 1.0 / cw;
        if (written < 8) {
          _shadowPts[written * 2] = halfW + cx * inv * halfW;
          _shadowPts[written * 2 + 1] = halfH - cy * inv * halfH;
          written++;
        }
      }
      if (written < 3) continue;

      // Height above the floor softens and fades the shadow, which is what
      // sells an object as airborne during a reaction.
      final double height = math.max(0.0, minY - groundY);
      final double fade = 1.0 / (1.0 + height * 1.25);
      double alpha = strength * fade * inst.opacity;
      if (alpha < 0.012) continue;

      final double avgScale = _uniformScale(mt);
      final double sigma = (3.0 + height * 5.5) * math.max(0.35, avgScale);

      _shadowPaint
        ..color = Toy.inkStrong.withValues(alpha: alpha.clamp(0.0, 0.5))
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);

      if (_shapedShadows) {
        final int hn = _convexHull(_shadowPts, written, _hull);
        if (hn < 3) continue;
        final Path p = Path()..moveTo(_hull[0], _hull[1]);
        for (int i = 1; i < hn; i++) {
          p.lineTo(_hull[i * 2], _hull[i * 2 + 1]);
        }
        p.close();
        canvas.drawPath(p, _shadowPaint);
      } else {
        double sx = 0, sy = 0;
        for (int i = 0; i < written; i++) {
          sx += _shadowPts[i * 2];
          sy += _shadowPts[i * 2 + 1];
        }
        sx /= written;
        sy /= written;
        double rx = 0, ry = 0;
        for (int i = 0; i < written; i++) {
          rx = math.max(rx, (_shadowPts[i * 2] - sx).abs());
          ry = math.max(ry, (_shadowPts[i * 2 + 1] - sy).abs());
        }
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(sx, sy),
            width: rx * 2 * inst.shadowScale,
            height: ry * 2 * inst.shadowScale,
          ),
          _shadowPaint,
        );
      }
      stats.shadowsDrawn++;
    }
    _shadowPaint.maskFilter = null;
  }

  static double _uniformScale(Float64List m) {
    final double sx = math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]);
    final double sy = math.sqrt(m[4] * m[4] + m[5] * m[5] + m[6] * m[6]);
    final double sz = math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10]);
    return (sx + sy + sz) / 3.0;
  }

  // Preallocated: the shadow pass runs once per instance per frame and must
  // not allocate.
  final Int32List _hullIdx = Int32List(8);
  final Int32List _hullStack = Int32List(20);

  /// Andrew's monotone chain over at most 8 points. Writes x,y pairs into
  /// [out] and returns the hull vertex count.
  int _convexHull(Float64List pts, int n, Float64List out) {
    final Int32List idx = _hullIdx;
    for (int i = 0; i < n; i++) {
      idx[i] = i;
    }
    // Insertion sort by (x, y) — n is at most 8, so this beats a comparator
    // sort and allocates nothing.
    for (int i = 1; i < n; i++) {
      final int key = idx[i];
      final double kx = pts[key * 2], ky = pts[key * 2 + 1];
      int j = i - 1;
      while (j >= 0) {
        final double jx = pts[idx[j] * 2], jy = pts[idx[j] * 2 + 1];
        if (jx > kx || (jx == kx && jy > ky)) {
          idx[j + 1] = idx[j];
          j--;
        } else {
          break;
        }
      }
      idx[j + 1] = key;
    }

    final Int32List stack = _hullStack;
    int k = 0;
    for (int i = 0; i < n; i++) {
      final int p = idx[i];
      while (k >= 2 && _cross(pts, stack[k - 2], stack[k - 1], p) <= 0) {
        k--;
      }
      stack[k++] = p;
    }
    final int lower = k + 1;
    for (int i = n - 2; i >= 0; i--) {
      final int p = idx[i];
      while (k >= lower && _cross(pts, stack[k - 2], stack[k - 1], p) <= 0) {
        k--;
      }
      stack[k++] = p;
    }
    final int hn = k - 1;
    for (int i = 0; i < hn && i < 8; i++) {
      out[i * 2] = pts[stack[i] * 2];
      out[i * 2 + 1] = pts[stack[i] * 2 + 1];
    }
    return hn > 8 ? 8 : hn;
  }

  static double _cross(Float64List p, int o, int a, int b) {
    return (p[a * 2] - p[o * 2]) * (p[b * 2 + 1] - p[o * 2 + 1]) -
        (p[a * 2 + 1] - p[o * 2 + 1]) * (p[b * 2] - p[o * 2]);
  }
}
