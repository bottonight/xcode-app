import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

const gsmCommonLabels = ['品名', '成分', '门幅', '标称克重', '纱支', '报价', '备注', '织造方式'];
const gsmWeavingWoven = '梭织';
const gsmWeavingKnit = '针织';
const gsmWovenLabels = ['织法/工艺', '密度'];
const gsmKnitLabels = ['针数'];
const gsmReservedKeys = {
  '品名',
  '成分',
  '门幅',
  '标称克重',
  '纱支',
  '报价',
  '备注',
  '织造方式',
  '织法/工艺',
  '密度',
  '针数',
  'custom_image',
};

const gsmServiceUuid = '00001234-0000-1000-8000-00805f9b34fb';
const gsmReadUuid = '00001235-0000-1000-8000-00805f9b34fb';
const gsmUpdateUuid = '00001236-0000-1000-8000-00805f9b34fb';
const gsmNetworkUuid = '00001237-0000-1000-8000-00805f9b34fb';
const gsmIpUuid = '00001238-0000-1000-8000-00805f9b34fb';
const gsmWriteUuid = '00001239-0000-1000-8000-00805f9b34fb';
const gsmTriggerUuid = '0000123a-0000-1000-8000-00805f9b34fb';
const gsmNameUuid = '0000123b-0000-1000-8000-00805f9b34fb';
const gsmBindUuid = '0000123c-0000-1000-8000-00805f9b34fb';

bool isGsmAdvertisedName(String name) => name.startsWith('FEAT');

String gsmBleName(String? raw) => (raw ?? '').replaceFirst(RegExp(r'^FEAT-'), '').trim();

List<String> gsmDynamicLabels(String weaving) {
  if (weaving == gsmWeavingWoven) return gsmWovenLabels;
  if (weaving == gsmWeavingKnit) return gsmKnitLabels;
  return const [];
}

bool splitDeviceSections({required int composition, required int gsm}) =>
    composition > 0 && gsm > 0;

int gsmSignalPercent(int rssi) {
  if (rssi >= -30) return 100;
  if (rssi <= -100) return 0;
  return (((rssi + 100) * 100) / 70).round().clamp(0, 100);
}

class GsmDevice {
  const GsmDevice({required this.id, required this.name});
  final String id, name;
  String label(String fallback) => name.trim().isEmpty ? fallback : name.trim();

  factory GsmDevice.fromJson(Map<String, dynamic> json) => GsmDevice(
    id: '${json['device_id'] ?? json['id'] ?? ''}'.trim(),
    name: '${json['device_name'] ?? json['name'] ?? ''}'.trim(),
  );

  Map<String, dynamic> toJson() => {'device_id': id, 'device_name': name};
}

List<GsmDevice> mergeGsmDevices(List<GsmDevice> cached, List<GsmDevice> remote) {
  final seen = <String>{};
  final merged = <GsmDevice>[];
  for (final device in [...remote, ...cached]) {
    if (device.id.isEmpty || !seen.add(device.id)) continue;
    merged.add(device);
  }
  return merged;
}

class GsmRecord {
  const GsmRecord({
    required this.id,
    required this.time,
    required this.gsm,
    required this.unit,
    required this.image,
    required this.favorite,
    required this.product,
  });
  final String id, time, gsm, unit, image, product;
  final bool favorite;

  GsmRecord copyWith({bool? favorite, String? product}) => GsmRecord(
    id: id,
    time: time,
    gsm: gsm,
    unit: unit,
    image: image,
    favorite: favorite ?? this.favorite,
    product: product ?? this.product,
  );

  factory GsmRecord.fromJson(Map<String, dynamic> json) {
    final extra = gsmStringMap(json['extra_data']);
    final product = (extra['品名'] ?? '').trim();
    return GsmRecord(
      id: '${json['id'] ?? ''}',
      time: formatDisplayTime('${json['time'] ?? ''}'),
      gsm: '${json['gsm'] ?? ''}',
      unit: '${json['unit'] ?? ''}',
      image: '${json['image'] ?? ''}'.trim(),
      favorite: json['favorite'] == 1 || json['favorite'] == true,
      product: product.isEmpty ? '-' : product,
    );
  }
}

class GsmDetail {
  const GsmDetail({
    required this.id,
    required this.time,
    required this.gsm,
    required this.unit,
    required this.image,
    required this.extra,
  });
  final String id, time, gsm, unit, image;
  final Map<String, String> extra;

  factory GsmDetail.fromJson(Map<String, dynamic> json) {
    final extra = gsmStringMap(json['extra_data']);
    return GsmDetail(
      id: '${json['id'] ?? ''}',
      time: formatDisplayTime('${json['time'] ?? ''}'),
      gsm: '${json['gsm'] ?? ''}',
      unit: '${json['unit'] ?? ''}',
      image: '${json['image'] ?? ''}'.trim(),
      extra: extra,
    );
  }
}

class GsmPage {
  const GsmPage({required this.items, required this.total, required this.page, this.pageSize = 10});
  final List<GsmRecord> items;
  final int total, page, pageSize;
  int get totalPages => total == 0 ? 0 : (total / pageSize).ceil();
}

class GsmHardwareInfo {
  const GsmHardwareInfo({
    required this.deviceId,
    required this.hardware,
    required this.mac,
    required this.software,
    required this.supports5g,
  });
  final String deviceId, hardware, mac, software;
  final bool supports5g;

  factory GsmHardwareInfo.fromJson(Map<String, dynamic> json) {
    final id = '${json['device_id'] ?? ''}'.trim();
    if (id.isEmpty) throw const FormatException('device_id');
    return GsmHardwareInfo(
      deviceId: id,
      hardware: '${json['hardware_ver'] ?? ''}',
      mac: '${json['mac'] ?? ''}',
      software: '${json['software_ver'] ?? ''}',
      supports5g: json['5g'] == true,
    );
  }
}

class GsmField {
  const GsmField(this.label, this.value);
  final String label, value;
}

List<GsmField> gsmCustomFields(Map<String, String> extra) => [
  for (final entry in extra.entries)
    if (!gsmReservedKeys.contains(entry.key) && entry.value.trim().isNotEmpty)
      GsmField(entry.key, entry.value),
];

Map<String, String> gsmStringMap(dynamic raw) {
  dynamic value = raw;
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return {};
    try {
      value = jsonDecode(text);
    } catch (_) {
      return {};
    }
  }
  if (value is! Map) return {};
  return value.map((key, item) => MapEntry('$key', item == null ? '' : '$item'));
}

Uint8List? decodeGsmImage(String raw) {
  final cleaned = raw
      .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '')
      .replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) return null;
  try {
    return base64Decode(cleaned);
  } catch (_) {
    return null;
  }
}

class GsmNameInput {
  const GsmNameInput(this.value, this.errorKey);
  final String value;
  final String? errorKey;
}

const gsmNameMaxWidth = 14;

bool _gsmNameChar(int code) {
  if ((code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x20) {
    return true;
  }
  if ((code >= 0xFF10 && code <= 0xFF19) ||
      (code >= 0xFF21 && code <= 0xFF3A) ||
      (code >= 0xFF41 && code <= 0xFF5A)) {
    return true;
  }
  return (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF);
}

int _gsmNameWidth(int code) => code <= 0x7E ? 1 : 2;

GsmNameInput sanitizeGsmName(String input) {
  final buffer = StringBuffer();
  var width = 0;
  String? error;
  for (final code in input.runes) {
    if (!_gsmNameChar(code)) {
      error ??= 'gsm.name_invalid';
      continue;
    }
    final next = _gsmNameWidth(code);
    if (width + next > gsmNameMaxWidth) {
      error ??= 'gsm.name_long';
      break;
    }
    buffer.writeCharCode(code);
    width += next;
  }
  return GsmNameInput(buffer.toString(), error);
}

String? validateGsmName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'gsm.name_empty';
  final checked = sanitizeGsmName(trimmed);
  if (checked.errorKey != null || checked.value != trimmed) {
    return checked.errorKey ?? 'gsm.name_invalid';
  }
  return null;
}

class GsmInfoAssembler {
  int totalLength = 0;
  final List<List<int>?> packets = [];

  void add(List<int> value) {
    if (value.isEmpty) return;
    final index = value[0];
    final data = value.sublist(1);
    if (index == 0) {
      if (data.length >= 4) {
        totalLength = data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
        packets
          ..clear()
          ..add(null);
      }
      return;
    }
    while (packets.length <= index) {
      packets.add(null);
    }
    packets[index] = data;
  }

  List<int>? take() {
    if (totalLength <= 0) return null;
    final combined = <int>[];
    for (final packet in packets) {
      if (packet == null || packet.isEmpty) continue;
      final room = totalLength - combined.length;
      if (room <= 0) break;
      combined.addAll(packet.length <= room ? packet : packet.sublist(0, room));
    }
    if (combined.length < totalLength) return null;
    return combined;
  }
}

List<List<int>> gsmWifiPackets(List<int> payload) {
  const size = 19;
  final packets = <List<int>>[];
  final length = List<int>.filled(20, 0);
  final count = payload.length;
  length[1] = count & 0xFF;
  length[2] = (count >> 8) & 0xFF;
  length[3] = (count >> 16) & 0xFF;
  length[4] = (count >> 24) & 0xFF;
  packets.add(length);
  final total = count == 0 ? 0 : (count / size).ceil();
  for (var i = 0; i < total; i++) {
    final start = i * size;
    final end = start + size > count ? count : start + size;
    final packet = List<int>.filled(20, 0);
    packet[0] = i + 1;
    packet.setRange(1, 1 + end - start, payload.sublist(start, end));
    packets.add(packet);
  }
  return packets;
}

String gsmErrorText(String Function(String key, [Object? value]) translate, Object error) {
  if (error is AppException) {
    return error.key == 'server' ? '${error.detail}' : translate(error.key, error.detail);
  }
  if (error is TimeoutException) return translate('error.connect', '$error');
  return translate('error.connect', '$error');
}
