import 'package:asmr_hub/effects/audio_effect.dart';
import 'package:asmr_hub/effects/audio_parameter.dart';

class NoiseReductionEffect extends AudioEffect {
  NoiseReductionEffect()
    : super(
        id: 'noise_reduction',
        nameBuilder: (l10n) => l10n.effectNoiseReduction,
        descBuilder: (l10n) => l10n.effectNoiseReductionDesc,
        parameters: [
          RangeParameter(
            id: 'cutoff',
            nameBuilder: (l10n) => l10n.paramCutoff,
            descBuilder: (l10n) => l10n.paramCutoffDesc,
            value: 3000.0,
            min: 500.0,
            max: 8000.0,
          ),
          RangeParameter(
            id: 'resonance',
            nameBuilder: (l10n) => l10n.paramResonance,
            descBuilder: (l10n) => l10n.paramResonanceDesc,
            value: 0.5,
            min: 0.1,
            max: 2.0,
          ),
        ],
      );

  @override
  String? buildAfChain() {
    if (!isEnabled) return null;

    final cutoff =
        (parameters.firstWhere((p) => p.id == 'cutoff') as RangeParameter)
            .value;

    // Low-pass filter to reduce high-frequency noise. mpv/ffmpeg's lowpass
    // filter takes a cutoff frequency (Hz) and a Q factor.
    return 'lavfi=[lowpass=f=${cutoff.toStringAsFixed(0)}:poles=2]';
  }
}
