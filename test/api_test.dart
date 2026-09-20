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
}
