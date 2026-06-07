import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:smart_launcher_app/core/models/widget_provider_info.dart';

/// Grid sig that the cache is keyed by. A mismatch on load means a stale
/// cache from a different grid configuration; we drop it and let the next
/// refresh rebuild.
class WidgetCacheKey {
  final int gridColumns;
  final int gridRows;
  final int cellWidth;
  final int cellHeight;

  const WidgetCacheKey({
    required this.gridColumns,
    required this.gridRows,
    required this.cellWidth,
    required this.cellHeight,
  });

  factory WidgetCacheKey.from({
    required int gridColumns,
    required int gridRows,
    required double cellWidth,
    required double cellHeight,
  }) {
    return WidgetCacheKey(
      gridColumns: gridColumns,
      gridRows: gridRows,
      cellWidth: cellWidth.round(),
      cellHeight: cellHeight.round(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetCacheKey &&
      other.gridColumns == gridColumns &&
      other.gridRows == gridRows &&
      other.cellWidth == cellWidth &&
      other.cellHeight == cellHeight;

  @override
  int get hashCode => Object.hash(gridColumns, gridRows, cellWidth, cellHeight);
}

/// Persists the widget picker's provider list (including preview/icon byte
/// payloads) so subsequent opens render instantly. The on-disk format is a
/// compact binary blob — JSON+base64 would roughly double the size of the
/// payload bytes, which is the bulk of the file.
class WidgetProviderCacheService {
  WidgetProviderCacheService._({Directory? overrideDir})
      : _overrideDir = overrideDir;

  static final WidgetProviderCacheService instance =
      WidgetProviderCacheService._();

  /// Test-only constructor: lets tests pin the cache directory.
  WidgetProviderCacheService.forTesting(Directory dir) : _overrideDir = dir;

  final Directory? _overrideDir;

  static const _fileName = 'widget_picker_cache_v1.bin';
  static const _magic = 0x57504331; // 'WPC1'
  static const _version = 1;

  Future<List<WidgetProviderInfo>?> load(WidgetCacheKey key) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return _decode(bytes, key);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    WidgetCacheKey key,
    List<WidgetProviderInfo> providers,
  ) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final bytes = _encode(key, providers);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (_) {
      // Cache is best-effort. A failed write just means the next open
      // refetches from the platform.
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<File> _file() async {
    final dir = _overrideDir ?? await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Uint8List _encode(WidgetCacheKey key, List<WidgetProviderInfo> providers) {
    final w = _Writer();
    w.writeU32(_magic);
    w.writeU8(_version);
    w.writeU16(key.gridColumns);
    w.writeU16(key.gridRows);
    w.writeU16(key.cellWidth);
    w.writeU16(key.cellHeight);
    w.writeU32(providers.length);
    for (final p in providers) {
      w.writeString(p.packageName);
      w.writeString(p.appName);
      w.writeString(p.providerClass);
      w.writeString(p.label);
      w.writeI32(p.minWidth);
      w.writeI32(p.minHeight);
      w.writeI32(p.minResizeWidth);
      w.writeI32(p.minResizeHeight);
      w.writeI32(p.maxResizeWidth);
      w.writeI32(p.maxResizeHeight);
      w.writeI32(p.resizeMode);
      w.writeI32(p.targetCellWidth);
      w.writeI32(p.targetCellHeight);
      w.writeI32(p.minSpanX);
      w.writeI32(p.minSpanY);
      w.writeI32(p.spanX);
      w.writeI32(p.spanY);
      w.writeI32(p.maxSpanX);
      w.writeI32(p.maxSpanY);
      var flags = 0;
      if (p.previewIsGenerated) flags |= 0x01;
      if (p.appIcon != null) flags |= 0x02;
      if (p.previewImage != null) flags |= 0x04;
      w.writeU8(flags);
      if (p.appIcon != null) w.writeBytes(p.appIcon!);
      if (p.previewImage != null) w.writeBytes(p.previewImage!);
    }
    return w.toBytes();
  }

  List<WidgetProviderInfo>? _decode(Uint8List bytes, WidgetCacheKey key) {
    final r = _Reader(bytes);
    if (r.readU32() != _magic) return null;
    if (r.readU8() != _version) return null;
    final cols = r.readU16();
    final rows = r.readU16();
    final cellW = r.readU16();
    final cellH = r.readU16();
    if (cols != key.gridColumns ||
        rows != key.gridRows ||
        cellW != key.cellWidth ||
        cellH != key.cellHeight) {
      return null;
    }
    final count = r.readU32();
    final out = <WidgetProviderInfo>[];
    for (var i = 0; i < count; i++) {
      final packageName = r.readString();
      final appName = r.readString();
      final providerClass = r.readString();
      final label = r.readString();
      final minWidth = r.readI32();
      final minHeight = r.readI32();
      final minResizeWidth = r.readI32();
      final minResizeHeight = r.readI32();
      final maxResizeWidth = r.readI32();
      final maxResizeHeight = r.readI32();
      final resizeMode = r.readI32();
      final targetCellWidth = r.readI32();
      final targetCellHeight = r.readI32();
      final minSpanX = r.readI32();
      final minSpanY = r.readI32();
      final spanX = r.readI32();
      final spanY = r.readI32();
      final maxSpanX = r.readI32();
      final maxSpanY = r.readI32();
      final flags = r.readU8();
      final previewIsGenerated = (flags & 0x01) != 0;
      final hasAppIcon = (flags & 0x02) != 0;
      final hasPreview = (flags & 0x04) != 0;
      final appIcon = hasAppIcon ? r.readBytes() : null;
      final previewImage = hasPreview ? r.readBytes() : null;
      out.add(WidgetProviderInfo(
        packageName: packageName,
        appName: appName,
        providerClass: providerClass,
        label: label,
        minWidth: minWidth,
        minHeight: minHeight,
        minResizeWidth: minResizeWidth,
        minResizeHeight: minResizeHeight,
        maxResizeWidth: maxResizeWidth,
        maxResizeHeight: maxResizeHeight,
        resizeMode: resizeMode,
        targetCellWidth: targetCellWidth,
        targetCellHeight: targetCellHeight,
        minSpanX: minSpanX,
        minSpanY: minSpanY,
        spanX: spanX,
        spanY: spanY,
        maxSpanX: maxSpanX,
        maxSpanY: maxSpanY,
        appIcon: appIcon,
        previewImage: previewImage,
        previewIsGenerated: previewIsGenerated,
      ));
    }
    return out;
  }
}

class _Writer {
  final BytesBuilder _bb = BytesBuilder(copy: false);

  void writeU8(int v) {
    final b = ByteData(1)..setUint8(0, v);
    _bb.add(b.buffer.asUint8List());
  }

  void writeU16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    _bb.add(b.buffer.asUint8List());
  }

  void writeU32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    _bb.add(b.buffer.asUint8List());
  }

  void writeI32(int v) {
    final b = ByteData(4)..setInt32(0, v, Endian.little);
    _bb.add(b.buffer.asUint8List());
  }

  void writeString(String s) {
    final bytes = utf8.encode(s);
    writeU32(bytes.length);
    _bb.add(bytes);
  }

  void writeBytes(Uint8List bytes) {
    writeU32(bytes.length);
    _bb.add(bytes);
  }

  Uint8List toBytes() => _bb.toBytes();
}

class _Reader {
  final ByteData _data;
  int _offset = 0;

  _Reader(Uint8List bytes)
      : _data = ByteData.view(
            bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);

  int readU8() {
    final v = _data.getUint8(_offset);
    _offset += 1;
    return v;
  }

  int readU16() {
    final v = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    return v;
  }

  int readU32() {
    final v = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  int readI32() {
    final v = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  String readString() {
    final len = readU32();
    final bytes = Uint8List.view(
      _data.buffer,
      _data.offsetInBytes + _offset,
      len,
    );
    _offset += len;
    return utf8.decode(bytes);
  }

  Uint8List readBytes() {
    final len = readU32();
    final view = Uint8List.view(
      _data.buffer,
      _data.offsetInBytes + _offset,
      len,
    );
    _offset += len;
    // Copy so the returned bytes aren't a view into the file buffer.
    return Uint8List.fromList(view);
  }
}
