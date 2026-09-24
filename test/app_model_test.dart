import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fabriclab/app_model.dart';
import 'package:fabriclab/models.dart';
import 'package:fabriclab/services/api.dart';
import 'package:fabriclab/services/bluetooth.dart';
import 'package:fabriclab/ui/design.dart';

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

class TestApi extends FabricApi {
  Completer<String>? pendingPrediction;
  int predictions = 0;
  @override
  Future<String> predict(
    List<Capture> captures,
    DeviceIdentity identity,
    AnalysisMode mode,
    UserSession session,
    bool defaultReference,
    List<int>? builtin,
  ) async {
    predictions++;
    return pendingPrediction == null ? 'Cotton 100%' : pendingPrediction!.future;
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
