import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeatureHiveBoxes {
  static const featureSettings = 'feature_settings_box';
  static const clockAlarms = 'clock_alarms_box';
  static const clockTimerPresets = 'clock_timer_presets_box';
  static const clockTimerState = 'clock_timer_state_box';
  static const clockStopwatchState = 'clock_stopwatch_state_box';
  static const clockWorldCities = 'clock_world_cities_box';
  static const vaultAlbums = 'vault_albums_box';
  static const vaultItems = 'vault_items_box';
  static const appLockPolicy = 'app_lock_policy_box';
  static const hiddenSpace = 'hidden_space_box';
  static const intruderAttempts = 'intruder_attempts_box';

  static const sensitive = {
    vaultAlbums,
    vaultItems,
    appLockPolicy,
    hiddenSpace,
    intruderAttempts,
  };
}

class FeatureHiveStore {
  FeatureHiveStore._();

  static const _security =
      MethodChannel('com.genrevibes.smartlauncher/security');
  static const _fallbackKey = 'feature_hive_fallback_key_v1';

  static late final HiveAesCipher _sensitiveCipher;

  static Future<void> init() async {
    await Hive.initFlutter();
    final key = await _loadSensitiveKey();
    _sensitiveCipher = HiveAesCipher(key);
    await Future.wait([
      _open(FeatureHiveBoxes.featureSettings),
      _open(FeatureHiveBoxes.clockAlarms),
      _open(FeatureHiveBoxes.clockTimerPresets),
      _open(FeatureHiveBoxes.clockTimerState),
      _open(FeatureHiveBoxes.clockStopwatchState),
      _open(FeatureHiveBoxes.clockWorldCities),
      _open(FeatureHiveBoxes.vaultAlbums),
      _open(FeatureHiveBoxes.vaultItems),
      _open(FeatureHiveBoxes.appLockPolicy),
      _open(FeatureHiveBoxes.hiddenSpace),
      _open(FeatureHiveBoxes.intruderAttempts),
    ]);
  }

  static Box box(String name) => Hive.box(name);

  static Future<Box> _open(String name) {
    final cipher =
        FeatureHiveBoxes.sensitive.contains(name) ? _sensitiveCipher : null;
    return Hive.openBox(name, encryptionCipher: cipher);
  }

  static Future<Uint8List> _loadSensitiveKey() async {
    try {
      final encoded = await _security.invokeMethod<String>('getHiveAesKey');
      if (encoded != null && encoded.isNotEmpty) {
        final bytes = base64Decode(encoded);
        if (bytes.length == 32) return Uint8List.fromList(bytes);
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_fallbackKey);
    if (saved != null) {
      final bytes = base64Decode(saved);
      if (bytes.length == 32) return Uint8List.fromList(bytes);
    }
    final key = Uint8List(32);
    final random = Random.secure();
    for (var i = 0; i < key.length; i++) {
      key[i] = random.nextInt(256);
    }
    await prefs.setString(_fallbackKey, base64Encode(key));
    return key;
  }
}
