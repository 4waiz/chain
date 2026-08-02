import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../game/play/devices.dart';
import 'settings.dart';

/// Sound, music and haptics.
///
/// Two things matter for a chain-reaction game. First, dozens of impacts can
/// land in the same second, so playback goes through a small pool of players
/// and a per-sound rate limit — otherwise a domino run turns into a wall of
/// noise. Second, the brief asks for intensity that *grows* with the chain, so
/// [chainIntensity] lifts pitch and volume as the reaction lengthens.
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  static const int _poolSize = 8;
  final List<AudioPlayer> _pool = <AudioPlayer>[];
  int _next = 0;

  AudioPlayer? _music;
  bool _ready = false;
  bool _musicPlaying = false;

  /// 0 at the start of a reaction, 1 at a long chain. Drives volume and pitch.
  double chainIntensity = 0.0;

  final Map<String, int> _lastPlayedMs = <String, int>{};
  int _clockMs = 0;

  /// Minimum gap between two plays of the same sound, in milliseconds.
  static const Map<String, int> _minGap = <String, int>{
    'domino_impact': 45,
    'block_break': 90,
    'glass_break': 110,
    'coin_pickup': 70,
  };

  Future<void> init() async {
    if (_ready) return;
    try {
      for (int i = 0; i < _poolSize; i++) {
        final AudioPlayer p = AudioPlayer(playerId: 'sfx$i');
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        _pool.add(p);
      }
      _music = AudioPlayer(playerId: 'music');
      await _music!.setReleaseMode(ReleaseMode.loop);
      _ready = true;
    } catch (e) {
      // Audio is a nice-to-have; a device with no working audio backend must
      // still be able to play the game.
      debugPrint('AudioService: init failed, continuing muted ($e)');
      _ready = false;
    }
  }

  /// Advances the internal clock. Called once per frame by the play screen so
  /// rate limiting does not need a wall clock.
  void tick(double dt) => _clockMs += (dt * 1000).round();

  bool _allowed(String name) {
    final int gap = _minGap[name] ?? 25;
    final int last = _lastPlayedMs[name] ?? -100000;
    if (_clockMs - last < gap) return false;
    _lastPlayedMs[name] = _clockMs;
    return true;
  }

  Future<void> play(
    String name, {
    double volume = 1.0,
    double rate = 1.0,
  }) async {
    if (!_ready || !Settings.instance.sound) return;
    if (!_allowed(name)) return;
    try {
      final AudioPlayer p = _pool[_next];
      _next = (_next + 1) % _pool.length;
      await p.stop();
      await p.setVolume(volume.clamp(0.0, 1.0));
      await p.setPlaybackRate(rate.clamp(0.5, 2.0));
      await p.play(AssetSource('audio/$name.wav'));
    } catch (_) {
      // A dropped sound must never interrupt a reaction.
    }
  }

  Future<void> startMusic() async {
    if (!_ready || !Settings.instance.music || _musicPlaying) return;
    try {
      await _music!.setVolume(0.32);
      await _music!.play(AssetSource('audio/music_loop.wav'));
      _musicPlaying = true;
    } catch (_) {}
  }

  Future<void> stopMusic() async {
    if (!_ready || !_musicPlaying) return;
    try {
      await _music!.stop();
      _musicPlaying = false;
    } catch (_) {}
  }

  Future<void> syncMusic() async {
    if (Settings.instance.music) {
      await startMusic();
    } else {
      await stopMusic();
    }
  }

  Future<void> pauseAll() async {
    if (!_ready) return;
    try {
      await _music?.pause();
      for (final AudioPlayer p in _pool) {
        await p.stop();
      }
    } catch (_) {}
  }

  Future<void> resumeMusic() async {
    if (!_ready || !Settings.instance.music) return;
    try {
      await _music?.resume();
    } catch (_) {}
  }

  // ------------------------------------------------------------- gameplay
  /// Maps a gameplay signal onto a sound, scaling with the chain intensity.
  void onSignal(GameSignal s) {
    final double i = chainIntensity.clamp(0.0, 1.0);
    // As the chain grows, hits get a little louder and a little brighter.
    final double vol = 0.55 + 0.40 * i;
    final double rate = 0.94 + 0.16 * i;

    switch (s.kind) {
      case SignalKind.cannonFire:
        play('cannon_fire', volume: 0.95);
        haptic(HapticStrength.medium);
      case SignalKind.impact:
        final double strength = s.strength.clamp(0.0, 1.0);
        if (strength < 0.02) return;
        play(
          'domino_impact',
          volume: (0.28 + strength * 1.6).clamp(0.15, 1.0) * vol,
          rate: rate * (0.92 + strength * 0.3),
        );
        if (strength > 0.30) haptic(HapticStrength.light);
      case SignalKind.buttonPress:
        play('button_press', volume: 0.9);
        haptic(HapticStrength.medium);
      case SignalKind.springLaunch:
        play('spring', volume: 0.85, rate: rate);
      case SignalKind.fanOn:
        play('fan', volume: 0.5);
      case SignalKind.balloonPop:
        play('balloon', volume: 0.9);
        haptic(HapticStrength.light);
      case SignalKind.magnetPulse:
        play('magnet', volume: 0.7);
      case SignalKind.spark:
        play('electricity', volume: 0.7);
      case SignalKind.breakGlass:
        play('glass_break', volume: 0.85);
        haptic(HapticStrength.medium);
      case SignalKind.breakBlock:
        play('block_break', volume: 0.85);
        haptic(HapticStrength.medium);
      case SignalKind.splash:
        play('water_splash', volume: 0.8);
      case SignalKind.gearTurn:
        play('gears', volume: 0.55);
      case SignalKind.bridgeMove:
        play('bridge_move', volume: 0.6);
      case SignalKind.bell:
        play('bell', volume: 0.9);
      case SignalKind.flagRaise:
        play('flag', volume: 0.8);
      case SignalKind.chestOpen:
        play('chest_open', volume: 0.9);
      case SignalKind.targetReached:
        play('success', volume: 1.0);
        haptic(HapticStrength.heavy);
      case SignalKind.collect:
        play(s.strength >= 1 ? 'star_reward' : 'coin_pickup', volume: 0.8);
      case SignalKind.celebrate:
        play('level_complete', volume: 1.0);
        play('fireworks', volume: 0.7);
        haptic(HapticStrength.heavy);
    }
  }

  void updateChain(int chainLength, int par) {
    chainIntensity = math.min(1.0, chainLength / math.max(4, par).toDouble());
  }

  // -------------------------------------------------------------- haptics
  void haptic(HapticStrength s) {
    if (!Settings.instance.haptics) return;
    switch (s) {
      case HapticStrength.light:
        HapticFeedback.lightImpact();
      case HapticStrength.medium:
        HapticFeedback.mediumImpact();
      case HapticStrength.heavy:
        HapticFeedback.heavyImpact();
      case HapticStrength.selection:
        HapticFeedback.selectionClick();
    }
  }

  void uiTap() {
    play('ui_tap', volume: 0.7);
    haptic(HapticStrength.selection);
  }

  Future<void> dispose() async {
    for (final AudioPlayer p in _pool) {
      await p.dispose();
    }
    await _music?.dispose();
    _pool.clear();
    _ready = false;
  }
}

enum HapticStrength { light, medium, heavy, selection }
