import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fabriclab/app_model.dart';
import 'package:fabriclab/models.dart';
import 'package:fabriclab/services/api.dart';
import 'package:fabriclab/services/bluetooth.dart';

class TestBluetooth extends FabricBluetooth {
  bool ready = true;
  int scanCalls = 0;
  @override
  bool get connectedReady => ready;
  @override
  Future<Capture> scan() async {
    scanCalls++;
    return Capture(DeviceKind.ir2210, List.filled(256, 12));
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
}
