// Optional local render utility, not part of production or the normal test suite.
// flutter test tool/ui_preview_test.dart --dart-define=UI_FONT_PATH=/path/to/font.ttf
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fabriclab/app_model.dart';
import 'package:fabriclab/main.dart';
import 'package:fabriclab/models.dart';
import 'package:fabriclab/ui/design.dart';
import 'package:fabriclab/ui/devices.dart';

void main() {
  testWidgets('Render migrated screens using local fixtures', (tester) async {
    const fontPath = String.fromEnvironment('UI_FONT_PATH');
    if (fontPath.isNotEmpty) {
      await tester.runAsync(() async {
        for (final family in ['Roboto', 'Ahem']) {
          final font = FontLoader(family)
            ..addFont(File(fontPath).readAsBytes().then((b) => ByteData.sublistView(b)));
          await font.load();
        }
      });
    }
    await tester.runAsync(() async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // This is a flutter_test entry point kept outside test/ to avoid routine rendering.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'english': false});
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
    final app = AppModel();
    await tester.runAsync(app.initialize);
    final boundary = GlobalKey();
    Future<void> capture(String name, Widget widget) async {
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: widget));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/previews/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('login', FabricLabApp(app));
    app.session = const UserSession(
      userId: 'preview',
      phone: '13800138000',
      email: '',
      username: 'FabricLab',
      token: 'preview',
      adminLevel: 2,
    );
    app.clearMeasurements();
    await capture('projects', FabricLabApp(app));
    app.route = HomeRoute.discovery;
    app.bluetooth.nearby = [
      const NearbyDevice('preview', 'NIR Nano', DeviceKind.nir, -52),
      const NearbyDevice('ir', 'IR2210', DeviceKind.ir2210, -65),
    ];
    app.clearMeasurements();
    await capture('discovery', FabricLabApp(app));
    app.selectedDevice = app.bluetooth.nearby.last;
    app.chooseMode(const AnalysisMode('cotton', '成分分析', 'Composition', 32));
    await capture('workbench', FabricLabApp(app));
    final device = ManagedDevice('IR2210-000126', 'IR2210', 32, {
      '2026-06': 18,
      '2026-07': 42,
      '2026-08': 28,
      '2026-09': 32,
    }, true);
    await capture(
      'device',
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: fabricTheme(),
        home: DeviceDetailPage(app, device),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
