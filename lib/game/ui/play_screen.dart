import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../data/audio_service.dart';
import '../../data/save_service.dart';
import '../../data/settings.dart';
import '../../engine/render/camera.dart';
import '../../engine/render/palette.dart';
import '../../engine/render/renderer.dart';
import '../../engine/render/scene_view.dart';
import '../level/level_repository.dart';
import '../level/level_spec.dart';
import '../play/camera_director.dart';
import '../play/devices.dart';
import '../play/fx.dart';
import '../play/level_object.dart';
import '../play/level_runtime.dart';
import '../play/scoring.dart';
import 'design.dart';
import 'result_sheets.dart';

/// The gameplay screen: one diorama, one tap, one reaction.
class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.levelId, this.onExit})
    : preBuilt = null,
      mode = PlayMode.campaign,
      onFinished = null;

  /// Used by the Daily Challenge and the Reaction Lab, which generate their
  /// level in memory rather than loading it from the bundle.
  const PlayScreen.fromSpec({
    super.key,
    required LevelSpec spec,
    required this.mode,
    this.onExit,
    this.onFinished,
  }) : preBuilt = spec,
       levelId = '';

  final String levelId;
  final LevelSpec? preBuilt;
  final PlayMode mode;
  final VoidCallback? onExit;
  final void Function(LevelResult result)? onFinished;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

enum PlayMode { campaign, daily, lab }

class _PlayScreenState extends State<PlayScreen> with WidgetsBindingObserver {
  final OrbitCamera _camera = OrbitCamera();
  final Renderer _renderer = Renderer();
  final FxSystem _fx = FxSystem();

  LevelSpec? _spec;
  LevelRuntime? _rt;
  CameraDirector? _director;

  String? _error;
  bool _paused = false;
  bool _framed = false;
  bool _resultShown = false;
  int _failCount = 0;
  double _resultAnim = 0;

  double _shownMultiplier = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    try {
      final LevelSpec spec = widget.preBuilt != null
          ? await LevelRepository.instance.prepareSpec(widget.preBuilt!)
          : await LevelRepository.instance.prepare(widget.levelId);
      final LevelRuntime rt = LevelRuntime(spec)..build();
      _fx.preparePieces(rt.instances);
      _fx.reset();

      final CameraDirector dir = CameraDirector(_camera, spec);
      _applySettings(dir);

      if (!mounted) return;
      setState(() {
        _spec = spec;
        _rt = rt;
        _director = dir;
        _framed = false;
      });
      unawaited(AudioService.instance.startMusic());
    } catch (e, st) {
      debugPrint('PlayScreen boot failed: $e\n$st');
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _applySettings(CameraDirector dir) {
    final Settings s = Settings.instance;
    dir.reducedMotion = s.reducedMotion;
    dir.allowShake = s.cameraShake;
    _renderer.quality = switch (s.quality) {
      GraphicsQuality.low => RenderQuality.low,
      GraphicsQuality.medium => RenderQuality.medium,
      GraphicsQuality.high => RenderQuality.high,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (mounted && !_paused) setState(() => _paused = true);
      unawaited(AudioService.instance.pauseAll());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(AudioService.instance.resumeMusic());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ------------------------------------------------------------------ loop
  void _onFrame(double dt) {
    final LevelRuntime? rt = _rt;
    final CameraDirector? dir = _director;
    if (rt == null || dir == null || _paused) return;

    AudioService.instance.tick(dt);

    // The director owns time dilation, so the simulation and the effects all
    // slow together during the final-impact beat.
    final double sim = dt * dir.timeScale;

    rt.update(sim);
    _drainSignals(rt, dir);
    _fx.update(sim);
    dir.update(dt, rt, _aspect);

    AudioService.instance.updateChain(rt.tracker.chainLength, rt.spec.parChain);

    final double target = Scoring.multiplierFor(rt.tracker.chainLength);
    _shownMultiplier += (target - _shownMultiplier) * math.min(1.0, dt * 7);

    if (rt.phase == RunPhase.won || rt.phase == RunPhase.failed) {
      if (!_resultShown) {
        _resultShown = true;
        _onRunFinished(rt);
      }
      if (_resultAnim < 1.0) {
        _resultAnim = math.min(1.0, _resultAnim + dt * 2.2);
        // The result sheet lives in the widget tree, not the scene, so it only
        // redraws when the element rebuilds. Without this it would freeze at
        // whatever opacity it happened to have on the frame it appeared.
        if (mounted) setState(() {});
      }
    }
  }

  double get _aspect {
    final Size s = MediaQuery.sizeOf(context);
    return s.height <= 0 ? 1.0 : s.width / s.height;
  }

  void _drainSignals(LevelRuntime rt, CameraDirector dir) {
    for (final GameSignal s in rt.signals) {
      AudioService.instance.onSignal(s);
      _fx.onSignal(s);

      switch (s.kind) {
        case SignalKind.impact:
          dir.impulse(s.strength.clamp(0.0, 1.0) * 0.7);
        case SignalKind.cannonFire:
          dir.impulse(0.45);
        case SignalKind.targetReached:
          dir.impulse(0.8);
          dir.slowMotion(0.55);
        case SignalKind.celebrate:
          final LevelObject? goal = rt.find(rt.spec.goalObject);
          _fx.celebrate(goal?.body?.position ?? Vector3(0, 0.5, 0));
        case SignalKind.breakBlock:
        case SignalKind.breakGlass:
        case SignalKind.balloonPop:
          dir.impulse(0.5);
        default:
          break;
      }
    }
  }

  Future<void> _onRunFinished(LevelRuntime rt) async {
    final LevelResult? r = rt.result;
    if (r == null) return;

    // Daily and Lab runs report back to their host screen and are not part of
    // campaign progression.
    if (widget.mode != PlayMode.campaign) {
      widget.onFinished?.call(r);
      if (r.completed) {
        AudioService.instance.play('level_complete', volume: 0.9);
      } else {
        _failCount++;
        AudioService.instance.play('failure', volume: 0.8);
      }
      if (mounted) setState(() {});
      return;
    }

    if (r.completed) {
      await SaveService.instance.recordResult(
        widget.levelId,
        stars: r.stars,
        score: r.score,
        chain: r.chainLength,
        time: r.timeSec,
        coinsEarned: r.coins,
        bonuses: r.bonusesMet,
        completed: true,
      );
      // Toy City grows one landmark per completed level.
      await SaveService.instance.unlockCity(widget.levelId);
      AudioService.instance.play('city_upgrade', volume: 0.55);
    } else {
      _failCount++;
      AudioService.instance.play('failure', volume: 0.8);
      await SaveService.instance.recordResult(
        widget.levelId,
        stars: 0,
        score: 0,
        chain: r.chainLength,
        time: r.timeSec,
        coinsEarned: 0,
        bonuses: const <String>[],
        completed: false,
      );
    }
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------------- input
  void _onTap(Offset local, Size size) {
    final LevelRuntime? rt = _rt;
    if (rt == null || _paused) return;

    if (rt.phase != RunPhase.inspecting) return;

    final Vector3 o = Vector3.zero();
    final Vector3 d = Vector3.zero();
    _camera.screenRay(local.dx, local.dy, size.width, size.height, o, d);

    final String? started = rt.tapStarter(o, d);
    if (started != null) {
      AudioService.instance.haptic(HapticStrength.medium);
      setState(() {});
    } else {
      AudioService.instance.uiTap();
    }
  }

  void _restart() {
    final LevelRuntime? rt = _rt;
    if (rt == null) return;
    AudioService.instance.uiTap();
    rt.reset();
    _fx.reset();
    _resultShown = false;
    _resultAnim = 0;
    _shownMultiplier = 1.0;
    _director?.establish(rt.bounds, _aspect);
    setState(() => _paused = false);
  }

  void _exit() {
    AudioService.instance.uiTap();
    final VoidCallback? onExit = widget.onExit;
    if (onExit != null) {
      onExit();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // ------------------------------------------------------------------ view
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: StudioBackdrop(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(D.s5),
              child: ToyCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'This level could not load',
                      style: D.heading(Toy.inkStrong),
                    ),
                    const SizedBox(height: D.s3),
                    Text(
                      _error!,
                      style: D.body(Toy.inkSoft),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: D.s4),
                    ToyButton(label: 'Back', colour: Toy.blue, onTap: _exit),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final LevelRuntime? rt = _rt;
    final LevelSpec? spec = _spec;
    if (rt == null || spec == null) {
      return const Scaffold(
        body: StudioBackdrop(
          child: Center(child: CircularProgressIndicator(color: Toy.blue)),
        ),
      );
    }

    return Scaffold(
      body: StudioBackdrop(
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (BuildContext ctx, BoxConstraints c) {
                    if (!_framed && c.maxHeight > 0) {
                      _framed = true;
                      _director!.establish(rt.bounds, c.maxWidth / c.maxHeight);
                    }
                    return SceneView(
                      camera: _camera,
                      instances: rt.instances,
                      renderer: _renderer,
                      onFrame: _onFrame,
                      onTapWorld: _onTap,
                      paused: _paused,
                      onPan: rt.phase == RunPhase.inspecting
                          ? (Offset d) => _director!.inspect(d.dx, d.dy)
                          : null,
                      overlay: (ui.Canvas canvas, Size size) =>
                          _fx.draw(canvas, size, _camera),
                    );
                  },
                ),
              ),
              _Hud(
                spec: spec,
                rt: rt,
                multiplier: _shownMultiplier,
                onPause: () {
                  AudioService.instance.uiTap();
                  setState(() => _paused = true);
                },
                onRestart: _restart,
              ),
              if (rt.phase == RunPhase.inspecting) _TapPrompt(rt: rt),
              if (_paused)
                PauseSheet(
                  onResume: () {
                    AudioService.instance.uiTap();
                    setState(() => _paused = false);
                  },
                  onRestart: _restart,
                  onQuit: _exit,
                ),
              if (rt.phase == RunPhase.failed && !_paused)
                FailSheet(
                  t: _resultAnim,
                  breakdown: rt.tracker.breakdownStage,
                  chain: rt.tracker.chainLength,
                  showHint: _failCount >= 2,
                  hint: spec.hint,
                  onRetry: _restart,
                  onMenu: _exit,
                ),
              if (rt.phase == RunPhase.won && !_paused && rt.result != null)
                CompleteSheet(
                  t: _resultAnim,
                  result: rt.result!,
                  spec: spec,
                  onRetry: _restart,
                  onContinue: () {
                    AudioService.instance.uiTap();
                    if (widget.mode != PlayMode.campaign) {
                      _exit();
                      return;
                    }
                    final String? next = LevelRepository.instance.nextLevelId(
                      widget.levelId,
                    );
                    if (next == null) {
                      _exit();
                      return;
                    }
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PlayScreen(levelId: next, onExit: widget.onExit),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimal in-play HUD. Deliberately hugs the top and bottom edges so it never
/// covers the diorama.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.spec,
    required this.rt,
    required this.multiplier,
    required this.onPause,
    required this.onRestart,
  });

  final LevelSpec spec;
  final LevelRuntime rt;
  final double multiplier;
  final VoidCallback onPause;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final bool reacting = rt.phase == RunPhase.reacting;
    final int stars = SaveService.instance.progressFor(spec.id).stars;

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s3),
        child: Row(
          children: <Widget>[
            ToyIconButton(
              icon: Icons.pause_rounded,
              onTap: onPause,
              tooltip: 'Pause',
            ),
            const SizedBox(width: D.s3),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: D.s4,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Toy.white,
                borderRadius: BorderRadius.circular(D.rPill),
                boxShadow: D.chip,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${spec.world}-${spec.index}',
                    style: D.label(Toy.inkStrong),
                  ),
                  const SizedBox(width: D.s3),
                  StarRow(earned: stars, size: 15),
                ],
              ),
            ),
            const Spacer(),
            // The multiplier only appears once a chain is actually running, so
            // the pre-tap screen stays as clean as the reference art.
            AnimatedOpacity(
              opacity: reacting && rt.tracker.chainLength > 1 ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: D.s4,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Toy.yellow,
                  borderRadius: BorderRadius.circular(D.rPill),
                  boxShadow: D.chip,
                ),
                child: Text(
                  '${multiplier.toStringAsFixed(1)}x',
                  style: D.label(Toy.inkStrong),
                ),
              ),
            ),
            const SizedBox(width: D.s3),
            AnimatedOpacity(
              opacity: reacting ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: ToyIconButton(
                icon: Icons.refresh_rounded,
                onTap: reacting ? onRestart : null,
                tooltip: 'Restart',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The only instruction the game ever gives, and it disappears on first tap.
class _TapPrompt extends StatelessWidget {
  const _TapPrompt({required this.rt});
  final LevelRuntime rt;

  @override
  Widget build(BuildContext context) {
    final int n = rt.starters.length;
    return Positioned(
      left: 0,
      right: 0,
      bottom: D.s6,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: D.s5, vertical: D.s3),
          decoration: BoxDecoration(
            color: Toy.white,
            borderRadius: BorderRadius.circular(D.rPill),
            boxShadow: D.chip,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.touch_app_rounded, color: Toy.blue, size: 20),
              const SizedBox(width: D.s2),
              Text(
                n > 1 ? 'Tap one to start' : 'Tap to start',
                style: D.label(Toy.inkStrong),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void unawaited(Future<void> f) {}
