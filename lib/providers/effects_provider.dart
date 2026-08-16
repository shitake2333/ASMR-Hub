import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:asmr_hub/effects/audio_effect.dart';
import 'package:asmr_hub/effects/audio_parameter.dart';
import 'package:asmr_hub/effects/noise_reduction_effect.dart';
import 'package:asmr_hub/effects/safe_sleep_effect.dart';
import 'package:asmr_hub/services/log_service.dart';

/// Manages audio effects (noise reduction, safe sleep) and translates them
/// into an mpv `af` filter chain applied to the player engine.
class EffectsProvider extends ChangeNotifier {
  /// Whether the platform's libmpv can run the lavfi filters the effects use
  /// (alimiter/lowpass). media_kit's Android build lacks them, so effects are
  /// unavailable there.
  static bool get supported => !Platform.isAndroid;
  final List<AudioEffect> _effects = [
    NoiseReductionEffect(),
    SafeSleepEffect(),
  ];

  /// Called whenever the effective filter chain changes; the owner (player
  /// provider) uses it to push the chain into the mpv engine.
  Future<void> Function(String? chain)? onFilterChainChanged;

  List<AudioEffect> get effects => List.unmodifiable(_effects);

  bool get isAnyEffectEnabled => _effects.any((e) => e.isEnabled);

  bool isEffectEnabled(String id) {
    return _effects
        .firstWhere((e) => e.id == id, orElse: () => NoiseReductionEffect())
        .isEnabled;
  }

  /// The current mpv `af` chain built from enabled effects, or null.
  String? get filterChain {
    final parts = <String>[];
    for (final effect in _effects) {
      if (!effect.isEnabled) continue;
      final chain = effect.buildAfChain();
      if (chain != null && chain.isNotEmpty) parts.add(chain);
    }
    return parts.isEmpty ? null : parts.join(',');
  }

  Future<void> toggleEffect(String id) async {
    final effect = _effects.firstWhere(
      (e) => e.id == id,
      orElse: () => throw Exception('Effect not found'),
    );
    effect.isEnabled = !effect.isEnabled;
    notifyListeners();
    await _applyEffects();
  }

  Future<void> updateParameter(
    String effectId,
    String paramId,
    dynamic value,
  ) async {
    final effect = _effects.firstWhere((e) => e.id == effectId);
    final param = effect.parameters.firstWhere((p) => p.id == paramId);

    if (param is RangeParameter) {
      param.value = value as double;
    } else if (param is BoolParameter) {
      param.value = value as bool;
    } else if (param is EnumParameter) {
      param.value = value;
    }

    notifyListeners();
    if (effect.isEnabled) {
      await _applyEffects();
    }
  }

  Future<void> _applyEffects() async {
    try {
      final chain = filterChain;
      LogService().info('Effects: applying af chain: $chain');
      await onFilterChainChanged?.call(chain);
    } catch (e, stack) {
      LogService().error('Failed to apply effects', e, stack);
    }
  }
}
