import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class FabricApi {
  FabricApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'https://wx.nir.fabriceyes.com.cn:50002',
          );
  final http.Client _client;
  final String baseUrl;
  String language = 'zh-Hans';
  String? token;

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse(baseUrl).resolve(path).replace(queryParameters: query);
    final headers = {
      'Content-Type': 'application/json',
      'Accept-Language': language,
      if (authenticated && token != null) 'Authorization': 'Bearer $token',
    };
    final response =
        await (body == null
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 && authenticated) {
      throw const AppException('error.unauthorized');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException('error.http', response.statusCode);
    }
    try {
      dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
      // The legacy registration endpoint can return a JSON-encoded JSON string.
      if (decoded is String) decoded = jsonDecode(decoded);
      final result = Map<String, dynamic>.from(decoded as Map);
      if (result.containsKey('status') && !succeeded(result['status'])) {
        throw AppException('server', result['error'] ?? result['info'] ?? 'Request failed');
      }
      return result;
    } on FormatException {
      throw const AppException('error.decode');
    } on TypeError {
      throw const AppException('error.decode');
    }
  }

  Future<UserSession> authenticate(
    AccountIdentifier account,
    String password, {
    String? username,
    String? code,
    String company = '',
    String industry = '',
  }) async {
    final register = username != null;
    final data = await request(
      '/apps/LoginPage/${register ? 'register' : 'login'}',
      authenticated: false,
      body: {
        'openid': '',
        'password': password,
        if (account.isEmail) 'email': account.value,
        if (!account.isEmail) ...{
          'phone_num': account.value,
          if (!register) 'phone_number': account.value,
        },
        if (register) ...{
          'username': username,
          'code': code,
          'verification_code': code,
          'company': company,
          'industry': industry,
        },
      },
    );
    final detail = Map<String, dynamic>.from(data['UserDetail'] ?? {});
    final authToken = data['token'] as String?;
    if (authToken == null || authToken.isEmpty) {
      throw const AppException('error.missing_token');
    }
    return UserSession(
      userId: '${data['user_id'] ?? detail['user_id'] ?? account.value}',
      phone:
          data['phone_number'] ??
          detail['phone_num'] ??
          detail['phone_number'] ??
          (account.isEmail ? '' : account.value),
      email: data['email'] ?? detail['email'] ?? (account.isEmail ? account.value : ''),
      username: data['username'] ?? detail['username'] ?? username ?? account.value,
      token: authToken,
      adminLevel: intValue(data['is_admin'] ?? detail['is_admin']),
    );
  }

  Future<void> sendCode(AccountIdentifier account) async {
    await request(
      '/apps/LoginPage/${account.isEmail ? 'getEmailVC' : 'getPhoneVC'}',
      authenticated: false,
      body: {...account.query, if (!account.isEmail) 'phone_num': account.value},
    );
  }

  Future<Map<String, dynamic>> inspect(
    DeviceKind kind,
    DeviceIdentity identity,
    UserSession session,
  ) => request(
    '/apps/LoginPage/${kind == DeviceKind.nir ? 'getDeviceInfo' : 'getIR2210DeviceInfo'}',
    body: {...session.query, ...identity.json},
  );
  Future<List<AnalysisMode>> bind(DeviceIdentity identity, UserSession session) async =>
      AnalysisMode.parse(
        (await request(
          '/apps/LoginPage/bindDevice',
          body: {
            ...session.query,
            'serial_number': identity.serial,
            if (identity.uuid != null) 'uuid': identity.uuid,
          },
        ))['permission'],
      );
  Future<List<ManagedDevice>> devices(UserSession session) async {
    final data = await request('/apps/LoginPage/getDevices', query: session.query);
    return ((data['devices'] as List?) ?? [])
        .map((j) => ManagedDevice.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  Future<List<String>> sharedUsers(ManagedDevice device, UserSession session) async {
    final data = await request(
      '/apps/LoginPage/getSharedUser',
      body: {...session.query, 'serial_number': device.serial},
    );
    return List<String>.from(data['shared_user'] ?? []);
  }

  Future<void> share(
    ManagedDevice device,
    UserSession session,
    String phone, {
    bool revoke = false,
  }) async {
    await request(
      '/apps/LoginPage/${revoke ? 'deleteSharedDevice' : 'shareDevice'}',
      body: {...session.query, 'serial_number': device.serial, 'number_shared': phone},
    );
  }

  static Map<String, dynamic> predictionBody(
    List<Capture> captures,
    DeviceIdentity identity,
    AnalysisMode mode,
    UserSession session,
    bool defaultReference,
    List<int>? builtin,
  ) {
    if (captures.isEmpty) throw const AppException('pred.need_nir');
    final kind = captures.first.kind;
    if (captures.any((c) => c.kind != kind)) {
      throw const AppException('pred.invalid_response');
    }
    if (kind == DeviceKind.nir &&
        defaultReference &&
        (builtin == null || builtin.length != 3822 || builtin.any((v) => v < 0 || v > 255))) {
      throw const AppException('pred.invalid_builtin');
    }
    return {
      'openid': '',
      ...session.query,
      'serial_number': identity.serial,
      'model_name': mode.id,
      if (kind == DeviceKind.nir) ...{
        'data': captures.expand((c) => c.values).map((v) => '$v').toList(),
        if (identity.mac != null) 'mac_NIR': identity.mac,
        if (identity.uuid != null) 'uuid': identity.uuid,
        'is_builtin': defaultReference,
        'view_spectrum': false,
        if (defaultReference) 'builtin': builtin!.map((v) => '$v').toList(),
      } else ...{
        'intensity': captures.length == 1
            ? captures.first.values
            : captures.map((c) => c.values).toList(),
        'is_default_ref': defaultReference,
        'is_adapter': false,
      },
    };
  }

  Future<String> predict(
    List<Capture> captures,
    DeviceIdentity identity,
    AnalysisMode mode,
    UserSession session,
    bool defaultReference,
    List<int>? builtin,
  ) async {
    final body = predictionBody(captures, identity, mode, session, defaultReference, builtin);
    final data = await request(
      '/apps/PredictionPage/${captures.first.kind == DeviceKind.nir ? 'Prediction' : 'IR2210Prediction'}',
      body: body,
    );
    if (!succeeded(data['status']) || data['result'] is! String) {
      throw const AppException('pred.failed');
    }
    return data['result'] as String;
  }

  Future<void> setReference(Capture capture, DeviceIdentity identity) async {
    final nir = capture.kind == DeviceKind.nir;
    await request(
      '/apps/PredictionPage/${nir ? 'SetReference' : 'SetIR2210UserRef'}',
      body: {
        'serial_number': identity.serial,
        if (nir) ...{
          'data': capture.values.map((v) => '$v').toList(),
          if (identity.mac != null) 'mac_NIR': identity.mac,
          if (identity.uuid != null) 'uuid': identity.uuid,
        } else
          'intensity': capture.values,
      },
    );
  }

  void dispose() => _client.close();
}
