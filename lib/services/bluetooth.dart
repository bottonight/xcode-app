import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models.dart';
import 'ble_protocol.dart';

enum _Operation {
  idle,
  identity,
  builtin,
  scanning,
  collecting,
  hardwareScanning,
  hardwareCollecting,
}

class FabricBluetooth extends ChangeNotifier {
  static String nir(String code) => '434841$code-444c-5020-4e49-52204e616e6f';
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<StreamSubscription<dynamic>> _connectionSubscriptions = [];
  final List<BluetoothCharacteristic> _characteristics = [];
  final NirAssembler _nir = NirAssembler();
  final IrAssembler _ir = IrAssembler();
  final Map<int, List<int>> _groups = {};
  BluetoothDevice? _device;
  NearbyDevice? connected;
  List<NearbyDevice> nearby = [];
  BluetoothAdapterState adapter = BluetoothAdapterState.unknown;
  bool scanning = false;
  bool _initialized = false;
  bool _disposed = false;
  _Operation _operation = _Operation.idle;
  Completer<List<int>>? _pending;
  Timer? _timer;
  List<int>? _builtin;
  VoidCallback? onHardwareStart, onProcessing, onDisconnect;
  void Function(Capture)? onHardwareCapture;
  void Function(Object)? onError;
  bool Function()? acceptsHardwareScan;
  bool get connectedReady => _device != null && connected != null;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (!await FlutterBluePlus.isSupported) {
      throw const AppException('bt.unsupported');
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Android 12+ must grant CONNECT before adapterState can read the radio.
      // This plugin call requests that permission before caching adapter state.
      await FlutterBluePlus.adapterName;
    }
    _initialized = true;
    _subscriptions.add(
      FlutterBluePlus.adapterState.listen((value) {
        adapter = value;
        if (value != BluetoothAdapterState.on) {
          _fail(const AppException('bt.not_ready'));
        }
        _changed();
      }),
    );
    _subscriptions.add(
      FlutterBluePlus.isScanning.listen((value) {
        scanning = value;
        _changed();
      }),
    );
    _subscriptions.add(
      FlutterBluePlus.onScanResults.listen((results) {
        nearby =
            results
                .map((r) {
                  final name = r.advertisementData.advName.isNotEmpty
                      ? r.advertisementData.advName
                      : r.device.platformName;
                  final kind = DeviceKind.identify(name);
                  return kind == null
                      ? null
                      : NearbyDevice(r.device.remoteId.str, name, kind, r.rssi);
                })
                .whereType<NearbyDevice>()
                .toList()
              ..sort((a, b) => b.rssi.compareTo(a.rssi));
        _changed();
      }, onError: (Object error) => onError?.call(error)),
    );
  }

  Future<void> startScan() async {
    await initialize();
    final state = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 8));
    if (state != BluetoothAdapterState.on) {
      throw AppException(
        state == BluetoothAdapterState.unauthorized ? 'bt.unauthorized' : 'bt.off',
      );
    }
    nearby = [];
    _changed();
    // Legacy devices may advertise only a name, so filter names after discovery.
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidCheckLocationServices: false,
    );
  }

  Future<void> stopScan() async {
    if (_initialized) await FlutterBluePlus.stopScan();
  }

  BluetoothCharacteristic _char(
    String uuid, {
    bool read = false,
    bool write = false,
    bool notify = false,
  }) {
    return _characteristics.firstWhere(
      (c) =>
          c.uuid == Guid(uuid) &&
          (!read || c.properties.read) &&
          (!write || c.properties.write || c.properties.writeWithoutResponse) &&
          (!notify || c.properties.notify || c.properties.indicate),
      orElse: () => throw AppException('bt.missing_char', uuid),
    );
  }

  Future<void> _write(String uuid, List<int> data) async {
    final c = _char(uuid, write: true);
    await c.write(data, withoutResponse: !c.properties.write, timeout: 8);
  }

  Future<void> connect(NearbyDevice device) async {
    await stopScan();
    await disconnect();
    final peripheral = BluetoothDevice.fromId(device.id);
    _device = peripheral;
    try {
      await peripheral.connect(timeout: const Duration(seconds: 12), mtu: null);
      _connectionSubscriptions.add(
        peripheral.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected && _device == peripheral) {
            _fail(const AppException('bt.device_lost'));
            connected = null;
            _builtin = null;
            _characteristics.clear();
            onDisconnect?.call();
            _changed();
          }
        }),
      );
      final services = await peripheral.discoverServices();
      _characteristics.addAll(services.expand((s) => s.characteristics));
      final notifications = device.kind == DeviceKind.nir
          ? [nir('1d'), nir('28'), nir('10')]
          : ['ffe2'];
      for (final uuid in notifications) {
        // Some NIR firmware exposes separate write and notify handles with the same UUID.
        final characteristic = _char(uuid, notify: true);
        _connectionSubscriptions.add(
          characteristic.onValueReceived.listen((data) {
            try {
              _receive(uuid, data);
            } catch (error) {
              _fail(error);
            }
          }, onError: (Object error) => _fail(error)),
        );
        await characteristic.setNotifyValue(true);
      }
      connected = device;
      _changed();
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  Future<List<int>> _exchange(
    _Operation operation,
    Future<void> Function() send, {
    int seconds = 30,
  }) async {
    if (!connectedReady) throw const AppException('bt.device_lost');
    if (_operation != _Operation.idle) {
      throw const AppException('bt.busy_other');
    }
    _operation = operation;
    _nir.reset();
    _ir.reset();
    _groups.clear();
    final pending = Completer<List<int>>();
    _pending = pending;
    _armTimeout(seconds);
    // Attach the receiver before sending, including synchronous notification responses.
    unawaited(
      Future<void>.sync(send).catchError((Object error) {
        if (identical(_pending, pending)) _fail(error);
      }),
    );
    return pending.future;
  }

  void _armTimeout(int seconds) {
    _timer?.cancel();
    _timer = Timer(
      Duration(seconds: seconds),
      () => _fail(const AppException('bt.timeout', 'BLE')),
    );
  }

  void _complete(List<int> bytes) {
    final hardware = _operation == _Operation.hardwareCollecting;
    _timer?.cancel();
    _operation = _Operation.idle;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(bytes);
    if (hardware && connected != null) {
      onHardwareCapture?.call(Capture(connected!.kind, bytes));
    }
  }

  void _fail(Object error) {
    final hardware =
        _operation == _Operation.hardwareScanning || _operation == _Operation.hardwareCollecting;
    _timer?.cancel();
    _operation = _Operation.idle;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
    if (hardware) onError?.call(error);
  }

  bool _beginHardware(_Operation operation) {
    if (connected == null || !(acceptsHardwareScan?.call() ?? false)) {
      return false;
    }
    _operation = operation;
    _groups.clear();
    _nir.reset();
    onHardwareStart?.call();
    _armTimeout(30);
    return true;
  }

  void _receive(String uuid, List<int> bytes) {
    if (bytes.isEmpty) return;
    if (uuid == nir('1d')) {
      if (_operation == _Operation.idle && !_beginHardware(_Operation.hardwareScanning)) {
        return;
      }
      if (bytes.first != 255 ||
          bytes.length < 5 ||
          ![_Operation.scanning, _Operation.hardwareScanning].contains(_operation)) {
        return;
      }
      _operation = _operation == _Operation.hardwareScanning
          ? _Operation.hardwareCollecting
          : _Operation.collecting;
      _nir.reset();
      _armTimeout(15);
      onProcessing?.call();
      unawaited(
        _write(nir('27'), bytes.sublist(1, 5)).catchError((Object e) {
          _fail(e);
        }),
      );
    } else if ((uuid == nir('10') && _operation == _Operation.builtin) ||
        (uuid == nir('28') &&
            [_Operation.collecting, _Operation.hardwareCollecting].contains(_operation))) {
      final result = _nir.feed(bytes);
      if (result != null) _complete(result);
    } else if (uuid == 'ffe2') {
      for (final frame in _ir.feed(bytes)) {
        final address = IrProtocol.address(frame);
        if (address == 0x4000300A && _operation == _Operation.idle) {
          _beginHardware(_Operation.hardwareCollecting);
        } else if (frame.length >= 20) {
          final isIdentity = address == 0x40003007 && _operation == _Operation.identity;
          final isScan =
              address == 0x40003005 &&
              [_Operation.collecting, _Operation.hardwareCollecting].contains(_operation);
          if (!isIdentity && !isScan) continue;
          final group = frame[10];
          if (group < 1 || group > (isIdentity ? 2 : 64)) continue;
          if (isScan && _groups.isEmpty) onProcessing?.call();
          _groups[group] = frame.sublist(11, 19);
          if (isIdentity && _groups.length == 2) {
            _complete([..._groups[1]!, ..._groups[2]!]);
          }
          if (isScan && _groups.length == 64) {
            _complete(IrProtocol.spectrum(_groups));
          }
        }
      }
    }
  }

  Future<DeviceIdentity> readIdentity() async {
    final device = connected;
    if (device == null) throw const AppException('bt.device_lost');
    if (device.kind == DeviceKind.nir) {
      final serial = await _char('2a25', read: true).read(timeout: 6);
      if (serial.isEmpty) throw const AppException('bt.ir_empty_sn');
      String? system;
      if (_characteristics.any((c) => c.uuid == Guid('2a23') && c.properties.read)) {
        system = _hex(await _char('2a23', read: true).read(timeout: 6));
      }
      return DeviceIdentity(device.name, _hex(serial), mac: device.id, uuid: system);
    }
    final bytes = await _exchange(
      _Operation.identity,
      () => _write('ffe1', IrProtocol.command(0x40003007, [0, 16])),
      seconds: 6,
    );
    final serial = ascii.decode(bytes).replaceAll(RegExp(r'^[\x00-\x20]+|[\x00-\x20]+$'), '');
    if (serial.isEmpty) throw const AppException('bt.ir_empty_sn');
    return DeviceIdentity(device.name, serial);
  }

  String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  Future<List<int>> readBuiltin() async {
    if (_builtin != null) return _builtin!;
    return _builtin = await _exchange(
      _Operation.builtin,
      () => _write(nir('0f'), [0]),
      seconds: 15,
    );
  }

  Future<Capture> scan() async {
    final kind = connected?.kind;
    if (kind == null) throw const AppException('bt.device_lost');
    final data = await _exchange(
      kind == DeviceKind.nir ? _Operation.scanning : _Operation.collecting,
      () => kind == DeviceKind.nir
          ? _write(nir('1d'), [0])
          : _write('ffe1', IrProtocol.command(0x40003005, [1, 0])),
    );
    return Capture(kind, data);
  }

  Future<void> disconnect() async {
    _fail(const AppException('bt.device_lost'));
    final device = _device;
    _device = null;
    connected = null;
    _builtin = null;
    for (final subscription in _connectionSubscriptions) {
      await subscription.cancel();
    }
    _connectionSubscriptions.clear();
    _characteristics.clear();
    _nir.reset();
    _ir.reset();
    _groups.clear();
    if (device != null) await device.disconnect();
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(stopScan());
    unawaited(disconnect());
    super.dispose();
  }
}
