import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'body.dart';
import 'manifold.dart';
import 'narrowphase.dart';

/// A collision reported to gameplay this step.
class CollisionEvent {
  CollisionEvent(this.a, this.b, this.impulse, this.point, this.relativeSpeed);

  final Body a;
  final Body b;

  /// Total normal impulse applied. Drives impact volume, particles and shake.
  final double impulse;
  final Vector3 point;

  /// Approach speed at the moment of contact, before it was solved.
  final double relativeSpeed;
}

/// Fixed-step, sequential-impulse rigid-body world.
///
/// Determinism is structural, not incidental:
///
///  * the step is a fixed 1/240 s, driven by an accumulator, so frame-rate
///    variation cannot change the trajectory;
///  * bodies are held in a `List` and always iterated in index order;
///  * candidate pairs come out of a sorted sweep, so contact order is fixed;
///  * warm-start impulses are matched by feature id, not by hash order;
///  * nothing in the step reads a clock or a random number.
///
/// The consequence is that tapping the same starter in the same level always
/// produces the same reaction, which is what the game design depends on.
class PhysicsWorld {
  PhysicsWorld({
    this.gravity = -9.81,
    this.fixedStep = 1.0 / 240.0,
    this.velocityIterations = 8,
    this.positionIterations = 3,
    this.maxSubSteps = 12,
  });

  final double gravity;
  final double fixedStep;
  final int velocityIterations;
  final int positionIterations;

  /// Upper bound on catch-up substeps, so a long frame (app resume, GC pause)
  /// cannot spiral into an unbounded simulation burst.
  final int maxSubSteps;

  final List<Body> bodies = <Body>[];
  final List<CollisionEvent> events = <CollisionEvent>[];

  final Narrowphase _narrow = Narrowphase();

  /// Manifolds are double-buffered. Warm starting reads the previous step's
  /// solved impulses, so the two steps must not share storage — with a single
  /// pool the "previous" entries would be the very objects being overwritten.
  final List<Manifold> _poolA = <Manifold>[];
  final List<Manifold> _poolB = <Manifold>[];
  bool _useA = true;
  int _manifoldCount = 0;

  List<Manifold> get _manifolds => _useA ? _poolA : _poolB;

  /// Previous step's manifolds, keyed for warm starting.
  final Map<int, Manifold> _previous = <int, Manifold>{};
  final Map<int, Manifold> _current = <int, Manifold>{};

  final List<int> _sweep = <int>[];

  int _bySweepX(int i, int j) {
    final double d = bodies[i].aabbMin.x - bodies[j].aabbMin.x;
    if (d < 0) return -1;
    if (d > 0) return 1;
    return i - j; // stable tiebreak keeps ordering deterministic
  }

  double _accumulator = 0.0;
  int _nextId = 0;

  /// Total simulated time. Used by the reaction graph for timed triggers.
  double elapsed = 0.0;

  /// Steps taken since reset. Handy for deterministic replay assertions.
  int stepCount = 0;

  // Tuning.
  static const double _slop = 0.0016;
  static const double _baumgarte = 0.22;
  static const double _restitutionThreshold = 0.55;
  static const double _sleepLinear = 0.022;
  static const double _sleepAngular = 0.055;
  static const double _sleepTime = 0.45;
  static const double _maxLinearVelocity = 42.0;
  static const double _maxAngularVelocity = 46.0;

  // Solver scratch.
  final Vector3 _rv = Vector3.zero();
  final Vector3 _tmpA = Vector3.zero();
  final Vector3 _tmpB = Vector3.zero();
  final Vector3 _impulse = Vector3.zero();

  Body add(Body b) {
    bodies.add(b);
    b.refresh();
    return b;
  }

  Body create({
    required BodyKind kind,
    required ShapeKind shape,
    Vector3? position,
    Quaternion? orientation,
    Vector3? halfExtents,
    double radius = 0.1,
    double mass = 1.0,
    double friction = 0.55,
    double restitution = 0.06,
    String tag = '',
    String nodeId = '',
    bool isSensor = false,
    double gravityScale = 1.0,
  }) {
    final Body b = Body(
      id: _nextId++,
      kind: kind,
      shape: shape,
      position: position,
      orientation: orientation,
      halfExtents: halfExtents,
      radius: radius,
      mass: mass,
      friction: friction,
      restitution: restitution,
      tag: tag,
      nodeId: nodeId,
      isSensor: isSensor,
      gravityScale: gravityScale,
    );
    return add(b);
  }

  /// Empties the world completely, including the id counter, so a rebuilt
  /// level produces byte-identical body ids and therefore identical ordering.
  void clear() {
    bodies.clear();
    events.clear();
    _poolA.clear();
    _poolB.clear();
    _useA = true;
    _manifoldCount = 0;
    _previous.clear();
    _current.clear();
    _sweep.clear();
    _accumulator = 0.0;
    _nextId = 0;
    elapsed = 0.0;
    stepCount = 0;
  }

  /// Clears transient simulation state but keeps the bodies. Callers restore
  /// body transforms themselves; this drops everything that would otherwise
  /// leak the previous run into the next one.
  void resetSimulationState() {
    events.clear();
    _manifoldCount = 0;
    _previous.clear();
    _current.clear();
    _accumulator = 0.0;
    elapsed = 0.0;
    stepCount = 0;
    for (final Body b in bodies) {
      b.stop();
      b.sleeping = false;
      b.sleepTimer = 0.0;
      b.lastImpactImpulse = 0.0;
      b.refresh();
    }
  }

  /// Advances the world by [dt] real seconds in fixed substeps.
  ///
  /// Returns the number of substeps actually run.
  int step(double dt) {
    events.clear();
    if (dt <= 0) return 0;
    _accumulator += dt;

    int n = 0;
    while (_accumulator >= fixedStep && n < maxSubSteps) {
      _substep(fixedStep);
      _accumulator -= fixedStep;
      n++;
    }
    // If we hit the substep ceiling, drop the backlog rather than carrying a
    // debt that would make the next frames run long too.
    if (n >= maxSubSteps) _accumulator = 0.0;
    return n;
  }

  void _substep(double h) {
    elapsed += h;
    stepCount++;

    // ---- integrate velocities -------------------------------------------
    for (int i = 0; i < bodies.length; i++) {
      final Body b = bodies[i];
      if (!b.enabled || !b.isDynamic || b.sleeping) continue;
      b.linearVelocity.y += gravity * b.gravityScale * h;

      final double ld = 1.0 / (1.0 + h * b.linearDamping * 10.0);
      final double ad = 1.0 / (1.0 + h * b.angularDamping * 10.0);
      b.linearVelocity.scale(ld);
      b.angularVelocity.scale(ad);

      _clampVelocity(b);
    }

    for (int i = 0; i < bodies.length; i++) {
      if (bodies[i].enabled) bodies[i].refresh();
    }

    // ---- collision -------------------------------------------------------
    // Hand the manifolds just solved to the warm-start cache, then swap pools
    // so this substep writes somewhere the cache is not pointing at. The swap
    // has to happen *here* rather than at the end of the substep: gameplay
    // reads the solved manifolds via collectImpacts() after step() returns,
    // and those must still be the ones that were solved.
    _previous.clear();
    _previous.addAll(_current);
    _useA = !_useA;
    _broadphase();

    // ---- solve -----------------------------------------------------------
    _preSolve(h);
    _warmStart();
    for (int it = 0; it < velocityIterations; it++) {
      _solveVelocity();
    }

    // ---- integrate positions --------------------------------------------
    for (int i = 0; i < bodies.length; i++) {
      final Body b = bodies[i];
      if (!b.enabled || !b.movable || b.sleeping) continue;
      b.position.addScaled(b.linearVelocity, h);
      Body.integrateOrientation(b.orientation, b.angularVelocity, h);
    }
    for (int i = 0; i < bodies.length; i++) {
      if (bodies[i].enabled) bodies[i].refresh();
    }

    // ---- position correction (split impulse) -----------------------------
    for (int it = 0; it < positionIterations; it++) {
      _solvePosition();
    }
    for (int i = 0; i < bodies.length; i++) {
      if (bodies[i].enabled) bodies[i].refresh();
    }

    _updateSleep(h);
  }

  void _clampVelocity(Body b) {
    final double l2 = b.linearVelocity.length2;
    if (l2 > _maxLinearVelocity * _maxLinearVelocity) {
      b.linearVelocity.scale(_maxLinearVelocity / math.sqrt(l2));
    }
    final double a2 = b.angularVelocity.length2;
    if (a2 > _maxAngularVelocity * _maxAngularVelocity) {
      b.angularVelocity.scale(_maxAngularVelocity / math.sqrt(a2));
    }
  }

  // ----------------------------------------------------------- broadphase
  /// Sort-and-sweep along X. Bodies are sorted by AABB minimum, then each is
  /// tested only against the following bodies whose spans still overlap.
  void _broadphase() {
    _manifoldCount = 0;
    _current.clear();

    _sweep.clear();
    for (int i = 0; i < bodies.length; i++) {
      if (bodies[i].enabled) _sweep.add(i);
    }
    _sweep.sort(_bySweepX);

    for (int si = 0; si < _sweep.length; si++) {
      final Body a = bodies[_sweep[si]];
      for (int sj = si + 1; sj < _sweep.length; sj++) {
        final Body b = bodies[_sweep[sj]];
        if (b.aabbMin.x > a.aabbMax.x) break; // sweep done for `a`

        if (!a.movable && !b.movable) continue;
        if (a.sleeping && b.sleeping) continue;
        if (!a.isDynamic && !b.isDynamic) continue;

        if (a.aabbMin.y > b.aabbMax.y || b.aabbMin.y > a.aabbMax.y) continue;
        if (a.aabbMin.z > b.aabbMax.z || b.aabbMin.z > a.aabbMax.z) continue;

        // Order the pair by id so the manifold key and normal direction are
        // independent of the sweep order.
        final Body lo = a.id < b.id ? a : b;
        final Body hi = a.id < b.id ? b : a;
        _collidePair(lo, hi);
      }
    }
  }

  void _collidePair(Body a, Body b) {
    while (_manifolds.length <= _manifoldCount) {
      _manifolds.add(Manifold());
    }
    final Manifold m = _manifolds[_manifoldCount];
    if (!_narrow.collide(a, b, m)) return;

    final Manifold? old = _previous[m.key];
    if (old != null) m.warmStartFrom(old);

    // A touch from something that can actually move wakes a sleeping body, so
    // a chain propagates into a stack that had already settled.
    //
    // Two conditions matter here. The toucher must be *movable* — a static
    // floor is permanently "not sleeping", so without this check nothing
    // resting on the ground could ever fall asleep. And the target must
    // already be asleep — waking an awake body resets its sleep timer, so
    // two settling neighbours would keep each other awake forever.
    if (!m.sensorOnly) {
      if (b.sleeping && a.movable && !a.sleeping) b.wake();
      if (a.sleeping && b.movable && !b.sleeping) a.wake();
    }

    _current[m.key] = m;
    _manifoldCount++;
  }

  // --------------------------------------------------------------- solver
  void _preSolve(double h) {
    for (int i = 0; i < _manifoldCount; i++) {
      final Manifold m = _manifolds[i];
      if (m.sensorOnly) {
        _reportSensor(m);
        continue;
      }
      final Body a = m.a, b = m.b;

      for (int k = 0; k < m.pointCount; k++) {
        final ContactPoint p = m.points[k];
        p.rA
          ..setFrom(p.position)
          ..sub(a.position);
        p.rB
          ..setFrom(p.position)
          ..sub(b.position);

        p.normalMass = _effectiveMass(a, b, p.rA, p.rB, m.normal);
        p.tangentMass1 = _effectiveMass(a, b, p.rA, p.rB, m.tangent1);
        p.tangentMass2 = _effectiveMass(a, b, p.rA, p.rB, m.tangent2);

        // Restitution only above a threshold, otherwise resting contacts
        // buzz forever.
        _relativeVelocity(a, b, p.rA, p.rB, _rv);
        final double vn = _rv.dot(m.normal);
        p.velocityBias = 0.0;
        if (vn < -_restitutionThreshold) {
          p.velocityBias = -m.restitution * vn;
        }
      }
    }
  }

  void _warmStart() {
    for (int i = 0; i < _manifoldCount; i++) {
      final Manifold m = _manifolds[i];
      if (m.sensorOnly) continue;
      final Body a = m.a, b = m.b;
      for (int k = 0; k < m.pointCount; k++) {
        final ContactPoint p = m.points[k];
        _impulse
          ..setFrom(m.normal)
          ..scale(p.normalImpulse)
          ..addScaled(m.tangent1, p.tangentImpulse1)
          ..addScaled(m.tangent2, p.tangentImpulse2);
        _applyPair(a, b, _impulse, p.rA, p.rB);
      }
    }
  }

  void _solveVelocity() {
    for (int i = 0; i < _manifoldCount; i++) {
      final Manifold m = _manifolds[i];
      if (m.sensorOnly) continue;
      final Body a = m.a, b = m.b;

      for (int k = 0; k < m.pointCount; k++) {
        final ContactPoint p = m.points[k];

        // --- normal ---
        _relativeVelocity(a, b, p.rA, p.rB, _rv);
        final double vn = _rv.dot(m.normal);
        double dPn = (-vn + p.velocityBias) * p.normalMass;
        final double oldPn = p.normalImpulse;
        p.normalImpulse = math.max(0.0, oldPn + dPn);
        dPn = p.normalImpulse - oldPn;
        if (dPn != 0.0) {
          _impulse
            ..setFrom(m.normal)
            ..scale(dPn);
          _applyPair(a, b, _impulse, p.rA, p.rB);
        }

        // --- friction (two tangents, clamped to the friction cone) ---
        final double maxF = m.friction * p.normalImpulse;

        _relativeVelocity(a, b, p.rA, p.rB, _rv);
        double vt = _rv.dot(m.tangent1);
        double dPt = -vt * p.tangentMass1;
        double oldPt = p.tangentImpulse1;
        p.tangentImpulse1 = (oldPt + dPt).clamp(-maxF, maxF);
        dPt = p.tangentImpulse1 - oldPt;
        if (dPt != 0.0) {
          _impulse
            ..setFrom(m.tangent1)
            ..scale(dPt);
          _applyPair(a, b, _impulse, p.rA, p.rB);
        }

        _relativeVelocity(a, b, p.rA, p.rB, _rv);
        vt = _rv.dot(m.tangent2);
        dPt = -vt * p.tangentMass2;
        oldPt = p.tangentImpulse2;
        p.tangentImpulse2 = (oldPt + dPt).clamp(-maxF, maxF);
        dPt = p.tangentImpulse2 - oldPt;
        if (dPt != 0.0) {
          _impulse
            ..setFrom(m.tangent2)
            ..scale(dPt);
          _applyPair(a, b, _impulse, p.rA, p.rB);
        }
      }
    }
  }

  /// Positional correction, kept entirely out of the velocity solve.
  ///
  /// Overlap is pushed out by translating the bodies in inverse-mass
  /// proportion rather than by injecting velocity, so a deep interpenetration
  /// — a domino spawned slightly inside its neighbour, a block dropped into a
  /// stack — settles instead of exploding. The accumulated `positionImpulse`
  /// is clamped at zero so a contact can only ever push, never pull.
  void _solvePosition() {
    for (int i = 0; i < _manifoldCount; i++) {
      final Manifold m = _manifolds[i];
      if (m.sensorOnly) continue;
      final Body a = m.a, b = m.b;
      final double totalInvMass = a.invMass + b.invMass;
      if (totalInvMass <= 0) continue;

      for (int k = 0; k < m.pointCount; k++) {
        final ContactPoint p = m.points[k];
        final double depth = p.penetration - _slop;
        if (depth <= 0) continue;

        double push = (_baumgarte * depth) / totalInvMass;
        final double old = p.positionImpulse;
        p.positionImpulse = math.max(0.0, old + push);
        push = p.positionImpulse - old;
        if (push == 0.0) continue;

        if (a.invMass > 0 && a.movable) {
          a.position.addScaled(m.normal, -push * a.invMass);
        }
        if (b.invMass > 0 && b.movable) {
          b.position.addScaled(m.normal, push * b.invMass);
        }
      }
    }
  }

  void _reportSensor(Manifold m) {
    if (m.pointCount == 0) return;
    _relativeVelocity(m.a, m.b, m.points[0].rA, m.points[0].rB, _rv);
    events.add(
      CollisionEvent(m.a, m.b, 0.0, m.points[0].position.clone(), _rv.length),
    );
  }

  /// Emits one event per manifold whose accumulated normal impulse crossed a
  /// meaningful threshold, so gameplay hears real hits and not resting weight.
  void collectImpacts(double minImpulse) {
    for (int i = 0; i < _manifoldCount; i++) {
      final Manifold m = _manifolds[i];
      if (m.sensorOnly) continue;
      double total = 0;
      for (int k = 0; k < m.pointCount; k++) {
        total += m.points[k].normalImpulse;
      }
      if (total < minImpulse) continue;
      m.a.lastImpactImpulse = math.max(m.a.lastImpactImpulse, total);
      m.b.lastImpactImpulse = math.max(m.b.lastImpactImpulse, total);
      _relativeVelocity(m.a, m.b, m.points[0].rA, m.points[0].rB, _rv);
      events.add(
        CollisionEvent(
          m.a,
          m.b,
          total,
          m.points[0].position.clone(),
          _rv.length,
        ),
      );
    }
  }

  // ------------------------------------------------------------- sleeping
  void _updateSleep(double h) {
    for (int i = 0; i < bodies.length; i++) {
      final Body b = bodies[i];
      if (!b.enabled || !b.isDynamic) continue;
      if (!b.canSleep) {
        b.sleeping = false;
        continue;
      }
      if (b.sleeping) continue;

      if (b.linearVelocity.length2 < _sleepLinear * _sleepLinear &&
          b.angularVelocity.length2 < _sleepAngular * _sleepAngular) {
        b.sleepTimer += h;
        if (b.sleepTimer >= _sleepTime) {
          b.sleeping = true;
          b.stop();
        }
      } else {
        b.sleepTimer = 0.0;
      }
    }
  }

  // ---------------------------------------------------------------- maths
  /// Inverse of the constraint's effective mass along [dir].
  ///
  ///   k = 1/mA + 1/mB + u_a . (Ia^-1 u_a) + u_b . (Ib^-1 u_b),  u = r x dir
  ///
  /// The angular terms reduce to that quadratic form via the triple product
  /// identity, which also makes them provably non-negative — writing them as
  /// `(r x (I^-1 u)) . dir` instead flips the sign and can drive k towards
  /// zero, producing an effectively infinite impulse.
  double _effectiveMass(Body a, Body b, Vector3 rA, Vector3 rB, Vector3 dir) {
    double k = a.invMass + b.invMass;

    rA.crossInto(dir, _tmpA);
    _tmpB.setFrom(a.invInertiaWorld.transformed(_tmpA));
    k += _tmpA.dot(_tmpB);

    rB.crossInto(dir, _tmpA);
    _tmpB.setFrom(b.invInertiaWorld.transformed(_tmpA));
    k += _tmpA.dot(_tmpB);

    return k > 1e-12 ? 1.0 / k : 0.0;
  }

  void _relativeVelocity(Body a, Body b, Vector3 rA, Vector3 rB, Vector3 out) {
    b.angularVelocity.crossInto(rB, _tmpA);
    out
      ..setFrom(b.linearVelocity)
      ..add(_tmpA);
    a.angularVelocity.crossInto(rA, _tmpA);
    out
      ..sub(a.linearVelocity)
      ..sub(_tmpA);
  }

  void _applyPair(Body a, Body b, Vector3 impulse, Vector3 rA, Vector3 rB) {
    if (a.invMass > 0) {
      a.linearVelocity.addScaled(impulse, -a.invMass);
      rA.crossInto(impulse, _tmpA);
      _tmpA.setFrom(a.invInertiaWorld.transformed(_tmpA));
      a.angularVelocity.sub(_tmpA);
    }
    if (b.invMass > 0) {
      b.linearVelocity.addScaled(impulse, b.invMass);
      rB.crossInto(impulse, _tmpA);
      _tmpA.setFrom(b.invInertiaWorld.transformed(_tmpA));
      b.angularVelocity.add(_tmpA);
    }
  }

  // ------------------------------------------------------------ raycasting
  /// Nearest-hit ray cast, used by one-tap picking.
  ///
  /// Returns the hit body, or null. [outDistance] receives the hit distance.
  Body? raycast(
    Vector3 origin,
    Vector3 direction,
    double maxDistance, {
    bool Function(Body)? filter,
  }) {
    Body? best;
    double bestT = maxDistance;
    for (int i = 0; i < bodies.length; i++) {
      final Body b = bodies[i];
      if (!b.enabled) continue;
      if (filter != null && !filter(b)) continue;
      final double t = b.shape == ShapeKind.sphere
          ? _raySphere(origin, direction, b)
          : _rayBox(origin, direction, b);
      if (t >= 0 && t < bestT) {
        bestT = t;
        best = b;
      }
    }
    lastRayDistance = best == null ? -1 : bestT;
    return best;
  }

  double lastRayDistance = -1;

  double _raySphere(Vector3 o, Vector3 d, Body b) {
    _tmpA
      ..setFrom(o)
      ..sub(b.position);
    final double bq = _tmpA.dot(d);
    final double c = _tmpA.length2 - b.radius * b.radius;
    if (c > 0 && bq > 0) return -1;
    final double disc = bq * bq - c;
    if (disc < 0) return -1;
    final double t = -bq - math.sqrt(disc);
    return t < 0 ? 0.0 : t;
  }

  double _rayBox(Vector3 o, Vector3 d, Body b) {
    // Transform the ray into the box's local frame and slab-test.
    _tmpA
      ..setFrom(o)
      ..sub(b.position);
    final r = b.rotation.storage;
    final double ox = _tmpA.x * r[0] + _tmpA.y * r[1] + _tmpA.z * r[2];
    final double oy = _tmpA.x * r[3] + _tmpA.y * r[4] + _tmpA.z * r[5];
    final double oz = _tmpA.x * r[6] + _tmpA.y * r[7] + _tmpA.z * r[8];
    final double dx = d.x * r[0] + d.y * r[1] + d.z * r[2];
    final double dy = d.x * r[3] + d.y * r[4] + d.z * r[5];
    final double dz = d.x * r[6] + d.y * r[7] + d.z * r[8];

    double tmin = -double.infinity, tmax = double.infinity;
    for (int axis = 0; axis < 3; axis++) {
      final double o = axis == 0 ? ox : (axis == 1 ? oy : oz);
      final double dd = axis == 0 ? dx : (axis == 1 ? dy : dz);
      final double e = axis == 0
          ? b.halfExtents.x
          : (axis == 1 ? b.halfExtents.y : b.halfExtents.z);

      if (dd.abs() < 1e-9) {
        // Ray is parallel to this slab: it either starts inside it or misses.
        if (o < -e || o > e) return -1;
        continue;
      }
      final double inv = 1.0 / dd;
      double t1 = (-e - o) * inv;
      double t2 = (e - o) * inv;
      if (t1 > t2) {
        final double t = t1;
        t1 = t2;
        t2 = t;
      }
      if (t1 > tmin) tmin = t1;
      if (t2 < tmax) tmax = t2;
      if (tmin > tmax) return -1;
    }
    if (tmax < 0) return -1;
    return tmin < 0 ? 0.0 : tmin;
  }
}
