import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/services/wallpaper_service.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

/// Solid colours offered for the Minimal background.
const minimalBackgroundSwatches = <int>[
  0xFF000000, // black (default)
  0xFF101414, // charcoal
  0xFF1B2430, // navy
  0xFF20161B, // wine
  0xFF14201A, // forest
  0xFF2A2A2E, // graphite
  0xFFF5F5F5, // light
];

/// Background picker for the iOS and Minimal home styles. Changes apply as
/// they are tapped, so the home screen above the sheet is the live preview;
/// Undo restores what the style had when the sheet opened.
Future<void> showHomeBackgroundSheet(
  BuildContext context, {
  required HomeMode style,
  required VoidCallback onOpenWallpaperBrowser,
}) async {
  assert(style != HomeMode.smart, 'Smart always shows the phone wallpaper');
  final cubit = context.read<SettingsCubit>();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black12,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _HomeBackgroundSheet(
        style: style,
        onOpenWallpaperBrowser: onOpenWallpaperBrowser,
      ),
    ),
  );
  final settings = cubit.state;
  await WallpaperService.deleteUnusedGalleryCopies([
    settings.iosPhotoPath,
    settings.minimalPhotoPath,
  ]);
}

class _HomeBackgroundSheet extends StatefulWidget {
  final HomeMode style;
  final VoidCallback onOpenWallpaperBrowser;

  const _HomeBackgroundSheet({
    required this.style,
    required this.onOpenWallpaperBrowser,
  });

  @override
  State<_HomeBackgroundSheet> createState() => _HomeBackgroundSheetState();
}

class _HomeBackgroundSheetState extends State<_HomeBackgroundSheet> {
  late final LauncherSettings _original;
  bool _picking = false;
  String? _error;

  bool get _isIos => widget.style == HomeMode.ios;

  @override
  void initState() {
    super.initState();
    _original = context.read<SettingsCubit>().state;
  }

  HomeBackground _mode(LauncherSettings s) =>
      _isIos ? s.iosBackground : s.minimalBackground;

  String _photo(LauncherSettings s) =>
      _isIos ? s.iosPhotoPath : s.minimalPhotoPath;

  double _blur(LauncherSettings s) => _isIos ? s.iosBlur : s.minimalBlur;

  double _dim(LauncherSettings s) => _isIos ? s.iosDim : s.minimalDim;

  LauncherSettings _with(
    LauncherSettings s, {
    HomeBackground? mode,
    String? photo,
    int? color,
    double? blur,
    double? dim,
  }) {
    return _isIos
        ? s.copyWith(
            iosBackground: mode,
            iosPhotoPath: photo,
            iosBlur: blur,
            iosDim: dim,
          )
        : s.copyWith(
            minimalBackground: mode,
            minimalPhotoPath: photo,
            minimalBackgroundColor: color,
            minimalBlur: blur,
            minimalDim: dim,
          );
  }

  bool _changed(LauncherSettings s) =>
      _mode(s) != _mode(_original) ||
      _photo(s) != _photo(_original) ||
      _blur(s) != _blur(_original) ||
      _dim(s) != _dim(_original) ||
      (!_isIos && s.minimalBackgroundColor != _original.minimalBackgroundColor);

  void _apply({
    HomeBackground? mode,
    String? photo,
    int? color,
    double? blur,
    double? dim,
  }) {
    final cubit = context.read<SettingsCubit>();
    cubit.update(
      _with(
        cubit.state,
        mode: mode,
        photo: photo,
        color: color,
        blur: blur,
        dim: dim,
      ),
    );
  }

  void _undo() {
    _apply(
      mode: _mode(_original),
      photo: _photo(_original),
      color: _original.minimalBackgroundColor,
      blur: _blur(_original),
      dim: _dim(_original),
    );
  }

  Future<void> _selectPhotoMode(LauncherSettings s) async {
    final existing = _photo(s);
    if (existing.isNotEmpty && File(existing).existsSync()) {
      _apply(mode: HomeBackground.photo);
      return;
    }
    await _pickPhoto();
  }

  Future<void> _pickPhoto() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final path = await WallpaperService.pickFromGallery();
      if (!mounted || path == null) return;
      _apply(mode: HomeBackground.photo, photo: path);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open that photo.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state;
    final mode = _mode(settings);
    final modes = _isIos
        ? const [HomeBackground.wallpaper, HomeBackground.photo]
        : HomeBackground.values;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.6),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Background',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      for (final option in modes) ...[
                        if (option != modes.first) const SizedBox(width: 10),
                        Expanded(
                          child: _ModeCard(
                            mode: option,
                            selected: mode == option,
                            onTap: _picking
                                ? null
                                : () => switch (option) {
                                      HomeBackground.photo =>
                                        _selectPhotoMode(settings),
                                      _ => _apply(mode: option),
                                    },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: switch (mode) {
                      HomeBackground.wallpaper => _SheetAction(
                          icon: Icons.wallpaper_rounded,
                          label: 'Change phone wallpaper',
                          onTap: () {
                            Navigator.pop(context);
                            widget.onOpenWallpaperBrowser();
                          },
                        ),
                      HomeBackground.photo => _SheetAction(
                          icon: Icons.photo_library_outlined,
                          label: _picking
                              ? 'Opening photos...'
                              : 'Choose another photo',
                          onTap: _picking ? null : _pickPhoto,
                        ),
                      HomeBackground.color => _Swatches(
                          selected: settings.minimalBackgroundColor,
                          onSelected: (color) => _apply(color: color),
                        ),
                    },
                  ),
                  if (mode != HomeBackground.color) ...[
                    _SliderRow(
                      icon: Icons.blur_on_rounded,
                      label: 'Blur',
                      value: _blur(settings),
                      max: 1,
                      divisions: 10,
                      onChanged: (value) => _apply(blur: value),
                    ),
                    _SliderRow(
                      icon: Icons.brightness_6_outlined,
                      label: 'Dim',
                      value: _dim(settings),
                      max: 0.8,
                      divisions: 8,
                      onChanged: (value) => _apply(dim: value),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _changed(settings) ? _undo : null,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white30,
                        ),
                        child: const Text('Undo'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final HomeBackground mode;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (mode) {
      HomeBackground.wallpaper => (Icons.wallpaper_rounded, 'Phone wallpaper'),
      HomeBackground.photo => (Icons.photo_outlined, 'Photo'),
      HomeBackground.color => (Icons.palette_outlined, 'Colour'),
    };
    return Material(
      color: Colors.white.withValues(alpha: selected ? 0.22 : 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? Colors.white : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SheetAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        alignment: Alignment.centerLeft,
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (value / max * 100).round();
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white12,
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
            ),
            child: Slider(
              value: value.clamp(0.0, max),
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            percent == 0 ? 'Off' : '$percent%',
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _Swatches extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _Swatches({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: minimalBackgroundSwatches.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final value = minimalBackgroundSwatches[index];
        final color = Color(value);
        final isSelected = value == selected;
        return Center(
          child: GestureDetector(
            onTap: () => onSelected(value),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white24,
                  width: isSelected ? 3 : 1,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: color.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}
