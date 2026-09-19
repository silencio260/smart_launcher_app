import 'package:genrevibes_devtools/genrevibes_devtools.dart';

/// The launcher's real analytics events, as Kit Lab shows and fires them.
///
/// Generated from the catalog that the old in-app analytics debug screen
/// carried, so the Lab lists exactly the events [AppAnalytics] emits. Add an
/// entry here whenever a new event is added to `app_events.dart`.
abstract final class LauncherEventCatalogue {
  /// Every event, grouped as the metric plan groups them.
  static const DevAnalyticsCatalogue catalogue = DevAnalyticsCatalogue(
    events: <DevEventSpec>[
      DevEventSpec(
        name: 'screen_view',
        group: 'Generic',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'screen_name', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'app_open',
        group: 'C0 · Lifecycle & user model',
      ),
      DevEventSpec(
        name: 'first_open',
        group: 'C0 · Lifecycle & user model',
      ),
      DevEventSpec(
        name: 'app_remove',
        group: 'C0 · Lifecycle & user model',
      ),
      DevEventSpec(
        name: 'launcher_set_default',
        group: 'C0 · Lifecycle & user model',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'is_default', kind: DevParamKind.boolean, example: true),
        ],
      ),
      DevEventSpec(
        name: 'app_launched',
        group: 'C1 · Home / workspace',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'source', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'position', kind: DevParamKind.integer, example: 1),
        ],
      ),
      DevEventSpec(
        name: 'workspace_page_changed',
        group: 'C1 · Home / workspace',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'from_index', kind: DevParamKind.integer, example: 1),
          DevParamSpec(name: 'to_index', kind: DevParamKind.integer, example: 1),
          DevParamSpec(name: 'type', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'folder_opened',
        group: 'C1 · Home / workspace',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'item_count', kind: DevParamKind.integer, example: 1),
        ],
      ),
      DevEventSpec(
        name: 'home_edit_mode',
        group: 'C1 · Home / workspace',
      ),
      DevEventSpec(
        name: 'drawer_opened',
        group: 'C1 · Home / workspace',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'open_method', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'app_context_menu_opened',
        group: 'C1 · Home / workspace',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'actions_available', kind: DevParamKind.integer, example: 1),
        ],
      ),
      DevEventSpec(
        name: 'ad_click',
        group: 'Ads',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'ad_type', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'ad_lifecycle',
        group: 'Ads',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'ad_type', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'action', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'result', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'source', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'test_ads', kind: DevParamKind.boolean, example: true),
          DevParamSpec(name: 'ad_unit_id', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'error', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'ad_impression',
        group: 'Ads',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'ad_platform', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'ad_source', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'ad_format', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'ad_unit_name', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'value', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'currency', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'ad_revenue',
        group: 'Ads',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'value', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'currency', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'ad_source', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'ad_unit_id', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'ad_format', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'ad_network', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'search_opened',
        group: 'C2 · Smart search',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'source', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'search_performed',
        group: 'C2 · Smart search',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'query_length', kind: DevParamKind.integer, example: 1),
          DevParamSpec(name: 'result_count', kind: DevParamKind.integer, example: 1),
          DevParamSpec(name: 'has_results', kind: DevParamKind.boolean, example: true),
        ],
      ),
      DevEventSpec(
        name: 'search_result_tapped',
        group: 'C2 · Smart search',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'result_type', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'result_index', kind: DevParamKind.integer, example: 1),
        ],
      ),
      DevEventSpec(
        name: 'search_recent_rerun',
        group: 'C2 · Smart search',
      ),
      DevEventSpec(
        name: 'mini_app_open',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'mini_app', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'secure_auth_attempt',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'mini_app', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'method', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'secure_auth_result',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'mini_app', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'method', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'success', kind: DevParamKind.boolean, example: true),
        ],
      ),
      DevEventSpec(
        name: 'vault_item_imported',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'media_type', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'count', kind: DevParamKind.integer, example: 1),
        ],
      ),
      DevEventSpec(
        name: 'vault_item_exported',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'count', kind: DevParamKind.integer, example: 1),
        ],
      ),
      DevEventSpec(
        name: 'app_lock_toggle',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'enabled', kind: DevParamKind.boolean, example: true),
        ],
      ),
      DevEventSpec(
        name: 'app_lock_challenge_shown',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'strategy', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'app_hider_toggle',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'hidden', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'app_hider_disguise_set',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'disguise_id', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'file_locker_action',
        group: 'C3 · Secure mini-apps',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'action', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'file_type', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'alarm_created',
        group: 'C4 · Clock / alarm',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'repeat', kind: DevParamKind.boolean, example: true),
          DevParamSpec(name: 'has_sound', kind: DevParamKind.boolean, example: true),
        ],
      ),
      DevEventSpec(
        name: 'alarm_edited',
        group: 'C4 · Clock / alarm',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'field_changed', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'alarm_deleted',
        group: 'C4 · Clock / alarm',
      ),
      DevEventSpec(
        name: 'alarm_toggled',
        group: 'C4 · Clock / alarm',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'enabled', kind: DevParamKind.boolean, example: true),
        ],
      ),
      DevEventSpec(
        name: 'alarm_fired',
        group: 'C4 · Clock / alarm',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'snoozed', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'world_clock_added',
        group: 'C4 · Clock / alarm',
      ),
      DevEventSpec(
        name: 'discover_opened',
        group: 'C5 · Discover & app library',
      ),
      DevEventSpec(
        name: 'discover_article_opened',
        group: 'C5 · Discover & app library',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'source_name', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'position', kind: DevParamKind.integer, example: 1),
        ],
      ),
      DevEventSpec(
        name: 'discover_sources_opened',
        group: 'C5 · Discover & app library',
      ),
      DevEventSpec(
        name: 'discover_suggestion_launched',
        group: 'C5 · Discover & app library',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'position', kind: DevParamKind.integer, example: 1),
        ],
      ),
      DevEventSpec(
        name: 'app_library_opened',
        group: 'C5 · Discover & app library',
      ),
      DevEventSpec(
        name: 'app_library_category_opened',
        group: 'C5 · Discover & app library',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'category', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'settings_opened',
        group: 'C6 · Settings & feature flags',
      ),
      DevEventSpec(
        name: 'settings_subpage_opened',
        group: 'C6 · Settings & feature flags',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'page', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'feature_toggled',
        group: 'C6 · Settings & feature flags',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'feature_id', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'enabled', kind: DevParamKind.boolean, example: true),
        ],
      ),
      DevEventSpec(
        name: 'appearance_changed',
        group: 'C6 · Settings & feature flags',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'setting', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'value', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'gesture_set',
        group: 'C6 · Settings & feature flags',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'gesture', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'action', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'settings_export',
        group: 'C6 · Settings & feature flags',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'success', kind: DevParamKind.boolean, example: true),
        ],
      ),
      DevEventSpec(
        name: 'app_install_event',
        group: 'C6 · Settings & feature flags',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'event_type', kind: DevParamKind.text, example: 'example'),
          DevParamSpec(name: 'source', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'installed_app_removed',
        group: 'C6 · Settings & feature flags',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'source', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'retention_app_opened',
        group: 'Retention (from RetentionTracker)',
        parameters: <DevParamSpec>[
          DevParamSpec(name: 'd7_retention_rate', kind: DevParamKind.text, example: 'example'),
        ],
      ),
      DevEventSpec(
        name: 'retention_session_started',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_first_open',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_second_open',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_third_open',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_fourth_open',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_fifth_open',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_first_session',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_second_session',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_third_session',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_fourth_session',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_fifth_session',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_day_0_returned',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_day_1_returned',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_day_3_returned',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_day_7_returned',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_day_10_returned',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_day_15_returned',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_day_20_returned',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_day_25_returned',
        group: 'Retention (from RetentionTracker)',
      ),
      DevEventSpec(
        name: 'retention_day_30_returned',
        group: 'Retention (from RetentionTracker)',
      ),
    ],
  );
}
