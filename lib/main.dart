import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_model.dart';
import 'models.dart';
import 'ui/auth.dart';
import 'ui/design.dart';
import 'ui/devices.dart';
import 'ui/gsm_history.dart';
import 'ui/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppModel();
  runApp(FabricLabApp(app));
  unawaited(app.initialize());
}

class FabricLabApp extends StatefulWidget {
  const FabricLabApp(this.app, {super.key});
  final AppModel app;
  @override
  State<FabricLabApp> createState() => _FabricLabAppState();
}

class _FabricLabAppState extends State<FabricLabApp> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  bool showingMessage = false;
  bool hadSession = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(changed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(changed);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(widget.app.bluetooth.stopScan());
    }
  }

  void changed() {
    final app = widget.app;
    if (hadSession && app.session == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => navigator.currentState?.popUntil((r) => r.isFirst),
      );
    }
    hadSession = app.session != null;
    if (app.message == null || showingMessage) return;
    showingMessage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = navigator.currentContext;
      final message = app.message;
      app.message = null;
      if (context != null && context.mounted && message != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(app.t('common.alert')),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(app.t('common.ok'))),
            ],
          ),
        );
      }
      showingMessage = false;
      if (mounted && app.message != null) changed();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app,
    builder: (context, _) {
      final app = widget.app;
      return MaterialApp(
        title: 'FabricLab',
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        theme: fabricTheme(),
        locale: Locale(app.english ? 'en' : 'zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: !app.initialized
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : app.session == null
            ? AuthPage(app)
            : MainShell(app),
        builder: (context, child) => Stack(
          children: [
            child!,
            if (app.busy) ...[
              const ModalBarrier(dismissible: false, color: Color(0x29000000)),
              Center(
                child: Material(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            app.t(app.busyKey),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class MainShell extends StatefulWidget {
  const MainShell(this.app, {super.key});
  final AppModel app;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int rootTab = 0;

  String _title(AppModel app) {
    if (app.area == AppArea.root) {
      return rootTab == 1 ? app.t('account.title') : app.t('project.home');
    }
    if (app.area == AppArea.gsm) return app.t('gsm.history_title');
    if (app.areaTab == 1) return app.t('tab.composition_devices');
    return switch (app.route) {
      HomeRoute.modes => app.t('mode.title'),
      HomeRoute.workbench => app.mode?.title(app.english) ?? app.t('workbench.inspect'),
      _ => app.t('discovery.title'),
    };
  }

  bool _stepsBack(AppModel app) =>
      app.area == AppArea.composition &&
      app.areaTab == 0 &&
      app.route != HomeRoute.discovery &&
      app.route != HomeRoute.projects;

  Future<void> _back(AppModel app) async {
    if (app.busy) return;
    if (_stepsBack(app)) {
      await app.back();
      return;
    }
    await app.exitToHome();
  }

  Future<void> _select(AppModel app, int index) async {
    if (app.busy) return;
    if (app.area == AppArea.root) {
      if (rootTab == index) return;
      setState(() => rootTab = index);
      if (index != 0) await app.bluetooth.stopScan();
      return;
    }
    if (app.areaTab == index) return;
    final leavingDiscovery =
        app.area == AppArea.composition && app.areaTab == 0 && app.route == HomeRoute.discovery;
    app.selectAreaTab(index);
    if (leavingDiscovery) await app.bluetooth.stopScan();
    if (app.area == AppArea.composition && index == 1) await app.showDevices();
    if (app.area == AppArea.composition && index == 0 && app.route == HomeRoute.discovery) {
      await app.perform(app.bluetooth.startScan);
    }
  }

  Widget _body(AppModel app) => switch (app.area) {
    AppArea.root => rootTab == 0 ? HomePage(app) : AccountPage(app),
    AppArea.composition => app.areaTab == 0 ? HomePage(app, flow: true) : DevicesPage(app),
    AppArea.gsm => GsmHistoryPage(app),
  };

  List<BottomNavigationBarItem> _items(AppModel app) => switch (app.area) {
    AppArea.root => [
      BottomNavigationBarItem(icon: const Icon(Icons.home_outlined), label: app.t('tab.home')),
      BottomNavigationBarItem(
        icon: const Icon(Icons.account_circle_outlined),
        label: app.t('tab.account'),
      ),
    ],
    AppArea.composition => [
      BottomNavigationBarItem(icon: const Icon(Icons.bluetooth), label: app.t('tab.connect')),
      BottomNavigationBarItem(
        icon: const Icon(Icons.sensors),
        label: app.t('tab.composition_devices'),
      ),
    ],
    AppArea.gsm => const [],
  };

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final inside = app.area != AppArea.root;
    final gsm = app.area == AppArea.gsm;
    final current = inside ? app.areaTab : rootTab;
    return PopScope(
      canPop: !inside && !app.busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inside && !app.busy) unawaited(_back(app));
      },
      child: Scaffold(
        appBar: gsm
            ? null
            : AppBar(
                title: Text(_title(app)),
                leading: inside
                    ? IconButton(
                        tooltip: app.t('common.back'),
                        onPressed: app.busy ? null : () => _back(app),
                        icon: const Icon(Icons.chevron_left, color: indigo),
                      )
                    : null,
              ),
        body: SafeArea(top: false, child: _body(app)),
        bottomNavigationBar: gsm
            ? null
            : BottomNavigationBar(
                elevation: 0,
                currentIndex: current,
                selectedItemColor: indigo,
                unselectedItemColor: muted,
                backgroundColor: Colors.white,
                onTap: (index) => _select(app, index),
                items: _items(app),
              ),
      ),
    );
  }
}
