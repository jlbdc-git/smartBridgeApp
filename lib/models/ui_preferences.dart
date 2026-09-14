import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI/voice preferences model (extracted from the original main.dart).

@immutable
class AppUiPreferences {
  const AppUiPreferences({
    this.themeMode = ThemeMode.system,
    this.textScale = 1.0,
    this.highContrast = false,
    this.reduceMotion = false,
    this.hapticsEnabled = true,
    this.autoSpeakSigns = false,
    this.ttsRate = 0.5,
    this.ttsPitch = 1.0,
    this.ttsVolume = 1.0,
    this.recognitionThreshold = 35.0,
    this.historyConfidenceThreshold = 60.0,
    this.frameStride = 2,
  });

  static const String _themeModeKey = 'pref_theme_mode';
  static const String _textScaleKey = 'pref_text_scale';
  static const String _highContrastKey = 'pref_high_contrast';
  static const String _reduceMotionKey = 'pref_reduce_motion';
  static const String _hapticsKey = 'pref_haptics_enabled';
  static const String _autoSpeakSignsKey = 'pref_auto_speak_signs';
  static const String _ttsRateKey = 'pref_tts_rate';
  static const String _ttsPitchKey = 'pref_tts_pitch';
  static const String _ttsVolumeKey = 'pref_tts_volume';
  static const String _recognitionThresholdKey = 'pref_recognition_threshold';
  static const String _historyThresholdKey =
      'pref_history_confidence_threshold';
  static const String _frameStrideKey = 'pref_frame_stride';

  final ThemeMode themeMode;
  final double textScale;
  final bool highContrast;
  final bool reduceMotion;
  final bool hapticsEnabled;
  final bool autoSpeakSigns;
  final double ttsRate;
  final double ttsPitch;
  final double ttsVolume;
  final double recognitionThreshold;
  final double historyConfidenceThreshold;
  final int frameStride;

  AppUiPreferences copyWith({
    ThemeMode? themeMode,
    double? textScale,
    bool? highContrast,
    bool? reduceMotion,
    bool? hapticsEnabled,
    bool? autoSpeakSigns,
    double? ttsRate,
    double? ttsPitch,
    double? ttsVolume,
    double? recognitionThreshold,
    double? historyConfidenceThreshold,
    int? frameStride,
  }) {
    return AppUiPreferences(
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
      highContrast: highContrast ?? this.highContrast,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      autoSpeakSigns: autoSpeakSigns ?? this.autoSpeakSigns,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsPitch: ttsPitch ?? this.ttsPitch,
      ttsVolume: ttsVolume ?? this.ttsVolume,
      recognitionThreshold: recognitionThreshold ?? this.recognitionThreshold,
      historyConfidenceThreshold:
          historyConfidenceThreshold ?? this.historyConfidenceThreshold,
      frameStride: frameStride ?? this.frameStride,
    );
  }

  factory AppUiPreferences.fromSharedPreferences(SharedPreferences prefs) {
    final String mode = prefs.getString(_themeModeKey) ?? 'system';

    ThemeMode themeMode = ThemeMode.system;
    if (mode == 'light') {
      themeMode = ThemeMode.light;
    } else if (mode == 'dark') {
      themeMode = ThemeMode.dark;
    }

    return AppUiPreferences(
      themeMode: themeMode,
      textScale: (prefs.getDouble(_textScaleKey) ?? 1.0).clamp(0.85, 1.4),
      highContrast: prefs.getBool(_highContrastKey) ?? false,
      reduceMotion: prefs.getBool(_reduceMotionKey) ?? false,
      hapticsEnabled: prefs.getBool(_hapticsKey) ?? true,
      autoSpeakSigns: prefs.getBool(_autoSpeakSignsKey) ?? false,
      ttsRate: (prefs.getDouble(_ttsRateKey) ?? 0.5).clamp(0.1, 1.0),
      ttsPitch: (prefs.getDouble(_ttsPitchKey) ?? 1.0).clamp(0.5, 2.0),
      ttsVolume: (prefs.getDouble(_ttsVolumeKey) ?? 1.0).clamp(0.0, 1.0),
      recognitionThreshold: (prefs.getDouble(_recognitionThresholdKey) ?? 35.0)
          .clamp(10, 95),
      historyConfidenceThreshold:
          (prefs.getDouble(_historyThresholdKey) ?? 60.0).clamp(35, 99),
      frameStride: (prefs.getInt(_frameStrideKey) ?? 2).clamp(1, 5),
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    String mode = 'system';
    if (themeMode == ThemeMode.light) {
      mode = 'light';
    } else if (themeMode == ThemeMode.dark) {
      mode = 'dark';
    }

    await prefs.setString(_themeModeKey, mode);
    await prefs.setDouble(_textScaleKey, textScale);
    await prefs.setBool(_highContrastKey, highContrast);
    await prefs.setBool(_reduceMotionKey, reduceMotion);
    await prefs.setBool(_hapticsKey, hapticsEnabled);
    await prefs.setBool(_autoSpeakSignsKey, autoSpeakSigns);
    await prefs.setDouble(_ttsRateKey, ttsRate);
    await prefs.setDouble(_ttsPitchKey, ttsPitch);
    await prefs.setDouble(_ttsVolumeKey, ttsVolume);
    await prefs.setDouble(_recognitionThresholdKey, recognitionThreshold);
    await prefs.setDouble(_historyThresholdKey, historyConfidenceThreshold);
    await prefs.setInt(_frameStrideKey, frameStride);
  }
}

