import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import '../providers/effects_provider.dart';
import '../effects/audio_parameter.dart';

class EffectsList extends StatelessWidget {
  final ScrollController? controller;

  const EffectsList({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    final effectsProvider = context.watch<EffectsProvider>();
    final effects = effectsProvider.effects;
    final l10n = AppLocalizations.of(context)!;

    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: effects.length,
      itemBuilder: (context, index) {
        final effect = effects[index];

        if (!effect.isEnabled) {
          return ListTile(
            title: Text(effect.getName(l10n)),
            subtitle: Text(effect.getDescription(l10n)),
            leading: Switch(
              value: effect.isEnabled,
              onChanged: (value) {
                context.read<EffectsProvider>().toggleEffect(effect.id);
              },
            ),
            onTap: () {
              context.read<EffectsProvider>().toggleEffect(effect.id);
            },
          );
        }

        return ExpansionTile(
          title: Text(effect.getName(l10n)),
          subtitle: Text(effect.getDescription(l10n)),
          leading: Switch(
            value: effect.isEnabled,
            onChanged: (value) {
              context.read<EffectsProvider>().toggleEffect(effect.id);
            },
          ),
          initiallyExpanded: true,
          children: effect.parameters.map((param) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: _buildParameterControl(context, effect.id, param, l10n),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildParameterControl(
    BuildContext context,
    String effectId,
    AudioParameter param,
    AppLocalizations l10n,
  ) {
    if (param is RangeParameter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${param.getName(l10n)}: ${param.value.toStringAsFixed(1)}'),
          Text(
            param.getDescription(l10n),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            value: param.value,
            min: param.min,
            max: param.max,
            onChanged: (value) {
              context.read<EffectsProvider>().updateParameter(
                effectId,
                param.id,
                value,
              );
            },
          ),
        ],
      );
    } else if (param is BoolParameter) {
      return SwitchListTile(
        title: Text(param.getName(l10n)),
        subtitle: Text(param.getDescription(l10n)),
        value: param.value,
        onChanged: (value) {
          context.read<EffectsProvider>().updateParameter(
            effectId,
            param.id,
            value,
          );
        },
      );
    } else if (param is EnumParameter) {
      return ListTile(
        title: Text(param.getName(l10n)),
        subtitle: Text(param.getDescription(l10n)),
        trailing: DropdownButton<dynamic>(
          value: param.value,
          onChanged: (newValue) {
            if (newValue != null) {
              context.read<EffectsProvider>().updateParameter(
                effectId,
                param.id,
                newValue,
              );
            }
          },
          items: param.values.map<DropdownMenuItem<dynamic>>((value) {
            return DropdownMenuItem<dynamic>(
              value: value,
              child: Text(
                param.labelBuilder(value, l10n),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }).toList(),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
