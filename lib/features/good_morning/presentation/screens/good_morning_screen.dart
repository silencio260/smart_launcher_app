import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/features/apps/data/app_categories.dart';
import 'package:smart_launcher_app/core/platform/feature_launch_dispatcher.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/core/widgets/mini_app_chrome.dart';

class GoodMorningScreen extends StatefulWidget {
  const GoodMorningScreen({super.key});

  @override
  State<GoodMorningScreen> createState() => _GoodMorningScreenState();
}

class _GoodMorningScreenState extends State<GoodMorningScreen> {
  // Calendar events feature removed (READ_CALENDAR dropped).
  _WeatherInfo? _weather;
  String _nextAlarm = 'Next alarm is not set';
  bool _loadingWeather = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([
      _loadNextAlarm(),
      _loadWeather(),
    ]);
  }

  Future<void> _loadNextAlarm() async {
    try {
      final alarm = await LauncherService.getNextAlarm();
      final trigger = alarm?['triggerTime'] as int?;
      if (trigger == null) return;
      final dt = DateTime.fromMillisecondsSinceEpoch(trigger);
      if (!mounted) return;
      setState(() {
        _nextAlarm =
            'Next alarm is set for ${DateFormat('EEE h:mm a').format(dt)}';
      });
    } catch (_) {}
  }

  // _loadCalendar / _eventSubtitle removed: Calendar events feature was never
  // wired (READ_CALENDAR was never requested) and the permission is dropped.

  Future<void> _loadWeather() async {
    try {
      var location = await LauncherService.getDeviceLocation();
      if (location == null) {
        final status = await Permission.locationWhenInUse.status;
        if (!status.isGranted && !status.isPermanentlyDenied) {
          await Permission.locationWhenInUse.request();
          location = await LauncherService.getDeviceLocation();
        }
      }
      final lat = (location?['latitude'] as num?)?.toDouble();
      final lon = (location?['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return;
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'current': 'temperature_2m,weather_code,precipitation',
        'timezone': 'auto',
      });
      final client = HttpClient();
      try {
        final request =
            await client.getUrl(uri).timeout(const Duration(seconds: 5));
        final response =
            await request.close().timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) return;
        final body = await utf8.decodeStream(response);
        final json = jsonDecode(body) as Map<String, dynamic>;
        final current = json['current'] as Map<String, dynamic>?;
        if (current == null) return;
        final temp = (current['temperature_2m'] as num?)?.round();
        final code = (current['weather_code'] as num?)?.toInt();
        final rain = (current['precipitation'] as num?)?.toDouble() ?? 0;
        if (temp == null || code == null) return;
        if (!mounted) return;
        setState(() {
          _weather = _WeatherInfo(
            temperature: temp,
            condition: _weatherLabel(code),
            icon: _weatherIcon(code),
            rainMm: rain,
            city: location?['city']?.toString() ?? 'Current location',
          );
        });
      } finally {
        client.close(force: true);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingWeather = false);
    }
  }

  IconData _weatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny_rounded;
    if (code <= 3) return Icons.cloud_rounded;
    if (code >= 51 && code <= 67) return Icons.grain_rounded;
    if (code >= 80 && code <= 99) return Icons.thunderstorm_rounded;
    return Icons.cloud_queue_rounded;
  }

  String _weatherLabel(int code) {
    if (code == 0) return 'Clear sky';
    if (code == 1) return 'Mainly clear';
    if (code == 2) return 'Partly cloudy';
    if (code == 3) return 'Overcast';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 57) return 'Drizzle';
    if (code >= 61 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain showers';
    if (code >= 95) return 'Thunderstorm';
    return 'Weather';
  }

  void _close() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openClock() {
    FeatureLaunchDispatcher.openFeature(context, 'alarm_clock');
  }

  Future<void> _playMusic() async {
    final apps = context.read<AppsCubit>().state.apps;
    final musicApps = apps
        .where((app) =>
            categorize(app.packageName, title: app.title) == AppCategory.music)
        .toList();
    if (musicApps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No music app found')),
      );
      return;
    }
    final app = musicApps.length == 1
        ? musicApps.first
        : await showModalBottomSheet<AppInfo>(
            context: context,
            backgroundColor: miniAppSurface,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final app in musicApps.take(8))
                    ListTile(
                      leading: _AppIcon(app: app),
                      title: Text(app.name,
                          style: const TextStyle(color: Colors.white)),
                      trailing:
                          const Icon(Icons.chevron_right, color: miniAppMuted),
                      onTap: () => Navigator.pop(context, app),
                    ),
                ],
              ),
            ),
          );
    if (app != null && mounted) {
      FeatureLaunchDispatcher.launchPackage(context, app.packageName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: miniAppBackground,
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 76, 20, 108),
              children: [
                const Icon(
                  Icons.wb_sunny_outlined,
                  color: Colors.white,
                  size: 42,
                ),
                const SizedBox(height: 18),
                Text(
                  'Good Morning!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  _nextAlarm,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: miniAppMuted, fontSize: 15),
                ),
                const SizedBox(height: 58),
                _WeatherCard(weather: _weather, loading: _loadingWeather),
                const SizedBox(height: 14),
                _InfoCard(
                  icon: Icons.music_note_rounded,
                  title: 'Play some music',
                  trailing: Icons.more_vert_rounded,
                  onTap: _playMusic,
                ),
              ],
            ),
            Positioned(
              left: 16,
              top: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: _close,
              ),
            ),
            Positioned(
              right: 16,
              top: 12,
              child: IconButton(
                icon: const Icon(Icons.settings_outlined,
                    color: Colors.white, size: 30),
                onPressed: _openClock,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  final _WeatherInfo? weather;
  final bool loading;

  const _WeatherCard({required this.weather, required this.loading});

  @override
  Widget build(BuildContext context) {
    final info = weather;
    return _CardShell(
      child: Row(
        children: [
          Icon(
            info?.icon ?? Icons.cloud_off_rounded,
            color: Colors.white,
            size: 46,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      info == null ? '-- °C' : '${info.temperature} °C',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (info != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${info.rainMm.toStringAsFixed(1)} mm',
                          style: const TextStyle(
                            color: miniAppMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  info?.condition ??
                      (loading ? 'Loading weather' : 'Weather unavailable'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  info == null
                      ? 'open-meteo.com'
                      : '${info.city} - open-meteo.com',
                  style: const TextStyle(color: miniAppMuted, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final IconData? trailing;
  final VoidCallback? onTap;

  const _InfoCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: miniAppSurface2,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white10),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: miniAppMuted,
                      fontSize: 16,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) Icon(trailing, color: Colors.white, size: 28),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _CardShell({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: miniAppSurface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: child,
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final AppInfo app;

  const _AppIcon({required this.app});

  @override
  Widget build(BuildContext context) {
    final icon = app.icon;
    if (icon == null) {
      return const Icon(Icons.music_note_rounded, color: Colors.white);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(icon, width: 36, height: 36),
    );
  }
}

class _WeatherInfo {
  final int temperature;
  final String condition;
  final IconData icon;
  final double rainMm;
  final String city;

  const _WeatherInfo({
    required this.temperature,
    required this.condition,
    required this.icon,
    required this.rainMm,
    required this.city,
  });
}

