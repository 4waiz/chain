import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GraphicsQuality { low, medium, high }

/// User-facing options. Every one of these is read live by the game, so
/// changing a setting takes effect without restarting a level.
class Settings extends ChangeNotifier {
  Settings._();
  static final Settings instance = Settings._();

  SharedPreferences? _prefs;

  bool _sound = true;
  bool _music = true;
  bool _haptics = true;
  bool _reducedMotion = false;
  bool _cameraShake = true;
  GraphicsQuality _quality = GraphicsQuality.high;

  bool get sound => _sound;
  bool get music => _music;
  bool get haptics => _haptics;
  bool get reducedMotion => _reducedMotion;
  bool get cameraShake => _cameraShake && !_reducedMotion;
  GraphicsQuality get quality => _quality;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final SharedPreferences p = _prefs!;
    _sound = p.getBool('sound') ?? true;
    _music = p.getBool('music') ?? true;
    _haptics = p.getBool('haptics') ?? true;
    _reducedMotion = p.getBool('reducedMotion') ?? false;
    _cameraShake = p.getBool('cameraShake') ?? true;
    _quality =
        GraphicsQuality.values[(p.getInt('quality') ??
                GraphicsQuality.high.index)
            .clamp(0, 2)];
    notifyListeners();
  }

  Future<void> _set(String key, Object value) async {
    final SharedPreferences? p = _prefs;
    if (p == null) return;
    if (value is bool) await p.setBool(key, value);
    if (value is int) await p.setInt(key, value);
  }

  set sound(bool v) {
    _sound = v;
    _set('sound', v);
    notifyListeners();
  }

  set music(bool v) {
    _music = v;
    _set('music', v);
    notifyListeners();
  }

  set haptics(bool v) {
    _haptics = v;
    _set('haptics', v);
    notifyListeners();
  }

  set reducedMotion(bool v) {
    _reducedMotion = v;
    _set('reducedMotion', v);
    notifyListeners();
  }

  set cameraShake(bool v) {
    _cameraShake = v;
    _set('cameraShake', v);
    notifyListeners();
  }

  set quality(GraphicsQuality v) {
    _quality = v;
    _set('quality', v.index);
    notifyListeners();
  }

  /// Test hook: swaps in an in-memory store.
  @visibleForTesting
  void attachPrefs(SharedPreferences p) => _prefs = p;
}
