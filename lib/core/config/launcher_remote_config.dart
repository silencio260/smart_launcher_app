import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:genrevibes_remote_config/genrevibes_remote_config.dart';
import 'package:genrevibes_remote_policy/genrevibes_remote_policy.dart';

import 'launcher_policy_keys.dart';

/// App-owned Firebase template also supplies the bundled, typed defaults.
abstract final class LauncherRemoteConfig {
  static const assetPath = 'config/remote_config.json';

  static Future<RemoteConfigSchema> loadSchema() async {
    final template =
        jsonDecode(await rootBundle.loadString(assetPath))
            as Map<String, dynamic>;
    final parameters = <String, dynamic>{};
    void addParameters(Map<String, dynamic> entries) {
      for (final entry in entries.entries) {
        if (parameters.containsKey(entry.key)) {
          throw FormatException('Duplicate Remote Config key: ${entry.key}');
        }
        parameters[entry.key] = entry.value;
      }
    }

    addParameters(template['parameters'] as Map<String, dynamic>? ?? {});
    final groups = template['parameterGroups'] as Map<String, dynamic>? ?? {};
    for (final group in groups.values) {
      addParameters(
        (group as Map<String, dynamic>)['parameters'] as Map<String, dynamic>,
      );
    }
    final base = PortfolioRemoteConfigSchema.build(
      appKeys: LauncherPolicyKeys.all,
    );
    for (final name in parameters.keys) {
      if (!base.byName.containsKey(name)) {
        throw FormatException('Remote Config key has no typed schema: $name');
      }
    }
    return RemoteConfigSchema(
      base.keys.map((key) {
        final parameter = parameters[key.name] as Map<String, dynamic>?;
        if (parameter == null) {
          throw FormatException(
            'Missing bundled Remote Config key: ${key.name}',
          );
        }
        final defaults = parameter['defaultValue'] as Map<String, dynamic>?;
        final value = key.tryDecode(defaults?['value']);
        if (value == null) {
          throw FormatException(
            'Invalid bundled Remote Config value: ${key.name}',
          );
        }
        return RemoteConfigKey<Object?>(
          name: key.name,
          defaultValue: value,
          codec: key.codec,
          isValid: key.isValid,
        );
      }),
    );
  }
}
