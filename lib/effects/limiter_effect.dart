import 'audio_effect.dart';

class LimiterEffect extends AudioEffect {
  LimiterEffect()
    : super(
        id: 'limiter',
        nameBuilder: (l10n) => l10n.effectLimiter,
        descBuilder: (l10n) => l10n.effectLimiterDesc,
      );

  @override
  String? buildAfChain() {
    if (!isEnabled) return null;
    // Soft limiter: prevents clipping / sudden loud peaks.
    return 'lavfi=[alimiter=limit=0.85:level=false:attack=5:release=50]';
  }
}
