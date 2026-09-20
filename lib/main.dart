import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_model.dart';
import 'models.dart';
import 'ui/auth.dart';
import 'ui/design.dart';
import 'ui/devices.dart';
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
  int tab = 0;
  String get title {
    final app = widget.app;
    if (tab == 1) return app.t('devices.title');
    if (tab == 2) return app.t('account.title');
    return switch (app.route) {
      HomeRoute.projects => app.t('project.home'),
      HomeRoute.discovery => app.t('discovery.title'),
      HomeRoute.modes => app.t('mode.title'),
      HomeRoute.workbench => app.mode?.title(app.english) ?? app.t('workbench.inspect'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final canBack = tab == 0 && app.route != HomeRoute.projects;
    return PopScope(
      canPop: !canBack && !app.busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canBack && !app.busy) app.back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: canBack
              ? IconButton(
                  tooltip: app.t('common.back'),
                  onPressed: app.busy ? null : app.back,
                  icon: const Icon(Icons.chevron_left, color: indigo),
                )
              : null,
        ),
        body: SafeArea(
          top: false,
          child: switch (tab) {
            0 => HomePage(app),
            1 => DevicesPage(app),
            _ => AccountPage(app),
          },
        ),
        bottomNavigationBar: BottomNavigationBar(
          elevation: 0,
          currentIndex: tab,
          selectedItemColor: indigo,
          unselectedItemColor: muted,
          backgroundColor: Colors.white,
          onTap: (index) async {
            if (app.busy || tab == index) return;
            setState(() => tab = index);
            if (index != 0) await app.bluetooth.stopScan();
            if (index == 1) await app.loadDevices();
          },
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              label: app.t('tab.home'),
            ),
            BottomNavigationBarItem(icon: const Icon(Icons.sensors), label: app.t('tab.devices')),
            BottomNavigationBarItem(
              icon: const Icon(Icons.account_circle_outlined),
              label: app.t('tab.account'),
            ),
          ],
        ),
      ),
    );
  }
}
