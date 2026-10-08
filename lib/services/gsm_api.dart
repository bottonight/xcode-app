import 'dart:convert';

import 'package:http/http.dart' as http;

import '../gsm.dart';
import '../models.dart';

class GsmApi {
  GsmApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'GSM_API_BASE_URL',
            defaultValue: 'https://aigsmcms.fabriceyes.com.cn:35001',
          );
  final http.Client _client;
  final String baseUrl;

  Future<List<GsmDevice>> devices(String account) async {
    final data = await _send(
      '/weixin/getDevices',
      body: {'user_tel': account, 'phone_number': account},
    );
    return ((data['devices'] as List?) ?? [])
        .map((item) => GsmDevice.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((device) => device.id.isNotEmpty)
        .toList();
  }

  Future<GsmPage> history(
    String deviceId, {
    int page = 1,
    int pageSize = 10,
    bool favorite = false,
  }) async {
    final data = await _send(
      favorite ? '/weixin/getFavorite' : '/weixin/getHistory',
      method: 'GET',
      query: {'device_id': deviceId, 'page': '$page', 'page_size': '$pageSize'},
    );
    final items = ((data['datas'] as List?) ?? [])
        .map((item) => GsmRecord.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    return GsmPage(items: items, total: intValue(data['total']), page: page, pageSize: pageSize);
  }

  Future<GsmDetail> detail(String id) async {
    final data = await _send('/weixin/getDataById', method: 'GET', query: {'data_id': id});
    final item = data['data'];
    if (item is! Map) throw const AppException('error.decode');
    return GsmDetail.fromJson(Map<String, dynamic>.from(item));
  }

  Future<void> saveExtra(String id, Map<String, String> extra) async {
    await _send('/weixin/addExtraData', body: {'id': int.tryParse(id) ?? id, 'extra_data': extra});
  }

  Future<void> setFavorite(String deviceId, String id, {required bool favorite}) async {
    await _send(
      favorite ? '/weixin/addFavorite' : '/weixin/removeFavorite',
      method: 'GET',
      query: {'device_id': deviceId, 'id': id},
    );
  }

  Future<void> deleteData(String deviceId, String phone, List<String> ids) async {
    await _send(
      '/weixin/deleteData',
      body: {
        'device_id': deviceId,
        'user_tel': phone,
        'data_ids': [for (final id in ids) int.tryParse(id) ?? id],
      },
    );
  }

  Future<void> rename(String account, String deviceId, String name) async {
    await _send(
      '/weixin/modifyDeviceName',
      method: 'GET',
      query: {'user_tel': account, 'device_id': deviceId, 'new_name': name},
    );
  }

  Future<String?> deviceName(String account, String deviceId) async {
    final data = await _send(
      '/weixin/getDeviceName',
      method: 'GET',
      query: {'user_tel': account, 'device_id': deviceId},
    );
    final name = '${data['device_name'] ?? ''}'.trim();
    return name.isEmpty ? null : name;
  }

  Future<void> share(String deviceId, String owner, String phone) async {
    await _send(
      '/weixin/shareDevice',
      body: {'device_id': deviceId, 'user_tel': owner, 'share_tel': phone},
    );
  }

  Future<List<String>> sharedPhones(String deviceId) async {
    final data = await _send(
      '/weixin/getSharedPhones',
      method: 'GET',
      query: {'device_id': deviceId},
    );
    return ((data['phones'] as List?) ?? []).map((phone) => '$phone').toList();
  }

  Future<void> cancelShare(String deviceId, String phone) async {
    await _send('/weixin/cancelShare', body: {'device_id': deviceId, 'user_tel': phone});
  }

  Future<void> bind(String account, String deviceId) async {
    await _send('/weixin/bindDevice', body: {'user_tel': account, 'device_id': deviceId});
  }

  Future<List<String>> bindStatus(String deviceId) async {
    final data = await _send(
      '/weixin/getBindStatus',
      method: 'GET',
      query: {'device_id': deviceId},
    );
    return ((data['bindings'] as List?) ?? []).map((phone) => '$phone').toList();
  }

  Future<String> latestVersion({
    required String mac,
    required String hardware,
    required String software,
  }) async {
    final uri = Uri.parse(baseUrl)
        .resolve('/version')
        .replace(queryParameters: {'mac': mac, 'hardware': hardware, 'software': software});
    final response = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException('error.http', response.statusCode);
    }
    final text = utf8.decode(response.bodyBytes).trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is String && decoded.trim().isNotEmpty) return decoded.trim();
      if (decoded is Map) {
        final data = Map<String, dynamic>.from(decoded);
        if (data.containsKey('status') && !succeeded(data['status'])) {
          throw AppException('server', data['error'] ?? data['message'] ?? 'Request failed');
        }
        final version = '${data['version'] ?? data['software'] ?? data['data'] ?? ''}'.trim();
        if (version.isNotEmpty && version != 'null') return version;
      }
    } on AppException {
      rethrow;
    } catch (_) {}
    final plain = text.replaceAll('"', '').trim();
    if (plain.isEmpty) throw const AppException('error.decode');
    return plain;
  }

  Future<Map<String, dynamic>> _send(
    String path, {
    String method = 'POST',
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(baseUrl).resolve(path).replace(queryParameters: query);
    final headers = {'Content-Type': 'application/json'};
    final response =
        await (method == 'GET'
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body ?? {})))
            .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException('error.http', response.statusCode);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const AppException('error.decode');
      final data = Map<String, dynamic>.from(decoded);
      if (data.containsKey('status') && !succeeded(data['status'])) {
        throw AppException('server', data['error'] ?? data['message'] ?? 'Request failed');
      }
      return data;
    } on AppException {
      rethrow;
    } on FormatException {
      throw const AppException('error.decode');
    }
  }

  void dispose() => _client.close();
}
