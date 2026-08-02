import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-level best result.
class LevelProgress {
  LevelProgress({
    this.stars = 0,
    this.bestScore = 0,
    this.bestChain = 0,
    this.bestTime = 0,
    this.attempts = 0,
    this.bonuses = const <String>[],
  });

  int stars;
  int bestScore;
  int bestChain;
  double bestTime;
  int attempts;
  List<String> bonuses;

  bool get completed => stars > 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
    's': stars,
    'p': bestScore,
    'c': bestChain,
    't': bestTime,
    'a': attempts,
    'b': bonuses,
  };

  static LevelProgress fromJson(Map<String, dynamic> j) => LevelProgress(
    stars: (j['s'] as num?)?.toInt() ?? 0,
    bestScore: (j['p'] as num?)?.toInt() ?? 0,
    bestChain: (j['c'] as num?)?.toInt() ?? 0,
    bestTime: (j['t'] as num?)?.toDouble() ?? 0,
    attempts: (j['a'] as num?)?.toInt() ?? 0,
    bonuses: ((j['b'] as List<dynamic>?) ?? const <dynamic>[])
        .map((dynamic e) => e.toString())
        .toList(),
  );
}

/// All persistent player state: progression, currency, cosmetics, the daily
/// streak and the toy city.
///
/// Everything lives in one JSON blob under a single key. That keeps saves
/// atomic — the game can never come back half-written after a crash mid-save.
class SaveService extends ChangeNotifier {
  SaveService._();
  static final SaveService instance = SaveService._();

  static const String _key = 'crc_save_v1';

  SharedPreferences? _prefs;
  bool _loaded = false;
  bool get loaded => _loaded;

  final Map<String, LevelProgress> levels = <String, LevelProgress>{};
  int coins = 0;
  final Set<String> ownedCosmetics = <String>{
    'cannon_default',
    'car_default',
    'ball_default',
  };
  final Map<String, String> equipped = <String, String>{
    'cannon': 'cannon_default',
    'car': 'car_default',
    'ball': 'ball_default',
    'celebration': 'confetti_default',
  };

  /// Toy City: unlocked landmark ids.
  final Set<String> cityUnlocks = <String>{};

  /// Daily challenge.
  int dailyStreak = 0;
  String? lastDailyDay;
  int dailyBestScore = 0;

  /// Reaction Lab.
  int labBestScore = 0;
  int labBestChain = 0;
  bool labUnlocked = false;

  int get totalStars =>
      levels.values.fold(0, (int a, LevelProgress b) => a + b.stars);
  int get levelsCompleted =>
      levels.values.where((LevelProgress p) => p.completed).length;

  LevelProgress progressFor(String id) =>
      levels[id] ?? (levels[id] = LevelProgress());

  bool isCompleted(String id) => levels[id]?.completed ?? false;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final String? raw = _prefs!.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        _apply(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // A corrupt save should cost the player their progress, not the
        // ability to launch the game.
        _reset();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  void _apply(Map<String, dynamic> j) {
    levels.clear();
    final Map<String, dynamic> l =
        (j['levels'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    l.forEach((String k, dynamic v) {
      levels[k] = LevelProgress.fromJson(v as Map<String, dynamic>);
    });
    coins = (j['coins'] as num?)?.toInt() ?? 0;

    ownedCosmetics
      ..clear()
      ..addAll(
        ((j['owned'] as List<dynamic>?) ?? const <dynamic>[]).map(
          (dynamic e) => e.toString(),
        ),
      );
    ownedCosmetics.addAll(<String>[
      'cannon_default',
      'car_default',
      'ball_default',
    ]);

    final Map<String, dynamic> eq =
        (j['equipped'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    eq.forEach((String k, dynamic v) => equipped[k] = v.toString());

    cityUnlocks
      ..clear()
      ..addAll(
        ((j['city'] as List<dynamic>?) ?? const <dynamic>[]).map(
          (dynamic e) => e.toString(),
        ),
      );

    dailyStreak = (j['streak'] as num?)?.toInt() ?? 0;
    lastDailyDay = j['lastDaily'] as String?;
    dailyBestScore = (j['dailyBest'] as num?)?.toInt() ?? 0;
    labBestScore = (j['labScore'] as num?)?.toInt() ?? 0;
    labBestChain = (j['labChain'] as num?)?.toInt() ?? 0;
    labUnlocked = j['labUnlocked'] == true;
  }

  void _reset() {
    levels.clear();
    coins = 0;
    cityUnlocks.clear();
    dailyStreak = 0;
    lastDailyDay = null;
    dailyBestScore = 0;
    labBestScore = 0;
    labBestChain = 0;
    labUnlocked = false;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'levels': levels.map(
      (String k, LevelProgress v) => MapEntry<String, dynamic>(k, v.toJson()),
    ),
    'coins': coins,
    'owned': ownedCosmetics.toList()..sort(),
    'equipped': equipped,
    'city': cityUnlocks.toList()..sort(),
    'streak': dailyStreak,
    'lastDaily': lastDailyDay,
    'dailyBest': dailyBestScore,
    'labScore': labBestScore,
    'labChain': labBestChain,
    'labUnlocked': labUnlocked,
  };

  Future<void> save() async {
    final SharedPreferences? p = _prefs;
    if (p == null) return;
    await p.setString(_key, jsonEncode(toJson()));
  }

  // --------------------------------------------------------------- mutation
  /// Records an attempt. Only improvements are kept, so a worse retry can
  /// never take stars away.
  Future<void> recordResult(
    String levelId, {
    required int stars,
    required int score,
    required int chain,
    required double time,
    required int coinsEarned,
    required List<String> bonuses,
    required bool completed,
  }) async {
    final LevelProgress p = progressFor(levelId);
    p.attempts++;
    if (completed) {
      p.stars = math.max(p.stars, stars);
      p.bestScore = math.max(p.bestScore, score);
      p.bestChain = math.max(p.bestChain, chain);
      p.bestTime = p.bestTime == 0 ? time : math.min(p.bestTime, time);
      final Set<String> merged = <String>{...p.bonuses, ...bonuses};
      p.bonuses = merged.toList()..sort();
      coins += coinsEarned;
    }
    if (!labUnlocked && levelsCompleted >= 10) labUnlocked = true;
    notifyListeners();
    await save();
  }

  Future<void> unlockCity(String id) async {
    if (cityUnlocks.add(id)) {
      notifyListeners();
      await save();
    }
  }

  bool canAfford(int price) => coins >= price;

  Future<bool> buy(String cosmeticId, int price) async {
    if (ownedCosmetics.contains(cosmeticId)) return true;
    if (coins < price) return false;
    coins -= price;
    ownedCosmetics.add(cosmeticId);
    notifyListeners();
    await save();
    return true;
  }

  Future<void> equip(String slot, String cosmeticId) async {
    if (!ownedCosmetics.contains(cosmeticId)) return;
    equipped[slot] = cosmeticId;
    notifyListeners();
    await save();
  }

  Future<void> recordDaily(String dayKey, int score) async {
    if (lastDailyDay == dayKey) {
      dailyBestScore = math.max(dailyBestScore, score);
    } else {
      final String? prev = lastDailyDay;
      dailyStreak = (prev != null && _isYesterday(prev, dayKey))
          ? dailyStreak + 1
          : 1;
      lastDailyDay = dayKey;
      dailyBestScore = score;
      coins += 40 + dailyStreak * 5;
    }
    notifyListeners();
    await save();
  }

  Future<void> recordLab(int score, int chain) async {
    labBestScore = math.max(labBestScore, score);
    labBestChain = math.max(labBestChain, chain);
    coins += 5 + chain ~/ 4;
    notifyListeners();
    await save();
  }

  static bool _isYesterday(String prev, String today) {
    final DateTime? a = DateTime.tryParse(prev);
    final DateTime? b = DateTime.tryParse(today);
    if (a == null || b == null) return false;
    return b.difference(a).inDays == 1;
  }

  /// Wipes all progress, from the settings screen.
  Future<void> resetAll() async {
    _reset();
    ownedCosmetics
      ..clear()
      ..addAll(<String>['cannon_default', 'car_default', 'ball_default']);
    equipped
      ..clear()
      ..addAll(<String, String>{
        'cannon': 'cannon_default',
        'car': 'car_default',
        'ball': 'ball_default',
        'celebration': 'confetti_default',
      });
    notifyListeners();
    await save();
  }

  /// Test hook.
  @visibleForTesting
  Future<void> resetForTest(SharedPreferences p) async {
    _prefs = p;
    _reset();
    _loaded = true;
  }
}
