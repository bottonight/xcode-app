import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fabriclab/app_model.dart';
import 'package:fabriclab/main.dart';
import 'package:fabriclab/models.dart';
import 'package:fabriclab/ui/home.dart';

void main() {
  Future<AppModel> createApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'english': false});
    FlutterSecureStorage.setMockInitialValues({});
    final app = AppModel();
    await tester.runAsync(app.initialize);
    return app;
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform login and registration preserve form validation', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = await createApp(tester);
      await tester.pumpWidget(FabricLabApp(app));
      await tester.pumpAndSettle();
      expect(find.text('FabricLab'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      final switcher = find.text(app.t('auth.to_register'));
      await tester.ensureVisible(switcher);
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(find.text(app.t('auth.register_title')), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(6));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('Home, workbench and language work at narrow width without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await createApp(tester);
    app.session = const UserSession(
      userId: '1',
      phone: '13800138000',
      email: '',
      username: 'Test',
      token: 'test',
      adminLevel: 2,
    );
    await tester.pumpWidget(FabricLabApp(app));
    await tester.pumpAndSettle();
    expect(find.text(app.t('project.composition')), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    app.selectedDevice = const NearbyDevice('test', 'IR2210 Test', DeviceKind.ir2210, -55);
    app.chooseMode(const AnalysisMode('cotton', '成分分析', 'Composition', 0));
    await tester.pumpAndSettle();
    expect(find.text(app.t('workbench.settings')), findsOneWidget);
    expect(find.text(app.t('workbench.scan_and_predict')), findsNothing);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text(app.t('workbench.device_settings')), findsOneWidget);
    expect(find.text(app.t('workbench.calibration')), findsOneWidget);
    await tester.tap(find.text(app.t('common.done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(app.t('scan.multiple')));
    await tester.pumpAndSettle();
    expect(app.multiple, true);
    expect(app.captures, isEmpty);
    expect(find.byIcon(Icons.filter_center_focus), findsNothing);
    expect(find.text(app.t('workbench.tips_title')), findsOneWidget);
    await tester.tap(find.text(app.t('workbench.tips_title')));
    await tester.pumpAndSettle();
    expect(find.textContaining(app.t('workbench.tip_1')), findsOneWidget);
    expect(find.text(app.t('workbench.start_scan')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(app.t('tab.account')));
    await tester.pumpAndSettle();
    expect(find.text('Test'), findsOneWidget);
    await tester.runAsync(() => app.setLanguage(true));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  testWidgets('Global errors appear once and can be dismissed', (tester) async {
    final app = await createApp(tester);
    await tester.pumpWidget(FabricLabApp(app));
    await tester.pumpAndSettle();
    await app.perform(() async {
      throw const AppException('error.invalid_email');
    });
    await tester.pumpAndSettle();
    expect(find.text(app.t('error.invalid_email')), findsOneWidget);
    await tester.tap(find.text(app.t('common.ok')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  testWidgets('Device settings clearly present unavailable writes', (tester) async {
    final app = await createApp(tester);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DeviceSettingsPage(app))));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
