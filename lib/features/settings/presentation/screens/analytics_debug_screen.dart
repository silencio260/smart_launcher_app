import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:genrevibes_starter_kit/starter_kit.dart';

import 'package:smart_launcher_app/core/analytics/analytics_config.dart';

/// Dev-only Analytics inspector reached from Settings → Developer Options →
/// Dev View → Analytics.
///
/// Two pages:
///   * [_RetentionMetricsScreen] — the live retention/engagement numbers held by
///     [RetentionTracker], so you can confirm the values being attached to
///     `retention_*` events without waiting on a dashboard.
///   * [_TrackedEventsScreen] — the catalog of every event name + params this
///     app emits (mirrors [AppAnalytics] in app_events.dart).
///
/// Nothing here sends analytics; it only reads local state. Safe to open
/// repeatedly. Wired behind `kDebugMode` at the call site.
class AnalyticsDebugScreen extends StatelessWidget {
  const AnalyticsDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hasMixpanel = AnalyticsConfig.hasMixpanelToken;
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Inspect what this build tracks and the current retention state. '
              'These pages only read local data — they do not log anything.',
            ),
          ),
          // Quick provider status so you immediately know WHY a dashboard might
          // be empty (Firebase is always on; Mixpanel needs a token).
          ListTile(
            leading: Icon(
              Icons.local_fire_department_outlined,
              color: Colors.orange.shade700,
            ),
            title: const Text('Firebase Analytics'),
            subtitle: const Text(
              'Always on (auth via google-services.json). Verify live in '
              'Firebase console → DebugView.',
            ),
            isThreeLine: true,
          ),
          ListTile(
            leading: Icon(
              hasMixpanel ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: hasMixpanel ? Colors.green : Colors.red,
            ),
            title: const Text('Mixpanel'),
            subtitle: Text(
              hasMixpanel
                  ? 'Token configured — events + session replay active.'
                  : 'No mixpanel_token in the active env file — SDK is a '
                      'no-op, nothing is sent. Set it in env/<flavor>.json.',
            ),
            isThreeLine: true,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Retention metrics'),
            subtitle: const Text('Live engagement values & D1/D7/D30 returns'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const _RetentionMetricsScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt_outlined),
            title: const Text('Tracked events'),
            subtitle: const Text('Catalog of every event name & its params'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const _TrackedEventsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Page 1 — Retention metrics (live values)
// ===========================================================================

class _RetentionMetricsScreen extends StatelessWidget {
  const _RetentionMetricsScreen();

  @override
  Widget build(BuildContext context) {
    final tracker = StarterKit.retentionTracker;
    return Scaffold(
      appBar: AppBar(title: const Text('Retention metrics')),
      // RetentionTracker is a ChangeNotifier — rebuild when a new app open /
      // session is recorded while this page is visible.
      body: ListenableBuilder(
        listenable: tracker,
        builder: (context, _) {
          final engagement = tracker.getEngagementMetrics();
          final d7 = tracker.getD7RetentionRate();
          final activeDays = tracker.getActiveDays();
          return ListView(
            children: [
              const _GroupHeader('Engagement'),
              _MetricTile('Total app opens', '${tracker.getTotalAppOpens()}'),
              _MetricTile('Total sessions', '${engagement['total_sessions']}'),
              _MetricTile(
                  'Sessions today', '${tracker.getSessionCountToday()}'),
              _MetricTile(
                'Active days (last 35)',
                '${engagement['active_days_count']}',
              ),
              _MetricTile(
                'Days since install',
                '${tracker.getDaysSinceInstall()}',
              ),
              _MetricTile(
                'Days since last open',
                '${tracker.getDaysSinceLastOpen()}',
              ),
              const Divider(),
              const _GroupHeader('Retention milestones'),
              _MetricTile(
                'D7 retention rate',
                '${d7.toStringAsFixed(1)}%',
              ),
              _BoolTile('Returned on D1', tracker.hasReturnedOnDay(1)),
              _BoolTile('Returned on D3', tracker.hasReturnedOnDay(3)),
              _BoolTile('Returned on D7', tracker.hasReturnedOnDay(7)),
              _BoolTile('Returned on D30', tracker.hasReturnedOnDay(30)),
              const Divider(),
              _GroupHeader('Active days (${activeDays.length})'),
              if (activeDays.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('No active days recorded yet.'),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(activeDays.join('\n')),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  'These are the same values attached to retention_* events '
                  '(app_opened / session_started / dayN_returned). History '
                  'older than 35 days is pruned, so D30 reflects the windowed '
                  'data on disk.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  const _MetricTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _BoolTile extends StatelessWidget {
  final String label;
  final bool value;
  const _BoolTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Icon(
        value ? Icons.check_circle : Icons.remove_circle_outline,
        color: value ? Colors.green : Theme.of(context).disabledColor,
        size: 20,
      ),
    );
  }
}

// ===========================================================================
// Page 2 — Tracked events catalog
// ===========================================================================

/// One row in the event catalog.
class _EventDef {
  final String name;
  final List<String> params;
  const _EventDef(this.name, [this.params = const []]);
}

class _EventGroup {
  final String title;
  final List<_EventDef> events;
  const _EventGroup(this.title, this.events);
}

/// Catalog of every event this app emits.
///
/// IMPORTANT: keep in sync with [AppAnalytics] in
/// core/analytics/app_events.dart. Grouped by the same C0–C7 sections.
const List<_EventGroup> _eventCatalog = [
  _EventGroup('Generic', [
    _EventDef('screen_view', ['screen_name']),
  ]),
  _EventGroup('C0 · Lifecycle & user model', [
    _EventDef('app_open'),
    _EventDef('launcher_set_default', ['is_default']),
  ]),
  _EventGroup('C1 · Home / workspace', [
    _EventDef('app_launched', ['source', 'position']),
    _EventDef('workspace_page_changed', ['from_index', 'to_index', 'type']),
    _EventDef('folder_opened', ['item_count']),
    _EventDef('home_edit_mode'),
    _EventDef('drawer_opened', ['open_method']),
    _EventDef('app_context_menu_opened', ['actions_available']),
  ]),
  _EventGroup('Ads', [
    _EventDef('ad_lifecycle', [
      'ad_type',
      'action',
      'result',
      'source',
      'test_ads',
      'error',
    ]),
    _EventDef('ad_impression', [
      'ad_platform',
      'ad_source',
      'ad_format',
      'ad_unit_name',
      'value',
      'currency',
    ]),
    _EventDef('ad_revenue', [
      'value',
      'currency',
      'ad_source',
      'ad_unit_id',
      'ad_format',
      'ad_network',
    ]),
  ]),
  _EventGroup('C2 · Smart search', [
    _EventDef('search_opened', ['source']),
    _EventDef(
        'search_performed', ['query_length', 'result_count', 'has_results']),
    _EventDef('search_result_tapped', ['result_type', 'result_index']),
    _EventDef('search_recent_rerun'),
  ]),
  _EventGroup('C3 · Secure mini-apps', [
    _EventDef('mini_app_open', ['mini_app']),
    _EventDef('secure_auth_attempt', ['mini_app', 'method']),
    _EventDef('secure_auth_result', ['mini_app', 'method', 'success']),
    _EventDef('vault_item_imported', ['media_type', 'count']),
    _EventDef('vault_item_exported', ['count']),
    _EventDef('app_lock_toggle', ['enabled']),
    _EventDef('app_lock_challenge_shown', ['strategy']),
    _EventDef('app_hider_toggle', ['hidden']),
    _EventDef('app_hider_disguise_set', ['disguise_id']),
    _EventDef('file_locker_action', ['action', 'file_type']),
  ]),
  _EventGroup('C4 · Clock / alarm', [
    _EventDef('alarm_created', ['repeat', 'has_sound']),
    _EventDef('alarm_edited', ['field_changed']),
    _EventDef('alarm_deleted'),
    _EventDef('alarm_toggled', ['enabled']),
    _EventDef('alarm_fired', ['snoozed']),
    _EventDef('world_clock_added'),
  ]),
  _EventGroup('C5 · Discover & app library', [
    _EventDef('discover_opened'),
    _EventDef('discover_article_opened', ['source_name', 'position']),
    _EventDef('discover_sources_opened'),
    _EventDef('discover_suggestion_launched', ['position']),
    _EventDef('app_library_opened'),
    _EventDef('app_library_category_opened', ['category']),
  ]),
  _EventGroup('C6 · Settings & feature flags', [
    _EventDef('settings_opened'),
    _EventDef('settings_subpage_opened', ['page']),
    _EventDef('feature_toggled', ['feature_id', 'enabled']),
    _EventDef('appearance_changed', ['setting', 'value']),
    _EventDef('gesture_set', ['gesture', 'action']),
    _EventDef('settings_export', ['success']),
  ]),
  _EventGroup('Retention (from RetentionTracker)', [
    _EventDef('app_opened', ['engagement metrics', 'd7_retention_rate']),
    _EventDef('session_started', ['engagement metrics']),
    _EventDef('day1_returned'),
    _EventDef('day3_returned'),
    _EventDef('day7_returned'),
    _EventDef('day30_returned'),
  ]),
];

class _TrackedEventsScreen extends StatelessWidget {
  const _TrackedEventsScreen();

  int get _total => _eventCatalog.fold(0, (sum, g) => sum + g.events.length);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tracked events')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '$_total events. Names below are exactly what is sent to Firebase '
              '(and Mixpanel when a token is set). Privacy rules: no package/app '
              'names, no raw search text, PINs, patterns, or file names — only '
              'lengths, counts, and flags.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          for (final group in _eventCatalog) ...[
            _GroupHeader(group.title),
            for (final e in group.events) _EventTile(e),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final _EventDef event;
  const _EventTile(this.event);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(
        event.name,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      subtitle: event.params.isEmpty
          ? null
          : Text(
              event.params.join(', '),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 18),
        tooltip: 'Copy event name',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: event.name));
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('Copied "${event.name}"')),
            );
        },
      ),
    );
  }
}

// ===========================================================================
// Shared
// ===========================================================================

class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
