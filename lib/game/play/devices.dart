import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../../engine/physics/body.dart';
import '../level/level_spec.dart';
import 'level_object.dart';

/// What a device can ask the level to do. Implemented by `LevelRuntime`.
abstract class DeviceHost {
  LevelObject? find(String id);
  void activate(String id, {String? by});
  void emit(GameSignal signal);
  double get now;
  double get gravity;
  Iterable<LevelObject> get objects;
}

/// A gameplay-visible moment. Feeds audio, particles, haptics and scoring.
enum SignalKind {
  cannonFire,
  impact,
  buttonPress,
  springLaunch,
  fanOn,
  balloonPop,
  magnetPulse,
  spark,
  breakGlass,
  breakBlock,
  splash,
  gearTurn,
  bridgeMove,
  bell,
  flagRaise,
  chestOpen,
  targetReached,
  collect,
  celebrate,
}

class GameSignal {
  GameSignal(this.kind, {this.at, this.strength = 1.0, this.objectId});

  final SignalKind kind;
  final Vector3? at;
  final double strength;
  final String? objectId;
}

/// Base class for scripted behaviours.
///
/// Devices exist so a reaction stays *readable*. Raw simulation handles what
/// it is good at — toppling, rolling, tipping — and a device takes over
/// wherever pure physics would be fragile or random: a cannon's muzzle
/// velocity, a button that must latch exactly once, a flag that rises on cue.
abstract class Device {
  Device(this.owner, this.spec);

  final LevelObject owner;
  final DeviceSpec spec;

  /// Called when something triggers this device (a tap, or another device).
  void activate(DeviceHost host) {}

  /// Called every fixed gameplay tick.
  void update(DeviceHost host, double dt) {}

  /// Called for each significant impact involving the owner's body.
  void onImpact(DeviceHost host, Body other, double impulse, Vector3 point) {}

  /// Restores spawn state.
  void reset() {}

  /// Whether tapping this object can begin the reaction.
  bool get isStartable => false;

  static Device? create(LevelObject owner, DeviceSpec spec) =>
      switch (spec.type) {
        'cannon' => CannonDevice(owner, spec),
        'button' => ButtonDevice(owner, spec),
        'spring' => SpringDevice(owner, spec),
        'fan' => FanDevice(owner, spec),
        'magnet' => MagnetDevice(owner, spec),
        'conveyor' => ConveyorDevice(owner, spec),
        'rotator' => RotatorDevice(owner, spec),
        'lifter' => LifterDevice(owner, spec),
        'balloon' => BalloonDevice(owner, spec),
        'breakable' => BreakableDevice(owner, spec),
        'target' => TargetDevice(owner, spec),
        'pusher' => PusherDevice(owner, spec),
        'nudge' => NudgeDevice(owner, spec),
        'buoyancy' => BuoyancyDevice(owner, spec),
        _ => null,
      };
}

// ============================================================== cannon
/// Fires a pre-placed ammo body along its aim direction, with a recoil kick.
///
/// The projectile is authored into the level as a hidden object rather than
/// spawned, so firing allocates nothing and a retry restores it exactly.
class CannonDevice extends Device {
  CannonDevice(super.owner, super.spec);

  bool fired = false;
  double _recoil = 0.0;

  @override
  bool get isStartable => true;

  double get power => spec.number('power', 4.2);
  Vector3 get aim => spec.vector('aim', Vector3(1, 0.30, 0));
  String get ammoId => spec.text('ammo') ?? '';
  Vector3 get muzzle => spec.vector('muzzle', Vector3(0.26, 0.04, 0));

  @override
  void activate(DeviceHost host) {
    if (fired) return;
    fired = true;
    _recoil = 1.0;

    final LevelObject? ammo = host.find(ammoId);
    final Body? b = ammo?.body;
    final Body? self = owner.body;
    if (ammo == null || b == null) return;

    final Vector3 dir = aim.normalized();

    // Muzzle offset is authored in the cannon's local frame so an aimed or
    // tilted cannon still spits the ball out of the barrel, not its side.
    final Vector3 world = Vector3.copy(muzzle);
    if (self != null) {
      self.rotation.transform(world);
      world.add(self.position);
    } else {
      world.add(owner.homePosition);
    }

    b.enabled = true;
    b.position.setFrom(world);
    b.orientation.setFrom(ammo.homeOrientation);
    b.stop();
    b.sleeping = false;
    b.sleepTimer = 0;
    b.linearVelocity.setFrom(dir..scale(power));
    b.refresh();

    ammo.instance?.visible = true;
    ammo.participated = true;

    host.emit(GameSignal(SignalKind.cannonFire, at: world, objectId: owner.id));
  }

  @override
  void update(DeviceHost host, double dt) {
    if (_recoil <= 0) return;
    _recoil = math.max(0.0, _recoil - dt * 4.0);
    // Barrel slides back on fire and eases home — purely visual.
    final double kick = _recoil * _recoil * 0.085;
    final ri = owner.instance;
    if (ri != null) {
      ri.transform.setTranslationRaw(
        owner.homePosition.x - kick,
        owner.homePosition.y,
        owner.homePosition.z,
      );
    }
  }

  @override
  void reset() {
    fired = false;
    _recoil = 0;
  }
}

// ============================================================== button
/// Latches once when hit hard enough, then activates its targets.
class ButtonDevice extends Device {
  ButtonDevice(super.owner, super.spec);

  bool pressed = false;
  double _depress = 0.0;

  double get minImpulse => spec.number('minImpulse', 0.03);

  @override
  void onImpact(DeviceHost host, Body other, double impulse, Vector3 point) {
    if (pressed || impulse < minImpulse) return;
    pressed = true;
    _depress = 1.0;
    owner.activated = true;
    owner.activatedAt = host.now;
    host.emit(
      GameSignal(SignalKind.buttonPress, at: point, objectId: owner.id),
    );
    for (final String id in spec.ids('activates')) {
      host.activate(id, by: owner.id);
    }
  }

  @override
  void activate(DeviceHost host) {
    if (pressed) return;
    pressed = true;
    _depress = 1.0;
    owner.activated = true;
    owner.activatedAt = host.now;
    host.emit(GameSignal(SignalKind.buttonPress, objectId: owner.id));
    for (final String id in spec.ids('activates')) {
      host.activate(id, by: owner.id);
    }
  }

  @override
  void update(DeviceHost host, double dt) {
    if (_depress <= 0) return;
    _depress = math.max(0.0, _depress - dt * 3.0);
    final double sink = (1.0 - _depress) * 0.0 + _depress * 0.028;
    final ri = owner.instance;
    if (ri != null) {
      ri.transform.setTranslationRaw(
        owner.homePosition.x,
        owner.homePosition.y - sink,
        owner.homePosition.z,
      );
    }
  }

  @override
  void reset() {
    pressed = false;
    _depress = 0;
  }
}

// ============================================================== spring
/// Launches whatever lands on it, once, along a fixed direction.
class SpringDevice extends Device {
  SpringDevice(super.owner, super.spec);

  bool sprung = false;
  double _extend = 0.0;

  double get power => spec.number('power', 2.6);
  Vector3 get direction => spec.vector('dir', Vector3(0, 1, 0));
  bool get reusable => spec.flag('reusable');

  @override
  void onImpact(DeviceHost host, Body other, double impulse, Vector3 point) {
    if (sprung && !reusable) return;
    if (!other.isDynamic) return;
    sprung = true;
    _extend = 1.0;

    final Vector3 v = direction.normalized()..scale(power);
    other.linearVelocity.setFrom(v);
    other.wake();
    host.emit(
      GameSignal(SignalKind.springLaunch, at: point, objectId: owner.id),
    );
  }

  @override
  void update(DeviceHost host, double dt) {
    if (_extend <= 0) return;
    _extend = math.max(0.0, _extend - dt * 5.0);
  }

  @override
  void reset() {
    sprung = false;
    _extend = 0;
  }
}

// ============================================================== fan
/// Blows dynamic bodies inside a box-shaped region.
class FanDevice extends Device {
  FanDevice(super.owner, super.spec);

  bool on = false;
  bool _announced = false;

  Vector3 get direction => spec.vector('dir', Vector3(1, 0, 0));
  double get force => spec.number('force', 2.2);
  double get range => spec.number('range', 1.6);
  double get width => spec.number('width', 0.45);
  bool get startsOn => spec.flag('on');

  @override
  void activate(DeviceHost host) {
    on = true;
    owner.activated = true;
    owner.activatedAt = host.now;
    if (!_announced) {
      _announced = true;
      host.emit(GameSignal(SignalKind.fanOn, objectId: owner.id));
    }
  }

  @override
  void update(DeviceHost host, double dt) {
    if (!on && !startsOn) return;
    final Body? self = owner.body;
    if (self == null) return;

    final Vector3 dir = direction.normalized();
    for (final LevelObject o in host.objects) {
      final Body? b = o.body;
      if (b == null || !b.isDynamic || !b.enabled) continue;

      final Vector3 rel = b.position - self.position;
      final double along = rel.dot(dir);
      if (along < 0 || along > range) continue;
      // Perpendicular distance from the fan's axis.
      final Vector3 perp = rel - (dir * along);
      if (perp.length > width) continue;

      // Falls off with distance so the stream reads as air, not a piston.
      final double falloff = 1.0 - (along / range) * 0.65;
      b.linearVelocity.addScaled(dir, force * falloff * dt);
      b.wake();
      o.participated = true;
    }
  }

  @override
  void reset() {
    on = false;
    _announced = false;
  }
}

// ============================================================== magnet
/// Pulls tagged bodies towards itself once switched on.
class MagnetDevice extends Device {
  MagnetDevice(super.owner, super.spec);

  bool on = false;

  double get force => spec.number('force', 3.4);
  double get range => spec.number('range', 1.5);
  String get attracts => spec.text('attracts') ?? 'metal';

  @override
  void activate(DeviceHost host) {
    on = true;
    owner.activated = true;
    owner.activatedAt = host.now;
    host.emit(GameSignal(SignalKind.magnetPulse, objectId: owner.id));
  }

  @override
  void update(DeviceHost host, double dt) {
    if (!on && !spec.flag('on')) return;
    final Body? self = owner.body;
    if (self == null) return;

    for (final LevelObject o in host.objects) {
      final Body? b = o.body;
      if (b == null || !b.isDynamic || !b.enabled) continue;
      if (b.tag != attracts) continue;

      final Vector3 rel = self.position - b.position;
      final double d = rel.length;
      if (d > range || d < 1e-4) continue;

      // Linear falloff rather than inverse-square: an inverse-square magnet
      // snaps violently at close range and is impossible to author around.
      final double strength = force * (1.0 - d / range);
      b.linearVelocity.addScaled(rel..scale(1.0 / d), strength * dt);
      b.wake();
      o.participated = true;
    }
  }

  @override
  void reset() => on = false;
}

// ============================================================== conveyor
/// Drags bodies resting on its top surface.
class ConveyorDevice extends Device {
  ConveyorDevice(super.owner, super.spec);

  bool on = false;
  double beltPhase = 0.0;

  Vector3 get direction => spec.vector('dir', Vector3(1, 0, 0));
  double get speed => spec.number('speed', 0.9);
  bool get startsOn => spec.flag('on', fallback: true);

  @override
  void activate(DeviceHost host) {
    on = true;
    owner.activated = true;
    owner.activatedAt = host.now;
  }

  @override
  void update(DeviceHost host, double dt) {
    if (!on && !startsOn) return;
    final Body? self = owner.body;
    if (self == null) return;
    beltPhase += speed * dt;

    final Vector3 dir = direction.normalized();
    final double topY = self.position.y + self.halfExtents.y;

    for (final LevelObject o in host.objects) {
      final Body? b = o.body;
      if (b == null || !b.isDynamic || !b.enabled) continue;

      // Only bodies actually sitting on the belt.
      final Vector3 rel = b.position - self.position;
      if (rel.x.abs() > self.halfExtents.x + 0.12) continue;
      if (rel.z.abs() > self.halfExtents.z + 0.12) continue;
      final double lift = b.position.y - topY;
      if (lift < -0.05 || lift > 0.30) continue;

      // Steer the horizontal velocity towards belt speed, leaving gravity
      // and stacking untouched.
      final double targetX = dir.x * speed;
      final double targetZ = dir.z * speed;
      b.linearVelocity.x +=
          (targetX - b.linearVelocity.x) * math.min(1.0, dt * 7.0);
      b.linearVelocity.z +=
          (targetZ - b.linearVelocity.z) * math.min(1.0, dt * 7.0);
      b.wake();
      o.participated = true;
    }
  }

  @override
  void reset() {
    on = false;
    beltPhase = 0;
  }
}

// ============================================================== rotator
/// Spins a kinematic body about a local axis — gears, water wheels,
/// windmills, spinning carnival rides.
class RotatorDevice extends Device {
  RotatorDevice(super.owner, super.spec);

  bool on = false;
  double angle = 0.0;

  double get speed => spec.number('speed', 1.8);
  Vector3 get axis => spec.vector('axis', Vector3(0, 0, 1));
  bool get startsOn => spec.flag('on');

  @override
  void activate(DeviceHost host) {
    on = true;
    owner.activated = true;
    owner.activatedAt = host.now;
    host.emit(GameSignal(SignalKind.gearTurn, objectId: owner.id));
  }

  @override
  void update(DeviceHost host, double dt) {
    if (!on && !startsOn) return;
    final Body? b = owner.body;
    if (b == null) return;
    angle += speed * dt;
    final Quaternion q = Quaternion.axisAngle(axis.normalized(), angle);
    b.orientation.setFrom(owner.homeOrientation * q);
    // A kinematic body needs a matching angular velocity so contacts impart
    // the right tangential push to whatever it touches.
    b.angularVelocity.setFrom(axis.normalized()..scale(speed));
    b.refresh();
  }

  @override
  void reset() {
    on = false;
    angle = 0;
  }
}

// ============================================================== lifter
/// Moves a kinematic platform between two points — lifts, drawbridges,
/// sliding doors, rising flags.
class LifterDevice extends Device {
  LifterDevice(super.owner, super.spec);

  bool running = false;
  double t = 0.0;

  Vector3 get travel => spec.vector('travel', Vector3(0, 0.6, 0));
  double get duration => spec.number('duration', 1.2);
  bool get loops => spec.flag('loop');
  bool get rotates => spec.params.containsKey('rotate');
  Vector3 get rotateAxis => spec.vector('rotateAxis', Vector3(0, 0, 1));
  double get rotateDeg => spec.number('rotate', 0);

  @override
  void activate(DeviceHost host) {
    if (running) return;
    running = true;
    owner.activated = true;
    owner.activatedAt = host.now;
    host.emit(
      GameSignal(
        spec.flag('isFlag') ? SignalKind.flagRaise : SignalKind.bridgeMove,
        objectId: owner.id,
      ),
    );
  }

  @override
  void update(DeviceHost host, double dt) {
    if (!running) return;
    t = math.min(1.0, t + dt / math.max(0.05, duration));
    // Smootherstep: no visible acceleration snap at either end.
    final double e = t * t * t * (t * (t * 6 - 15) + 10);

    final Body? b = owner.body;
    if (b != null) {
      final Vector3 p = owner.homePosition + (travel * e);
      b.linearVelocity.setFrom(
        (p - b.position)..scale(1.0 / math.max(1e-4, dt)),
      );
      b.position.setFrom(p);
      if (rotates) {
        final Quaternion q = Quaternion.axisAngle(
          rotateAxis.normalized(),
          rotateDeg * math.pi / 180.0 * e,
        );
        b.orientation.setFrom(owner.homeOrientation * q);
      }
      b.refresh();
    }

    if (t >= 1.0) {
      if (loops) {
        t = 0;
      } else {
        running = false;
        b?.linearVelocity.setZero();
      }
    }
  }

  @override
  void reset() {
    running = false;
    t = 0;
  }
}

// ============================================================== balloon
/// Floats upward until popped, carrying whatever it is tied to.
class BalloonDevice extends Device {
  BalloonDevice(super.owner, super.spec);

  bool popped = false;

  double get lift => spec.number('lift', 1.35);
  double get popImpulse => spec.number('popImpulse', 0.9);

  @override
  void update(DeviceHost host, double dt) {
    if (popped) return;
    final Body? b = owner.body;
    if (b == null || !b.enabled) return;
    // Cancel gravity and add a little extra so it climbs, with drag so it
    // reaches a readable terminal speed instead of accelerating away.
    b.linearVelocity.y += (-host.gravity * lift) * dt;
    b.linearVelocity.scale(1.0 - math.min(0.5, dt * 1.4));
    b.wake();
  }

  @override
  void onImpact(DeviceHost host, Body other, double impulse, Vector3 point) {
    if (popped || impulse < spec.number('popThreshold', 0.05)) return;
    popped = true;
    owner.activated = true;
    owner.activatedAt = host.now;

    final Body? b = owner.body;
    if (b != null) {
      b.enabled = false;
      owner.instance?.visible = false;
    }
    host.emit(GameSignal(SignalKind.balloonPop, at: point, objectId: owner.id));

    for (final String id in spec.ids('activates')) {
      host.activate(id, by: owner.id);
    }
    // A pop shoves nearby dynamics, which is what makes it feel like a bang.
    if (b != null) {
      for (final LevelObject o in host.objects) {
        final Body? ob = o.body;
        if (ob == null || !ob.isDynamic || !ob.enabled) continue;
        final Vector3 rel = ob.position - b.position;
        final double d = rel.length;
        if (d > 0.6 || d < 1e-4) continue;
        ob.applyCentralImpulse(rel..scale(popImpulse * (1 - d / 0.6) / d));
      }
    }
  }

  @override
  void reset() => popped = false;
}

// ============================================================== breakable
/// Shatters into pre-placed debris when hit hard enough.
class BreakableDevice extends Device {
  BreakableDevice(super.owner, super.spec);

  bool broken = false;

  double get threshold => spec.number('threshold', 0.10);
  String get flavour => spec.text('flavour') ?? 'block';

  @override
  void onImpact(DeviceHost host, Body other, double impulse, Vector3 point) {
    if (broken || impulse < threshold) return;
    broken = true;
    owner.activated = true;
    owner.activatedAt = host.now;

    owner.body?.enabled = false;
    owner.instance?.visible = false;

    // Wake the authored debris pieces where the intact object stood.
    for (final String id in spec.ids('debris')) {
      final LevelObject? piece = host.find(id);
      final Body? pb = piece?.body;
      if (piece == null || pb == null) continue;
      pb.enabled = true;
      pb.sleeping = false;
      piece.instance?.visible = true;
      piece.participated = true;
      // A small outward kick so the pieces scatter rather than collapse.
      final Vector3 away = pb.position - point;
      final double d = math.max(0.05, away.length);
      pb.linearVelocity.setFrom(away..scale(1.6 / d));
      pb.refresh();
    }

    host.emit(
      GameSignal(
        flavour == 'glass' ? SignalKind.breakGlass : SignalKind.breakBlock,
        at: point,
        strength: impulse,
        objectId: owner.id,
      ),
    );
    for (final String id in spec.ids('activates')) {
      host.activate(id, by: owner.id);
    }
  }

  @override
  void reset() => broken = false;
}

// ============================================================== target
/// The level's finish. Activating it completes the reaction.
class TargetDevice extends Device {
  TargetDevice(super.owner, super.spec);

  bool reached = false;

  double get minImpulse => spec.number('minImpulse', 0.02);

  void _fire(DeviceHost host, Vector3? at) {
    if (reached) return;
    reached = true;
    owner.activated = true;
    owner.activatedAt = host.now;
    host.emit(GameSignal(SignalKind.targetReached, at: at, objectId: owner.id));
    for (final String id in spec.ids('activates')) {
      host.activate(id, by: owner.id);
    }
  }

  @override
  void activate(DeviceHost host) => _fire(host, owner.body?.position);

  @override
  void onImpact(DeviceHost host, Body other, double impulse, Vector3 point) {
    if (impulse < minImpulse) return;
    _fire(host, point);
  }

  @override
  void reset() => reached = false;
}

// ============================================================== pusher
/// A one-shot piston that shoves along an axis when activated.
class PusherDevice extends Device {
  PusherDevice(super.owner, super.spec);

  bool fired = false;
  double t = 0;

  Vector3 get travel => spec.vector('travel', Vector3(0.35, 0, 0));
  double get duration => spec.number('duration', 0.28);

  @override
  void activate(DeviceHost host) {
    if (fired) return;
    fired = true;
    t = 0;
    owner.activated = true;
    owner.activatedAt = host.now;
    host.emit(GameSignal(SignalKind.gearTurn, objectId: owner.id));
  }

  @override
  void update(DeviceHost host, double dt) {
    if (!fired || t >= 1.0) return;
    t = math.min(1.0, t + dt / math.max(0.05, duration));
    final Body? b = owner.body;
    if (b == null) return;
    // Fast out, slow back — a piston's punch is all in the extension.
    final double e = t < 0.55 ? (t / 0.55) : 1.0 - ((t - 0.55) / 0.45) * 0.92;
    final Vector3 p = owner.homePosition + (travel * e);
    b.linearVelocity.setFrom((p - b.position)..scale(1.0 / math.max(1e-4, dt)));
    b.position.setFrom(p);
    b.refresh();
  }

  @override
  void reset() {
    fired = false;
    t = 0;
  }
}

// ============================================================== nudge
/// Applies a single authored impulse to a body when activated.
///
/// This is the deliberate "controlled gameplay event" escape hatch: where a
/// purely physical hand-off would be knife-edge, a nudge guarantees the chain
/// continues with exactly the momentum the level was designed around.
class NudgeDevice extends Device {
  NudgeDevice(super.owner, super.spec);

  bool fired = false;

  Vector3 get impulse => spec.vector('impulse', Vector3(0.15, 0, 0));
  Vector3 get at => spec.vector('at', Vector3.zero());
  String get targetId => spec.text('target') ?? owner.id;

  @override
  void activate(DeviceHost host) {
    if (fired) return;
    fired = true;
    owner.activated = true;
    owner.activatedAt = host.now;

    final LevelObject? t = host.find(targetId);
    final Body? b = t?.body;
    if (b == null) return;
    b.enabled = true;
    b.sleeping = false;
    if (at.length2 < 1e-9) {
      b.applyCentralImpulse(Vector3.copy(impulse));
    } else {
      b.applyImpulse(Vector3.copy(impulse), Vector3.copy(at));
    }
    t?.participated = true;
  }

  @override
  bool get isStartable => spec.flag('startable');

  @override
  void reset() => fired = false;
}

// ============================================================== buoyancy
/// A water volume. Bodies inside float and are slowed.
class BuoyancyDevice extends Device {
  BuoyancyDevice(super.owner, super.spec);

  double get density => spec.number('density', 2.4);
  double get drag => spec.number('drag', 2.0);
  final Set<String> _splashed = <String>{};

  @override
  void update(DeviceHost host, double dt) {
    final Body? self = owner.body;
    if (self == null) return;
    final double surface = self.position.y + self.halfExtents.y;

    for (final LevelObject o in host.objects) {
      final Body? b = o.body;
      if (b == null || !b.isDynamic || !b.enabled) continue;

      final Vector3 rel = b.position - self.position;
      if (rel.x.abs() > self.halfExtents.x) continue;
      if (rel.z.abs() > self.halfExtents.z) continue;

      final double depth = surface - (b.position.y - b.boundingRadius);
      if (depth <= 0) continue;

      if (_splashed.add(o.id)) {
        host.emit(
          GameSignal(
            SignalKind.splash,
            at: Vector3(b.position.x, surface, b.position.z),
            strength: b.linearVelocity.length,
            objectId: o.id,
          ),
        );
      }

      final double submerged = math.min(1.0, depth / (b.boundingRadius * 2));
      b.linearVelocity.y += (-host.gravity * density * submerged) * dt;
      final double d = math.min(0.6, drag * submerged * dt);
      b.linearVelocity.scale(1.0 - d);
      b.angularVelocity.scale(1.0 - d);
      b.wake();
      o.participated = true;
    }
  }

  @override
  void reset() => _splashed.clear();
}
