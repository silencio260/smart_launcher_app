import 'package:genrevibes_remote_config/genrevibes_remote_config.dart';

/// Remote-config keys only the launcher defines, added to the shared
/// portfolio schema through `appKeys`.
abstract final class LauncherPolicyKeys {
  static const _bool = RemoteConfigBoolCodec();

  /// When true, the launcher can't be used until it is the phone's default
  /// home app: set-as-default has no way out, and home is blocked whenever
  /// another launcher takes the role back. Defaults to false.
  static const forceDefaultLauncher = RemoteConfigKey<bool>(
    name: 'launcher_force_default',
    defaultValue: false,
    codec: _bool,
  );

  /// Every key, widened for a schema.
  static List<RemoteConfigKey<Object?>> get all => <RemoteConfigKey<Object?>>[
        remoteConfigKey(forceDefaultLauncher),
      ];
}
