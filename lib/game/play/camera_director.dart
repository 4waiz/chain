import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../../engine/render/camera.dart';
import '../../engine/render/scene_bounds.dart';
import '../level/level_spec.dart';
import 'level_object.dart';
import 'level_runtime.dart';
import 'reaction_tracker.dart';

/// Drives the camera through a reaction.
///
/// Rules from the brief, in order of priority: never disorient, never hide
/// what matters, and never move faster than the eye can follow. Every target
/// change is an eased interpolation between two orbit states rather than a
/// cut, and the whole rig is critically damped so it settles instead of
/// overshooting.
class CameraDirector {
  CameraDirector(this.camera, this.spec);

  final OrbitCamera camera;
  final LevelSpec spec;

  /// Where the camera is being asked to go. The live camera chases this.
  final OrbitCamera _goal = OrbitCamera();

  /// Framing of the whole level, used before the tap and for big reactions.
  final OrbitCamera _establishing = OrbitCamera();

  double _time = 0;
  double _shake = 0;
  double _shakePhase = 0;

  /// 1.0 = real time. Dips briefly for the final impact.
  double timeScale = 1.0;
  double _slowMoLeft = 0;

  /// Set from settings.
  bool reducedMotion = false;
  bool allowShake = true;

  String? _focusId;
  double _focusHold = 0;

  static const double _followLerp = 3.1;
  static const double _establishLerp = 1.8;

  /// Frames the level and parks the camera there.
  void establish(SceneBounds bounds, double aspect) {
    final CameraSpec c = spec.camera;
    camera
      ..yaw = c.yaw
      ..pitch = c.pitch
      ..fovY = c.fov;
    camera.frameBounds(
      bounds.lo,
      bounds.hi,
      aspect,
      pad: c.pad,
      verticalBias: c.verticalBias,
    );
    _establishing.copyFrom(camera);
    _goal.copyFrom(camera);
    _time = 0;
    _shake = 0;
    _slowMoLeft = 0;
    timeScale = 1.0;
    _focusId = null;
  }

  /// Called every frame with unscaled real time.
  void update(double dt, LevelRuntime rt, double aspect) {
    _time += dt;

    if (_slowMoLeft > 0) {
      _slowMoLeft -= dt;
      // Ease back to full speed rather than snapping.
      timeScale = _slowMoLeft > 0 ? 0.34 : 1.0;
    } else {
      timeScale = math.min(1.0, timeScale + dt * 2.2);
    }

    switch (rt.phase) {
      case RunPhase.inspecting:
        _goal.copyFrom(_establishing);
        // A few degrees of drift, just enough to read the depth of the set.
        if (!reducedMotion) {
          _goal.yaw =
              _establishing.yaw + math.sin(_time * 0.42) * spec.camera.orbit;
        }
        _apply(dt, _establishLerp);
      case RunPhase.reacting:
        _follow(dt, rt, aspect);
      case RunPhase.won:
        _celebrate(dt, rt, aspect);
      case RunPhase.failed:
        _goal.copyFrom(_establishing);
        _apply(dt, _establishLerp);
    }

    _applyShake(dt);
  }

  void _follow(double dt, LevelRuntime rt, double aspect) {
    final StageRun? stage = rt.tracker.activeStage;
    final String? focus = stage?.spec.cameraFocus;

    _focusHold += dt;
    // Do not re-target more often than a person can track.
    if (focus != null && focus != _focusId && _focusHold > 0.35) {
      _focusId = focus;
      _focusHold = 0;
    }

    final LevelObject? target = _focusId == null ? null : rt.find(_focusId!);
    final Vector3? p = target?.body?.position;

    _goal.copyFrom(_establishing);
    if (p != null) {
      // Sit between the whole-scene framing and the action, so context is
      // never lost. Late, sprawling reactions bias further towards the wide
      // shot; early tight ones push in.
      final double spread = rt.tracker.chainLength / math.max(6, spec.parChain);
      final double tight = (1.0 - spread).clamp(0.30, 0.78);
      _goal.target
        ..setFrom(_establishing.target)
        ..scale(1 - tight)
        ..addScaled(p, tight);
      _goal.distance =
          _establishing.distance * (0.70 + 0.30 * spread.clamp(0.0, 1.0));
    }

    _apply(dt, reducedMotion ? _establishLerp : _followLerp);
  }

  void _celebrate(double dt, LevelRuntime rt, double aspect) {
    _goal.copyFrom(_establishing);
    final LevelObject? goal = rt.find(spec.goalObject);
    final Vector3? p = goal?.body?.position;
    if (p != null) {
      _goal.target
        ..setFrom(_establishing.target)
        ..scale(0.45)
        ..addScaled(p, 0.55);
    }
    _goal.distance = _establishing.distance * 0.86;
    if (!reducedMotion) {
      _goal.yaw = _establishing.yaw + math.sin(_time * 0.55) * 0.10;
    }
    _apply(dt, 2.4);
  }

  void _apply(double dt, double rate) {
    // Frame-rate independent exponential approach.
    final double t = 1.0 - math.exp(-rate * dt);
    OrbitCamera.lerpInto(camera, camera, _goal, t.clamp(0.0, 1.0));
  }

  /// A short punch of camera movement on a heavy hit.
  void impulse(double strength) {
    if (!allowShake || reducedMotion) return;
    _shake = math.min(1.0, _shake + strength.clamp(0.0, 1.0) * 0.55);
  }

  /// Brief slow motion, used for the final impact of a reaction.
  void slowMotion([double seconds = 0.5]) {
    if (reducedMotion) return;
    _slowMoLeft = math.max(_slowMoLeft, seconds);
  }

  void _applyShake(double dt) {
    if (_shake <= 0.0005) {
      _shake = 0;
      return;
    }
    _shakePhase += dt * 26.0;
    // Rotational only — translating the camera on a white background reads as
    // a glitch, whereas a tiny yaw/pitch wobble reads as impact.
    final double amp = _shake * 0.016;
    camera.yaw += math.sin(_shakePhase) * amp;
    camera.pitch += math.cos(_shakePhase * 1.37) * amp * 0.55;
    _shake -= dt * 3.4;
  }

  /// Limited manual inspection before the tap, clamped so the player can
  /// never lose the set or see behind it.
  void inspect(double dxPixels, double dyPixels) {
    _establishing.yaw -= dxPixels * 0.0042;
    _establishing.pitch += dyPixels * 0.0032;
    final double baseYaw = spec.camera.yaw;
    _establishing.yaw = _establishing.yaw.clamp(baseYaw - 0.55, baseYaw + 0.55);
    _establishing.pitch = _establishing.pitch.clamp(0.20, 0.92);
  }
}
