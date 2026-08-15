import 'package:asmr_hub/effects/audio_effect.dart';
import 'package:asmr_hub/effects/audio_parameter.dart';

class SafeSleepEffect extends AudioEffect {
  SafeSleepEffect()
    : super(
        id: 'safe_sleep',
        nameBuilder: (l10n) => l10n.effectSafeSleep,
        descBuilder: (l10n) => l10n.effectSafeSleepDesc,
        parameters: [
          BoolParameter(
            id: 'limiter_enabled',
            nameBuilder: (l10n) => l10n.paramEnableLimiter,
            descBuilder: (l10n) => l10n.paramEnableLimiterDesc,
            value: true,
          ),
          RangeParameter(
            id: 'cutoff',
            nameBuilder: (l10n) => l10n.paramSoftness,
            descBuilder: (l10n) => l10n.paramSoftnessDesc,
            value: 1000.0,
            min: 200.0,
            max: 4000.0,
          ),
        ],
      );

  @override
  String? buildAfChain() {
    if (!isEnabled) return null;

    final limiterEnabled =
        (parameters.firstWhere((p) => p.id == 'limiter_enabled')
                as BoolParameter)
            .value;
    final cutoff =
        (parameters.firstWhere((p) => p.id == 'cutoff') as RangeParameter)
            .value;

    final filters = <String>[];
    // Limiter (soft clip) to protect hearing during sleep.
    if (limiterEnabled) {
      filters.add('lavfi=[alimiter=limit=0.7:level=false]');
    }
    // Gentle low-pass to soften harsh highs.
    filters.add('lavfi=[lowpass=f=${cutoff.toStringAsFixed(0)}:poles=1]');
    return filters.join(',');
  }
}
