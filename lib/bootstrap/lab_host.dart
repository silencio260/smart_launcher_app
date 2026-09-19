import 'package:genrevibes_app_rating/genrevibes_app_rating.dart';
import 'package:genrevibes_devtools/genrevibes_devtools.dart';
import 'package:genrevibes_engagement/genrevibes_engagement.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/core/analytics/dev_event_catalogue.dart';

/// Describes the running launcher to Kit Lab.
///
/// Every field is an instance this startup attempt already owns: the Lab
/// inspects and drives the live modules, it never constructs a second copy of
/// one. A module the launcher does not use is simply absent, which the Lab
/// reports as "not connected" rather than as a fault.
DevToolsHost buildLabHost(AppRuntime runtime) {
  return DevToolsHost(
    kit: runtime.coordinator,
    catalogue: LauncherEventCatalogue.catalogue,
    logger: runtime.logger,
    eventLog: runtime.eventLog,
    analytics: runtime.analytics,
    sessionReplay: runtime.replayPolicy,
    remoteConfig: runtime.remoteConfig,
    remoteConfigSchema: runtime.remoteConfigSchema,
    identity: runtime.identity,
    developerAccess: runtime.developerAccess,
    retention: runtime.retention,
    crash: runtime.crash,
    feedback: runtime.feedback,
    rating: runtime.rating,
    store: runtime.store,
    storageKeys: _storageGroups,
  );
}

/// Keys worth showing in the storage inspector, with the app-owned keys they
/// replaced so an upgraded install can be checked for carried-over history.
const _storageGroups = <DevStorageGroup>[
  DevStorageGroup(
    title: 'Retention',
    entries: <DevStorageEntry>[
      DevStorageEntry(
        key: EngagementKeys.installedAt,
        legacyKey: 'first_install_date',
        label: 'Installed at',
      ),
      DevStorageEntry(
        key: EngagementKeys.lastOpenedAt,
        legacyKey: 'last_open_date',
        label: 'Last opened at',
      ),
      DevStorageEntry(
        key: EngagementKeys.totalOpens,
        legacyKey: 'total_app_opens',
        label: 'Total opens',
      ),
      DevStorageEntry(
        key: EngagementKeys.sessionTimestamps,
        legacyKey: 'session_timestamps',
        label: 'Session timestamps',
      ),
      DevStorageEntry(
        key: EngagementKeys.dailyOpenDates,
        legacyKey: 'daily_open_dates',
        label: 'Active dates',
      ),
      DevStorageEntry(key: 'total_sessions', label: 'Lifetime sessions'),
    ],
  ),
  DevStorageGroup(
    title: 'Rating',
    entries: <DevStorageEntry>[
      DevStorageEntry(key: RatingKeys.optedOut, label: 'Opted out'),
      DevStorageEntry(key: RatingKeys.lastPromptedAt, label: 'Last prompted'),
    ],
  ),
  DevStorageGroup(
    title: 'Privacy',
    entries: <DevStorageEntry>[
      DevStorageEntry(
        key: 'launcher.analytics_consent.v1',
        label: 'Analytics consent',
      ),
    ],
  ),
];
