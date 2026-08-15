import 'package:asmr_hub/l10n/app_localizations.dart';

typedef LocalizedStringBuilder = String Function(AppLocalizations l10n);

abstract class AudioParameter<T> {
  final String id;
  final LocalizedStringBuilder nameBuilder;
  final LocalizedStringBuilder descBuilder;
  T value;

  AudioParameter({
    required this.id,
    required this.nameBuilder,
    required this.descBuilder,
    required this.value,
  });

  String getName(AppLocalizations l10n) => nameBuilder(l10n);
  String getDescription(AppLocalizations l10n) => descBuilder(l10n);
}

class RangeParameter extends AudioParameter<double> {
  final double min;
  final double max;

  RangeParameter({
    required super.id,
    required super.nameBuilder,
    required super.descBuilder,
    required super.value,
    required this.min,
    required this.max,
  });
}

class BoolParameter extends AudioParameter<bool> {
  BoolParameter({
    required super.id,
    required super.nameBuilder,
    required super.descBuilder,
    required super.value,
  });
}

class EnumParameter<T> extends AudioParameter<T> {
  final List<T> values;
  final String Function(T, AppLocalizations) labelBuilder;

  EnumParameter({
    required super.id,
    required super.nameBuilder,
    required super.descBuilder,
    required super.value,
    required this.values,
    required this.labelBuilder,
  });
}
