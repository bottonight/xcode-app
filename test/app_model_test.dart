import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fabriclab/app_model.dart';
import 'package:fabriclab/gsm.dart';
import 'package:fabriclab/models.dart';
import 'package:fabriclab/services/api.dart';
import 'package:fabriclab/services/bluetooth.dart';
import 'package:fabriclab/services/gsm_api.dart';
import 'package:fabriclab/ui/design.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestBluetooth extends FabricBluetooth {
  bool ready = true;
  int scanCalls = 0;
  int batteryReads = 0;
  int batteryValue = 80;
  @override
  bool get connectedReady => ready;
  @override
  Future<Capture> scan() async {
    scanCalls++;
    return Capture(DeviceKind.ir2210, List.filled(256, 12));
  }

  @override
  Future<int> readBattery() async {
    batteryReads++;
    return batteryValue;
  }
}

class _CountingDevicesApi extends FabricApi {
  int deviceLoads = 0;
  @override
  Future<List<ManagedDevice>> devices(UserSession session) async {
    deviceLoads++;
    return [ManagedDevice('sn', '成分$deviceLoads', deviceLoads, const {}, true)];
  }
}

class _CountingGsmApi extends GsmApi {
  int deviceLoads = 0;
  @override
  Future<List<GsmDevice>> devices() async {
    deviceLoads++;
    return [GsmDevice(id: 'g1', name: '克重$deviceLoads')];
  }
}

class _FixedGsmApi extends GsmApi {
  _FixedGsmApi(this.result);
  final List<GsmDevice> result;
  @override
  Future<List<GsmDevice>> devices() async => result;
}

class _FailingGsmApi extends GsmApi {
  @override
  Future<List<GsmDevice>> devices() async => throw const AppException('error.http', 500);
}

class TestApi extends FabricApi {
  Completer<String>? pendingPrediction;
  int predictions = 0;
  @override
  Future<PredictionOutcome> predict(
    List<Capture> captures,
    DeviceIdentity identity,
    AnalysisMode mode,
    UserSession session,
    bool defaultReference,
    List<int>? builtin,
  ) async {
    predictions++;
    final result = pendingPrediction == null ? 'Cotton 100%' : await pendingPrediction!.future;
    return PredictionOutcome(result);
  }

  @override
  Future<PagedItems<PredictionHistoryItem>> predictionHistory(
    String serial, {
    int page = 1,
    int pageSize = 10,
  }) async {
    return const PagedItems(items: []);
  }
}

void main() {
  AppModel configured(TestApi api, TestBluetooth ble) => AppModel(api: api, bluetooth: ble)
    ..session = const UserSession(
      userId: '1',
      phone: '13800138000',
      email: '',
      username: 'Test',
      token: 't',
      adminLevel: 0,
    )
    ..selectedDevice = const NearbyDevice('device', 'IR2210', DeviceKind.ir2210, -50)
    ..identity = const DeviceIdentity('IR2210', 'serial')
    ..mode = const AnalysisMode('cotton', '棉', 'Cotton', 0)
    ..route = HomeRoute.workbench;

  test('Single scan predicts immediately; multi scans require 2 and stop at 9', () async {
    final api = TestApi();
    final ble = TestBluetooth();
    final app = configured(api, ble);
    expect(await app.scan(), true);
    expect(app.result, 'Cotton 100%');
    expect(api.predictions, 1);
    app.multiple = true;
    app.clearMeasurements();
    await app.scan();
    expect(app.result, null);
    expect(await app.predictMultiple(), false);
    for (var i = 1; i < 9; i++) {
      await app.scan();
    }
    expect(app.captures.length, 9);
    final previousCalls = ble.scanCalls;
    expect(await app.scan(), false);
    expect(ble.scanCalls, previousCalls);
    expect(await app.predictMultiple(), true);
    expect(api.predictions, 2);
    app.dispose();
  });
  test('Disconnect during prediction cannot restore an obsolete result', () async {
    final api = TestApi()..pendingPrediction = Completer<String>();
    final ble = TestBluetooth();
    final app = configured(api, ble);
    final scanning = app.scan();
    await Future<void>.delayed(Duration.zero);
    ble.ready = false;
    ble.onDisconnect!();
    api.pendingPrediction!.complete('Obsolete result');
    expect(await scanning, false);
    expect(app.result, null);
    expect(app.route, HomeRoute.discovery);
    expect(app.busy, false);
    app.dispose();
  });
  test('Concurrent actions are rejected while acquisition is processing', () async {
    final api = TestApi()..pendingPrediction = Completer<String>();
    final ble = TestBluetooth();
    final app = configured(api, ble);
    final scanning = app.scan();
    await Future<void>.delayed(Duration.zero);
    expect(await app.scan(), false);
    expect(ble.scanCalls, 1);
    expect(ble.acceptsHardwareScan!(), false);
    api.pendingPrediction!.complete('Cotton');
    await scanning;
    expect(ble.acceptsHardwareScan!(), true);
    app.dispose();
  });
  test('Stored sessions keep their token without a client-side expiry field', () {
    const session = UserSession(
      userId: '1',
      phone: '13800138000',
      email: '',
      username: 'Test',
      token: 't',
      adminLevel: 0,
    );
    expect(session.toJson().containsKey('savedAt'), isFalse);
    expect(
      UserSession.fromJson({...session.toJson(), 'savedAt': '2020-01-01T00:00:00.000'}).token,
      't',
    );
    expect(session.copyWith(username: 'New').username, 'New');
  });
  test('Default language follows system language, not region', () {
    expect(isChineseLanguage(const Locale('zh')), isTrue);
    expect(isChineseLanguage(const Locale('zh', 'CN')), isTrue);
    expect(isChineseLanguage(const Locale('zh', 'US')), isTrue);
    expect(
      isChineseLanguage(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
      isTrue,
    );
    expect(isChineseLanguage(const Locale('en', 'CN')), isFalse);
    expect(isChineseLanguage(const Locale('ja')), isFalse);
  });
  test('Device page requests both lists only on the first visit and after binding', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final api = _CountingDevicesApi();
    final gsm = _CountingGsmApi();
    final app = AppModel(api: api, bluetooth: TestBluetooth(), gsmApi: gsm)
      ..session = const UserSession(
        userId: '1',
        phone: '13800138000',
        email: '',
        username: 'Test',
        token: 't',
        adminLevel: 0,
      );

    await app.showDevices();
    expect(api.deviceLoads, 1);
    expect(gsm.deviceLoads, 1);
    expect(app.managedDevices.single.name, '成分1');
    expect(app.gsmDevices.single.name, '克重1');

    await app.showDevices();
    expect(api.deviceLoads, 1);
    expect(gsm.deviceLoads, 1);

    await app.syncDevicesAfterBind();
    expect(api.deviceLoads, 2);
    expect(gsm.deviceLoads, 2);
    expect(app.managedDevices.single.name, '成分2');
    expect(app.gsmDevices.single.name, '克重2');

    final reopenedApi = _CountingDevicesApi();
    final reopenedGsm = _CountingGsmApi();
    final reopened = AppModel(api: reopenedApi, bluetooth: TestBluetooth(), gsmApi: reopenedGsm)
      ..session = app.session;
    await reopened.showDevices();
    expect(reopenedApi.deviceLoads, 1);
    expect(reopenedGsm.deviceLoads, 1);
    await reopened.showDevices();
    expect(reopenedApi.deviceLoads, 1);
    expect(reopenedGsm.deviceLoads, 1);
  });

  test('GSM device refresh overwrites the cache with the server list', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const account = '13800138000';
    SharedPreferences.setMockInitialValues({
      'gsm-devices-$account': jsonEncode([
        {'device_id': 'gone', 'device_name': '已解绑'},
        {'device_id': 'g1', 'device_name': '旧名'},
      ]),
    });
    final app = AppModel(
      api: _CountingDevicesApi(),
      bluetooth: TestBluetooth(),
      gsmApi: _FixedGsmApi(const [
        GsmDevice(id: 'g1', name: '克重1'),
        GsmDevice(id: 'g2', name: '克重2'),
      ]),
    )..session = const UserSession(
      userId: '1',
      phone: account,
      email: '',
      username: 'Test',
      token: 't',
      adminLevel: 0,
    );

    await app.refreshGsmDevices();

    expect(app.gsmDevices.map((device) => '${device.id}:${device.name}'), ['g1:克重1', 'g2:克重2']);
    final stored = jsonDecode(
      (await SharedPreferences.getInstance()).getString('gsm-devices-$account')!,
    );
    expect(stored, [
      {'device_id': 'g1', 'device_name': '克重1'},
      {'device_id': 'g2', 'device_name': '克重2'},
    ]);
  });

  test('GSM device refresh keeps the cache when the server request fails', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const account = '13800138000';
    final cached = jsonEncode([
      {'device_id': 'g1', 'device_name': '克重1'},
    ]);
    SharedPreferences.setMockInitialValues({'gsm-devices-$account': cached});
    final app = AppModel(
      api: _CountingDevicesApi(),
      bluetooth: TestBluetooth(),
      gsmApi: _FailingGsmApi(),
    )..session = const UserSession(
      userId: '1',
      phone: account,
      email: '',
      username: 'Test',
      token: 't',
      adminLevel: 0,
    );

    await app.refreshGsmDevices();

    expect(app.gsmDevices.single.id, 'g1');
    expect((await SharedPreferences.getInstance()).getString('gsm-devices-$account'), cached);
  });

  test('Battery color is green at 50+, yellow from 20, red below 20', () {
    expect(AppModel.batteryPollInterval, const Duration(minutes: 2));
    expect(batteryColor(100), batteryHigh);
    expect(batteryColor(50), batteryHigh);
    expect(batteryColor(49), batteryMedium);
    expect(batteryColor(20), batteryMedium);
    expect(batteryColor(19), batteryLow);
    expect(batteryIconFor(80), Icons.battery_full);
    expect(batteryIconFor(30), Icons.battery_3_bar);
    expect(batteryIconFor(10), Icons.battery_alert);
    expect(batteryIconFor(null), Icons.battery_unknown);
  });
}
