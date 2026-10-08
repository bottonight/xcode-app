import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../gsm.dart';
import '../models.dart';

class GsmNearby {
  const GsmNearby(this.id, this.name, this.rssi);
  final String id, name;
  final int rssi;
}

class GsmLink extends ChangeNotifier {
  GsmLink(this.device, this.advertisedName, this._characteristics);
  final BluetoothDevice device;
  final String advertisedName;
  final List<BluetoothCharacteristic> _characteristics;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String displayName = '';
  GsmHardwareInfo? hardware;
  String networkStatus = 'unknown';
  int wifiSignal = 0;
  int bluetoothSignal = 0;
  String ip = '';
  bool connected = true;
  int _networkEpoch = 0;
  bool _closed = false;
  Timer? _rssi;
  void Function(List<int> value)? _infoListener;
  void Function(List<int> value)? _updateListener;
  void Function(String value)? _ipWaiter;

  String get id => device.remoteId.str;

  void attach() {
    displayName = gsmBleName(advertisedName);
    _subscriptions.add(
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && connected) {
          connected = false;
          _emit();
        }
      }),
    );
    void listen(String uuid, void Function(List<int>) onData) {
      final characteristic = _find(uuid);
      if (characteristic == null) return;
      if (!(characteristic.properties.notify || characteristic.properties.indicate)) return;
      _subscriptions.add(characteristic.onValueReceived.listen(onData));
    }

    listen(gsmReadUuid, (value) => _infoListener?.call(value));
    listen(gsmUpdateUuid, (value) => _updateListener?.call(value));
    listen(gsmNetworkUuid, _onNetwork);
    listen(gsmIpUuid, (value) {
      final text = utf8.decode(value, allowMalformed: true).trim();
      if (text.isEmpty) return;
      ip = text;
      _ipWaiter?.call(text);
      _emit();
    });
    final network = _find(gsmNetworkUuid);
    if (network != null) unawaited(_notify(network, true));
    final ipChar = _find(gsmIpUuid);
    if (ipChar != null) unawaited(_notify(ipChar, true));
  }

  void startSignal() {
    _rssi?.cancel();
    unawaited(_readRssi());
    _rssi = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_readRssi()));
  }

  Future<GsmHardwareInfo> readInfo() async {
    final read = _need(gsmReadUuid, notify: true);
    final trigger = _need(gsmTriggerUuid, write: true);
    final assembler = GsmInfoAssembler();
    final done = Completer<GsmHardwareInfo>();
    _infoListener = (value) {
      if (done.isCompleted) return;
      assembler.add(value);
      final bytes = assembler.take();
      if (bytes == null) return;
      try {
        final text = utf8.decode(bytes, allowMalformed: true).replaceAll('\u0000', '').trim();
        final decoded = jsonDecode(text);
        if (decoded is! Map) throw const FormatException('device');
        final info = GsmHardwareInfo.fromJson(Map<String, dynamic>.from(decoded));
        hardware = info;
        done.complete(info);
      } catch (error) {
        done.completeError(error is AppException ? error : const AppException('error.decode'));
      }
    };
    try {
      await _notify(read, true);
      await _write(trigger, [0x01], preferNoResponse: true);
      return await done.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw const AppException('bt.timeout', 'BLE'),
      );
    } finally {
      _infoListener = null;
      await _notify(read, false);
    }
  }

  Future<void> setWifi(String name, String password) async {
    final write = _need(gsmWriteUuid, write: true);
    final payload = utf8.encode(jsonEncode({'name': name, 'key': password}));
    final started = _networkEpoch;
    for (final packet in gsmWifiPackets(payload)) {
      await _write(write, packet);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (_networkEpoch > started && networkStatus == 'connected') return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw const AppException('gsm.wifi_timeout');
  }

  Future<String> pushUpdate(String version) async {
    final update = _need(gsmUpdateUuid, write: true, notify: true);
    final done = Completer<String>();
    _updateListener = (value) {
      final text = utf8.decode(value, allowMalformed: true).trim();
      if (text.isEmpty || text == 'updating' || done.isCompleted) return;
      done.complete(text);
    };
    try {
      await _notify(update, true);
      await _write(update, utf8.encode(version));
      return await done.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw const AppException('bt.timeout', 'BLE'),
      );
    } finally {
      _updateListener = null;
      await _notify(update, false);
    }
  }

  Future<String> readIp() async {
    final characteristic = _need(gsmIpUuid);
    final done = Completer<String>();
    _ipWaiter = (text) {
      if (!done.isCompleted) done.complete(text);
    };
    try {
      if (ip.isNotEmpty) return ip;
      if (characteristic.properties.read) {
        try {
          final value = await characteristic.read(timeout: 5);
          final text = utf8.decode(value, allowMalformed: true).trim();
          if (text.isNotEmpty && !done.isCompleted) done.complete(text);
        } catch (_) {}
      }
      final text = await done.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw const AppException('bt.timeout', 'BLE'),
      );
      ip = text;
      _emit();
      return text;
    } finally {
      _ipWaiter = null;
    }
  }

  Future<void> writeName(String name) async {
    final characteristic = _need(gsmNameUuid, write: true);
    await _write(characteristic, [...utf8.encode(name), 0]);
    displayName = name;
    _emit();
  }

  Future<void> notifyBound() async {
    final characteristic = _need(gsmBindUuid, write: true);
    await _write(characteristic, [0x01], preferNoResponse: true);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    connected = false;
    _rssi?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await device.disconnect();
    } catch (_) {}
  }

  BluetoothCharacteristic? _find(String uuid) {
    final guid = Guid(uuid);
    for (final characteristic in _characteristics) {
      if (characteristic.uuid == guid) return characteristic;
    }
    return null;
  }

  BluetoothCharacteristic _need(String uuid, {bool write = false, bool notify = false}) {
    final guid = Guid(uuid);
    return _characteristics.firstWhere(
      (characteristic) =>
          characteristic.uuid == guid &&
          (!write ||
              characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) &&
          (!notify || characteristic.properties.notify || characteristic.properties.indicate),
      orElse: () => throw AppException('bt.missing_char', uuid),
    );
  }

  Future<void> _write(
    BluetoothCharacteristic characteristic,
    List<int> data, {
    bool preferNoResponse = false,
  }) async {
    final withoutResponse = preferNoResponse
        ? characteristic.properties.writeWithoutResponse || !characteristic.properties.write
        : !characteristic.properties.write && characteristic.properties.writeWithoutResponse;
    await characteristic.write(data, withoutResponse: withoutResponse, timeout: 8);
  }

  Future<void> _notify(BluetoothCharacteristic characteristic, bool state) async {
    if (characteristic.properties.notify || characteristic.properties.indicate) {
      await characteristic.setNotifyValue(state);
    }
  }

  void _onNetwork(List<int> value) {
    try {
      final decoded = jsonDecode(utf8.decode(value, allowMalformed: true));
      if (decoded is! Map) return;
      final status = '${decoded['status'] ?? ''}'.trim().toLowerCase();
      networkStatus = status == 'connected' || status == 'disconnected' ? status : 'unknown';
      final signal = decoded['wifi_signal'];
      wifiSignal = networkStatus == 'connected' && signal is num ? signal.round() : 0;
      _networkEpoch++;
      _emit();
    } catch (_) {}
  }

  Future<void> _readRssi() async {
    if (_closed || !connected) return;
    try {
      final rssi = await device.readRssi();
      bluetoothSignal = gsmSignalPercent(rssi);
      _emit();
    } catch (_) {}
  }

  void _emit() {
    if (!_closed) notifyListeners();
  }
}

class GsmBle extends ChangeNotifier {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<GsmNearby> nearby = [];
  bool scanning = false;
  BluetoothAdapterState adapter = BluetoothAdapterState.unknown;
  GsmLink? link;
  bool _prepared = false;
  bool _closed = false;

  Future<void> prepare() async {
    if (_prepared) return;
    if (!await FlutterBluePlus.isSupported) throw const AppException('bt.unsupported');
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await FlutterBluePlus.adapterName;
    }
    _prepared = true;
    _subscriptions.add(
      FlutterBluePlus.adapterState.listen((value) {
        adapter = value;
        _emit();
      }),
    );
    _subscriptions.add(
      FlutterBluePlus.isScanning.listen((value) {
        scanning = value;
        _emit();
      }),
    );
    _subscriptions.add(
      FlutterBluePlus.onScanResults.listen((results) {
        final next = [...nearby];
        for (final result in results) {
          final name = result.advertisementData.advName.isNotEmpty
              ? result.advertisementData.advName
              : result.device.platformName;
          if (!isGsmAdvertisedName(name)) continue;
          final id = result.device.remoteId.str;
          final index = next.indexWhere((device) => device.id == id);
          final found = GsmNearby(id, name, result.rssi);
          if (index >= 0) {
            next[index] = found;
          } else {
            next.add(found);
          }
        }
        next.sort((a, b) => b.rssi.compareTo(a.rssi));
        nearby = next;
        _emit();
      }),
    );
  }

  Future<void> startScan() async {
    await prepare();
    final state = await FlutterBluePlus.adapterState
        .where((value) => value != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 8));
    adapter = state;
    if (state != BluetoothAdapterState.on) {
      throw AppException(
        state == BluetoothAdapterState.unauthorized ? 'bt.unauthorized' : 'bt.off',
      );
    }
    nearby = [
      for (final device in FlutterBluePlus.connectedDevices)
        if (isGsmAdvertisedName(device.platformName))
          GsmNearby(device.remoteId.str, device.platformName, -50),
    ];
    _emit();
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      androidCheckLocationServices: false,
    );
  }

  Future<void> stopScan() async {
    if (_prepared) await FlutterBluePlus.stopScan();
  }

  Future<GsmLink> connect(GsmNearby found) async {
    await stopScan();
    await link?.close();
    final peripheral = BluetoothDevice.fromId(found.id);
    try {
      await peripheral.connect(timeout: const Duration(seconds: 12), mtu: null);
      final services = await peripheral.discoverServices();
      BluetoothService? service;
      for (final item in services) {
        if (item.uuid == Guid(gsmServiceUuid)) service = item;
      }
      if (service == null) throw const AppException('bt.no_service');
      final session = GsmLink(peripheral, found.name, service.characteristics);
      session.attach();
      session.startSignal();
      link = session;
      _emit();
      return session;
    } catch (error) {
      try {
        await peripheral.disconnect();
      } catch (_) {}
      if (error is AppException) rethrow;
      throw AppException('bt.connection_failed', error);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await link?.close();
    link = null;
    super.dispose();
  }

  void _emit() {
    if (!_closed) notifyListeners();
  }
}
