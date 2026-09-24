import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fabriclab/models.dart';
import 'package:fabriclab/services/api.dart';

const session = UserSession(
  userId: '7',
  phone: '',
  email: 'user@example.com',
  username: 'User',
  token: 'token',
  adminLevel: 2,
);
const identity = DeviceIdentity('NIR test', 'sn', mac: 'device-id', uuid: 'system-id');
const mode = AnalysisMode('COTTON', '棉', 'Cotton', 2);
void main() {
  test('Authentication accepts nested string JSON and does not send stale token', () async {
    final api = FabricApi(
      client: MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), false);
        final body = jsonDecode(request.body);
        expect(body['email'], 'user@example.com');
        expect(body.containsKey('phone_number'), false);
        return http.Response(
          jsonEncode(
            jsonEncode({
              'status': true,
              'token': 'new',
              'UserDetail': {'user_id': 7, 'is_admin': '2', 'username': 'Test'},
            }),
          ),
          200,
        );
      }),
    )..token = 'stale';
    final user = await api.authenticate(
      const AccountIdentifier('user@example.com', true),
      'abcdef',
    );
    expect(user.userId, '7');
    expect(user.adminLevel, 2);
    expect(user.email, 'user@example.com');
    api.dispose();
  });
  test('Device requests carry language and authorization; 401 expires session', () async {
    final api =
        FabricApi(
            client: MockClient((request) async {
              expect(request.headers['Authorization'], 'Bearer token');
              expect(request.headers['Accept-Language'], 'en');
              expect(request.url.queryParameters, {'email': 'user@example.com'});
              return http.Response('{}', 401);
            }),
          )
          ..token = 'token'
          ..language = 'en';
    await expectLater(
      api.devices(session),
      throwsA(isA<AppException>().having((e) => e.key, 'key', 'error.unauthorized')),
    );
    api.dispose();
  });
  test('NIR prediction flattens scans into decimal strings with reference', () {
    final captures = [
      Capture(DeviceKind.nir, List.filled(3822, 2)),
      Capture(DeviceKind.nir, List.filled(3822, 3)),
    ];
    final body = FabricApi.predictionBody(
      captures,
      identity,
      mode,
      session,
      true,
      List.filled(3822, 4),
    );
    expect((body['data'] as List).length, 7644);
    expect(body['data'][3822], '3');
    expect(body['builtin'][0], '4');
    expect(body['view_spectrum'], false);
    expect(body['email'], session.email);
    expect(body.containsKey('phone_number'), false);
    expect(
      () => FabricApi.predictionBody(captures, identity, mode, session, true, null),
      throwsA(isA<AppException>()),
    );
  });
  test('IR payload preserves one-dimensional single and two-dimensional multi scans', () {
    final capture = Capture(DeviceKind.ir2210, List.filled(256, 123));
    final single = FabricApi.predictionBody([capture], identity, mode, session, false, null);
    final multiple = FabricApi.predictionBody(
      [capture, capture],
      identity,
      mode,
      session,
      true,
      null,
    );
    expect(single['intensity'][0], 123);
    expect(multiple['intensity'][0].length, 256);
    expect(single['is_default_ref'], false);
    expect(multiple.containsKey('data'), false);
  });
  test('Phone/email validation preserves region rules', () {
    expect(
      AccountIdentifier.parse(' USER@Example.com ', allowsPhone: false).value,
      'user@example.com',
    );
    expect(AccountIdentifier.parse('138 0013 8000', allowsPhone: true).value, '13800138000');
    expect(
      () => AccountIdentifier.parse('13800138000', allowsPhone: false),
      throwsA(isA<AppException>()),
    );
    expect(() => AccountIdentifier.parse('bad@', allowsPhone: true), throwsA(isA<AppException>()));
  });
  test('Auto-login reuses the stored token and does not require extra body fields', () async {
    final api = FabricApi(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/apps/LoginPage/autoLogin');
        expect(request.headers['Authorization'], 'Bearer stored');
        expect(jsonDecode(request.body), {});
        return http.Response(
          jsonEncode({
            'status': true,
            'user_id': 7,
            'phone_number': '13800138000',
            'email': '',
            'username': 'Restored',
            'is_admin': 1,
          }),
          200,
        );
      }),
    );
    final user = await api.autoLogin('stored');
    expect(user.token, 'stored');
    expect(user.username, 'Restored');
    expect(user.userId, '7');
    expect(user.adminLevel, 1);
    api.dispose();
  });
  test('Password reset is unauthenticated and profile update is authenticated', () async {
    http.Request? passwordRequest;
    http.Request? profileRequest;
    final api = FabricApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('updatePassword')) {
          passwordRequest = request;
          return http.Response(jsonEncode({'status': true}), 200);
        }
        profileRequest = request;
        return http.Response(jsonEncode({'status': true, 'username': 'New', 'user_id': 7}), 200);
      }),
    )..token = 'token';
    await api.updatePassword(const AccountIdentifier('13800138000', false), 'abcdef', '1234');
    expect(passwordRequest!.headers.containsKey('Authorization'), false);
    expect(jsonDecode(passwordRequest!.body)['phone_num'], '13800138000');
    expect(jsonDecode(passwordRequest!.body)['verification_code'], '1234');
    final updated = await api.updateUser('New');
    expect(profileRequest!.headers['Authorization'], 'Bearer token');
    expect(jsonDecode(profileRequest!.body)['username'], 'New');
    expect(updated['username'], 'New');
    api.dispose();
  });
  test('Prediction history and customer data endpoints parse list payloads', () async {
    final api = FabricApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('getPredictionHistory')) {
          expect(jsonDecode(request.body)['serial_number'], 'sn');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': true,
                'page': 1,
                'page_size': 10,
                'total': 1,
                'list': [
                  {
                    'pre_id': '20260923212157287031',
                    'time': '2026-09-23 21:21:57',
                    'components': {'cotton': 80, 'poly': 20},
                  },
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('addCustomerData')) {
          final body = jsonDecode(request.body);
          expect(body['pre_id_list'], ['1']);
          expect(body['images'], ['data:image/jpeg;base64,xx']);
          expect(body['data']['name'], 'A');
          return http.Response(jsonEncode({'status': true, 'id': 12}), 200);
        }
        if (request.url.path.endsWith('getCustomerDataList')) {
          return http.Response(
            jsonEncode({
              'status': true,
              'page': 1,
              'page_size': 10,
              'total': 1,
              'list': [
                {'id': 12, 'time': '2026-09-24 12:00:00', 'components': 'cotton 80%'},
              ],
            }),
            200,
          );
        }
        expect(jsonDecode(request.body)['id'], 12);
        return http.Response(
          jsonEncode({
            'status': true,
            'id': 12,
            'data': {'name': 'A'},
            'images': ['data:image/jpeg;base64,QQ=='],
            'components': [
              {'cotton': 80},
              null,
            ],
          }),
          200,
        );
      }),
    )..token = 'token';
    final history = await api.predictionHistory('sn');
    expect(history.items.single.preId, '20260923212157287031');
    expect(history.items.single.components, 'cotton 80%  poly 20%');
    await api.addCustomerData(
      preIds: ['1'],
      images: ['data:image/jpeg;base64,xx'],
      data: {'name': 'A'},
    );
    final list = await api.customerDataList();
    expect(list.items.single.id, 12);
    final detail = await api.customerData(12);
    expect(detail.data['name'], 'A');
    expect(detail.images, isNotEmpty);
    expect(detail.components, ['cotton 80%', '']);
    api.dispose();
  });
}
