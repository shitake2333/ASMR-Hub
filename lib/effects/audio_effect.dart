import 'package:asmr_hub/effects/audio_parameter.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';

abstract class AudioEffect {
  final String id;
  final LocalizedStringBuilder nameBuilder;
  final LocalizedStringBuilder descBuilder;
  bool isEnabled;
  final List<AudioParameter> parameters;

  AudioEffect({
    required this.id,
    required this.nameBuilder,
    required this.descBuilder,
    this.isEnabled = false,
    this.parameters = const [],
  });

  String getName(AppLocalizations l10n) => nameBuilder(l10n);
  String getDescription(AppLocalizations l10n) => descBuilder(l10n);

  /// Returns the mpv `af` filter-chain segment for this effect (e.g.
  /// `lavfi=[alimiter=limit=0.8]`), or null when the effect is disabled.
  /// The provider joins enabled effects with commas to build the `af`
  /// property value passed to libmpv.
  String? buildAfChain();
}
