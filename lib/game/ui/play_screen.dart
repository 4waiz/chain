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
import 'tutorial.dart';

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

  /// Seconds since the level finished loading, for pacing the coach marks.
  double _sinceLoad = 0;

  /// Live aim preview, recomputed while the player is deciding.
  List<Vector3> _aimArc = const <Vector3>[];
  List<Vector3> _starterGround = const <Vector3>[];
  double _guideTime = 0;
  bool _coachDismissed = false;

  bool get _showCoach =>
      !_coachDismissed &&
      !SaveService.instance.tutorialSeen &&
      widget.mode == PlayMode.campaign;

  /// How close the barrel is to the level's intended line, 0..1.
  double _aimAccuracy = 0;

  /// Refreshes the on-screen guides. The arc is a plain ballistic integration
  /// so it is cheap enough to redo every frame as the barrel sweeps.
  void _refreshGuides(LevelRuntime rt) {
    final List<LevelObject> starters = rt.starters;
    _starterGround = <Vector3>[
      for (final LevelObject s in starters)
        if (s.body != null)
          Vector3(s.body!.position.x, 0.01, s.body!.position.z),
    ];
    final Object? dev = starters.isEmpty ? null : starters.first.device;
    _aimAccuracy = dev is CannonDevice ? dev.accuracy : 1.0;
    _aimArc = starters.isEmpty
        ? const <Vector3>[]
        : rt.previewArc(starters.first.id);
  }

  // ------------------------------------------------------------------ loop
  void _onFrame(double dt) {
    final LevelRuntime? rt = _rt;
    final CameraDirector? dir = _director;
    if (rt == null || dir == null || _paused) return;

    _guideTime += dt;
    AudioService.instance.tick(dt);

    // The opening fly-in runs before the simulation is allowed to start, so
    // the player always sees the untouched set first.
    if (dir.introActive) {
      dir.update(dt, rt, _aspect);
      if (!dir.introActive) _refreshGuides(rt);
      setState(() {});
      return;
    }

    if (rt.phase == RunPhase.inspecting) {
      _sinceLoad += dt;
      // Recomputed every frame: the barrel is sweeping, so the arc has to
      // track it or the preview would be a lie.
      _refreshGuides(rt);
    }

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
  void _skipIntro() {
    final CameraDirector? dir = _director;
    final LevelRuntime? rt = _rt;
    if (dir == null || rt == null || !dir.introActive) return;
    dir.skipIntro();
    _refreshGuides(rt);
    setState(() {});
  }

  void _onTap(Offset local, Size size) {
    final LevelRuntime? rt = _rt;
    if (rt == null || _paused) return;

    // Any tap during the opening shot cuts it short, so a player who already
    // knows the level never waits through it.
    if (_director?.introActive ?? false) {
      _skipIntro();
      return;
    }

    if (rt.phase != RunPhase.inspecting) return;

    final Vector3 o = Vector3.zero();
    final Vector3 d = Vector3.zero();
    _camera.screenRay(local.dx, local.dy, size.width, size.height, o, d);

    String? started = rt.tapStarter(o, d);

    // With a single starter the decision is *when*, not *what* — so the whole
    // screen fires it. Hunting for a small cannon with a fingertip adds
    // difficulty in the one place the game should have none.
    if (started == null && rt.starters.length == 1) {
      started = rt.start(rt.starters.first.id);
    }

    if (started != null) {
      AudioService.instance.haptic(HapticStrength.medium);
      _aimArc = const <Vector3>[];
      _starterGround = const <Vector3>[];
      unawaited(SaveService.instance.markTutorialSeen());
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
    _sinceLoad = 0;
    // Retry goes straight back to the playable framing. Replaying the fly-in
    // every attempt would fight the brief's under-two-second retry.
    _director?.establish(rt.bounds, _aspect);
    _refreshGuides(rt);
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
                      final LevelObject? first = rt.starters.isEmpty
                          ? null
                          : rt.starters.first;
                      _director!.startIntro(
                        rt.bounds,
                        first?.body?.position,
                        c.maxWidth / c.maxHeight,
                      );
                      if (!_director!.introActive) _refreshGuides(rt);
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
                      overlay: (ui.Canvas canvas, Size size) {
                        // Guides sit under the particles so a burst never
                        // hides the arc.
                        if (rt.phase == RunPhase.inspecting &&
                            !_director!.introActive) {
                          _fx.drawStarterRings(
                            canvas,
                            size,
                            _camera,
                            _starterGround,
                            _guideTime,
                          );
                          _fx.drawAimArc(
                            canvas,
                            size,
                            _camera,
                            _aimArc,
                            _guideTime,
                            accuracy: _aimAccuracy,
                          );
                        }
                        _fx.draw(canvas, size, _camera);
                      },
                    );
                  },
                ),
              ),
              // The HUD stays out of the way until the opening shot lands.
              if (!_director!.introActive)
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
              if (_director!.introActive) _SkipIntro(onSkip: _skipIntro),
              if (rt.phase == RunPhase.inspecting && !_director!.introActive)
                _TapPrompt(rt: rt),
              if (_showCoach && !_director!.introActive && !_paused)
                CoachOverlay(
                  step: CoachOverlay.stepFor(
                    rt.phase,
                    _sinceLoad,
                    rt.tracker.chainLength,
                  ),
                  chainLength: rt.tracker.chainLength,
                  onDismiss: () {
                    AudioService.instance.uiTap();
                    unawaited(SaveService.instance.markTutorialSeen());
                    setState(() => _coachDismissed = true);
                  },
                ),
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

/// Corner affordance during the opening fly-in.
class _SkipIntro extends StatelessWidget {
  const _SkipIntro({required this.onSkip});
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: D.s4,
      top: D.s3,
      child: GestureDetector(
        onTap: onSkip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: D.s4, vertical: 9),
          decoration: BoxDecoration(
            color: Toy.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(D.rPill),
            boxShadow: D.chip,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Skip', style: D.label(Toy.inkSoft)),
              const SizedBox(width: 4),
              const Icon(
                Icons.fast_forward_rounded,
                size: 17,
                color: Toy.inkSoft,
              ),
            ],
          ),
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
                n > 1 ? 'Tap a starter to fire' : 'Tap to fire',
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
