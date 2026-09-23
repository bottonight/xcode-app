import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services/api.dart';
import 'services/bluetooth.dart';

class AppModel extends ChangeNotifier {
  AppModel({FabricApi? api, FabricBluetooth? bluetooth})
    : api = api ?? FabricApi(),
      bluetooth = bluetooth ?? FabricBluetooth() {
    this.bluetooth.addListener(notifyListeners);
    this.bluetooth.acceptsHardwareScan = () =>
        !busy && route == HomeRoute.workbench && (!multiple || captures.length < 9);
    this.bluetooth.onHardwareStart = () {
      busy = true;
      busyKey = 'busy.scanning';
      notifyListeners();
    };
    this.bluetooth.onProcessing = () {
      busyKey = 'busy.processing_data';
      notifyListeners();
    };
    this.bluetooth.onHardwareCapture = (capture) async {
      try {
        await _accept(capture);
      } catch (e) {
        await _handleError(e);
      } finally {
        busy = false;
        notifyListeners();
      }
    };
    this.bluetooth.onError = (error) {
      unawaited(_handleError(error));
      busy = false;
      notifyListeners();
    };
    this.bluetooth.onDisconnect = () {
      _clearDevice();
      route = HomeRoute.discovery;
      message = t('bt.device_lost');
      notifyListeners();
    };
  }
  final FabricApi api;
  final FabricBluetooth bluetooth;
  // Keep the native app's Keychain service/account so iOS upgrades can reuse a session.
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'com.fabriceyes.fabriclab',
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  SharedPreferences? _preferences;
  final Map<String, Map<String, dynamic>> _translations = {};
  bool initialized = false,
      busy = false,
      multiple = false,
      defaultReference = true,
      pendingBinding = false;
  bool english = false;
  String busyKey = 'busy.processing';
  String? message, result;
  DateTime? resultTime;
  UserSession? session;
  HomeRoute route = HomeRoute.projects;
  NearbyDevice? selectedDevice;
  DeviceIdentity? identity;
  AnalysisMode? mode;
  List<AnalysisMode> modes = [];
  List<Capture> captures = [];
  List<ManagedDevice> managedDevices = [];
  bool get allowsPhone =>
      WidgetsBinding.instance.platformDispatcher.locale.countryCode?.toUpperCase() == 'CN';
  String t(String key, [Object? value]) {
    final text = (_translations[english ? 'en' : 'zh']?[key] ?? key) as String;
    return value == null ? text : text.replaceFirst(RegExp(r'%[@d]'), '$value');
  }

  Future<void> initialize() async {
    for (final language in ['zh', 'en']) {
      final source = await rootBundle.loadString('assets/l10n/$language.json');
      _translations[language] =
          jsonDecode(source.replaceFirst('\uFEFF', '')) as Map<String, dynamic>;
    }
    try {
      _preferences = await SharedPreferences.getInstance();
      english = _preferences!.getBool('english') ?? !allowsPhone;
      api.language = english ? 'en' : 'zh-Hans';
      final stored = await _secure.read(key: 'user-session');
      if (stored != null) {
        final restored = UserSession.fromJson(jsonDecode(stored) as Map<String, dynamic>);
        if (restored.token.isEmpty) {
          await _secure.delete(key: 'user-session');
        } else {
          await _restoreWithAutoLogin(restored.token);
        }
      }
    } catch (_) {
      api.token = null;
      session = null;
      message = t('error.auto_login_failed');
    }
    initialized = true;
    notifyListeners();
  }

  Future<void> _restoreWithAutoLogin(String token) async {
    api.token = token;
    try {
      final restored = await api.autoLogin(token);
      await _persist(restored);
    } on AppException catch (error) {
      api.token = null;
      session = null;
      if (error.key == 'error.unauthorized') {
        await _secure.delete(key: 'user-session');
        message = t('error.unauthorized');
      } else {
        message = error.key == 'server' ? '${error.detail}' : t('error.auto_login_failed');
      }
    } catch (_) {
      api.token = null;
      session = null;
      message = t('error.auto_login_failed');
    }
  }

  Future<void> _persist(UserSession value) async {
    session = value;
    api.token = value.token;
    await _secure.write(key: 'user-session', value: jsonEncode(value.toJson()));
  }

  Future<void> setLanguage(bool value) async {
    english = value;
    api.language = value ? 'en' : 'zh-Hans';
    notifyListeners();
    await _preferences?.setBool('english', value);
  }

  Future<void> _handleError(Object error) async {
    if (error is AppException && error.key == 'error.unauthorized') {
      await signOut();
    }
    message = error is AppException
        ? (error.key == 'server' ? '${error.detail}' : t(error.key, error.detail))
        : error is TimeoutException
        ? t('bt.timeout', t('busy.processing'))
        : t('error.connect', '$error');
    notifyListeners();
  }

  Future<bool> perform(Future<void> Function() action, {String title = 'busy.processing'}) async {
    if (busy) return false;
    busy = true;
    busyKey = title;
    message = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      await _handleError(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> authenticate(
    String account,
    String password, {
    String? username,
    String? confirm,
    String? code,
    String company = '',
    String industry = '',
  }) => perform(() async {
    if (password.length < 6) throw const AppException('error.invalid_password');
    if (username != null) {
      if (password != confirm) {
        throw const AppException('error.password_mismatch');
      }
      if ((code?.trim().length ?? 0) < 4) {
        throw const AppException('error.invalid_code');
      }
    }
    await _persist(
      await api.authenticate(
        AccountIdentifier.parse(account, allowsPhone: allowsPhone),
        password,
        username: username?.trim(),
        code: code?.trim(),
        company: company.trim(),
        industry: industry,
      ),
    );
  }, title: username == null ? 'busy.logging_in' : 'busy.registering');
  Future<bool> sendCode(String account) => perform(
    () => api.sendCode(AccountIdentifier.parse(account, allowsPhone: allowsPhone)),
    title: 'busy.sending_code',
  );
  Future<bool> updatePassword(String account, String password, String confirm, String code) =>
      perform(() async {
        if (password.length < 6) throw const AppException('error.invalid_password');
        if (password != confirm) throw const AppException('error.password_mismatch');
        if (code.trim().length < 4) throw const AppException('error.invalid_code');
        await api.updatePassword(
          AccountIdentifier.parse(account, allowsPhone: allowsPhone),
          password,
          code.trim(),
        );
        message = t('notice.password_updated');
      }, title: 'busy.updating_password');
  Future<bool> updateUsername(String username) => perform(() async {
    final name = username.trim();
    if (name.isEmpty) throw const AppException('error.username');
    final data = await api.updateUser(name);
    await _persist(session!.copyWith(username: '${data['username'] ?? name}'));
    message = t('notice.profile_updated');
  }, title: 'busy.updating_profile');
  Future<void> signOut() async {
    session = null;
    api.token = null;
    managedDevices = [];
    _clearDevice();
    route = HomeRoute.projects;
    await bluetooth.stopScan();
    await bluetooth.disconnect();
    await _secure.delete(key: 'user-session');
    notifyListeners();
  }

  void clearMeasurements() {
    captures = [];
    result = null;
    resultTime = null;
    notifyListeners();
  }

  void _clearDevice() {
    selectedDevice = null;
    identity = null;
    mode = null;
    modes = [];
    pendingBinding = false;
    captures = [];
    result = null;
    resultTime = null;
  }

  Future<void> discover() async {
    route = HomeRoute.discovery;
    notifyListeners();
    await perform(bluetooth.startScan);
  }

  Future<void> back() async {
    if (busy) return;
    if (route == HomeRoute.workbench && modes.length > 1) {
      clearMeasurements();
      mode = null;
      route = HomeRoute.modes;
    } else {
      final destination = route == HomeRoute.discovery ? HomeRoute.projects : HomeRoute.discovery;
      await bluetooth.stopScan();
      await bluetooth.disconnect();
      _clearDevice();
      route = destination;
      if (destination == HomeRoute.discovery) {
        await perform(bluetooth.startScan);
      }
    }
    notifyListeners();
  }

  Future<bool> prepare(NearbyDevice device) => perform(() async {
    try {
      await bluetooth.connect(device);
      selectedDevice = device;
      identity = await bluetooth.readIdentity();
      final inspection = await api.inspect(device.kind, identity!, session!);
      if (!bluetooth.connectedReady || selectedDevice?.id != device.id) {
        throw const AppException('bt.device_lost');
      }
      final status = intValue(inspection['device_status']);
      if (status == 0 && inspection['device_status'] != null) {
        pendingBinding = true;
      } else if (status == 1) {
        _enterModes(AnalysisMode.parse(inspection['permission']));
      } else {
        throw AppException('server', inspection['info'] ?? t('error.device_unavailable'));
      }
    } catch (_) {
      await bluetooth.disconnect();
      _clearDevice();
      rethrow;
    }
  });
  Future<bool> bind() => perform(() async {
    final device = selectedDevice;
    final available = await api.bind(identity!, session!);
    if (!bluetooth.connectedReady || selectedDevice != device) {
      throw const AppException('bt.device_lost');
    }
    pendingBinding = false;
    _enterModes(available);
  });
  Future<void> cancelBinding() async {
    pendingBinding = false;
    await bluetooth.disconnect();
    _clearDevice();
    notifyListeners();
  }

  void _enterModes(List<AnalysisMode> available) {
    modes = available;
    if (available.length == 1) {
      chooseMode(available.first);
    } else {
      route = HomeRoute.modes;
      mode = null;
    }
  }

  void chooseMode(AnalysisMode selected) {
    mode = selected;
    clearMeasurements();
    route = HomeRoute.workbench;
    notifyListeners();
  }

  Future<void> _accept(Capture capture) async {
    if (route != HomeRoute.workbench || session == null || identity == null || mode == null) {
      return;
    }
    if (multiple && captures.length >= 9) {
      throw const AppException('error.max_scans');
    }
    result = null;
    resultTime = null;
    captures = multiple ? [...captures, capture] : [capture];
    if (!multiple) await _predict();
  }

  Future<void> _predict() async {
    busyKey = 'busy.predicting';
    notifyListeners();
    final device = selectedDevice;
    final currentIdentity = identity;
    final currentMode = mode;
    final currentSession = session;
    final scans = List<Capture>.of(captures);
    if (device == null ||
        currentIdentity == null ||
        currentMode == null ||
        currentSession == null) {
      throw const AppException('bt.device_lost');
    }
    final builtin = device.kind == DeviceKind.nir && defaultReference
        ? await bluetooth.readBuiltin()
        : null;
    final predicted = await api.predict(
      scans,
      currentIdentity,
      currentMode,
      currentSession,
      defaultReference,
      builtin,
    );
    if (!bluetooth.connectedReady || selectedDevice?.id != device.id || session != currentSession) {
      throw const AppException('bt.device_lost');
    }
    result = predicted;
    resultTime = DateTime.now();
  }

  Future<bool> scan() => perform(() async {
    if (multiple && captures.length >= 9) {
      throw const AppException('error.max_scans');
    }
    await _accept(await bluetooth.scan());
  }, title: 'busy.scanning');
  Future<bool> predictMultiple() => perform(() async {
    if (captures.length < 2) throw const AppException('error.min_scans');
    await _predict();
  }, title: 'busy.predicting');
  Future<bool> calibrate() => perform(() async {
    final currentIdentity = identity;
    if (currentIdentity == null) throw const AppException('bt.device_lost');
    final capture = await bluetooth.scan();
    await api.setReference(capture, currentIdentity);
    if (!bluetooth.connectedReady || identity != currentIdentity) {
      throw const AppException('bt.device_lost');
    }
    clearMeasurements();
    message = t('notice.cal_ok');
  }, title: 'busy.scanning');
  Future<bool> loadDevices() => perform(() async {
    managedDevices = await api.devices(session!);
  });
  @override
  void dispose() {
    bluetooth.removeListener(notifyListeners);
    bluetooth.dispose();
    api.dispose();
    super.dispose();
  }
}
