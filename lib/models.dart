enum DeviceKind {
  nir,
  ir2210;

  String get label => this == nir ? 'NIR' : 'IR2210';
  static DeviceKind? identify(String name) {
    for (final kind in values) {
      if (name.toUpperCase().startsWith(kind.label)) return kind;
    }
    return null;
  }
}

int intValue(dynamic value) => value == true ? 1 : int.tryParse('$value') ?? 0;
bool succeeded(dynamic value) =>
    value == true || ['succeed', 'success', 'true'].contains('$value'.toLowerCase());

class AppException implements Exception {
  const AppException(this.key, [this.detail]);
  final String key;
  final Object? detail;
}

class AccountIdentifier {
  const AccountIdentifier(this.value, this.isEmail);
  final String value;
  final bool isEmail;
  Map<String, String> get query => {isEmail ? 'email' : 'phone_number': value};
  static AccountIdentifier parse(String raw, {required bool allowsPhone}) {
    final value = raw.trim();
    if (value.contains('@')) {
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
        throw const AppException('error.invalid_email');
      }
      return AccountIdentifier(value.toLowerCase(), true);
    }
    if (!allowsPhone) throw const AppException('error.invalid_email');
    final digits = value.replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^1\d{10}$').hasMatch(digits)) {
      throw const AppException('error.invalid_phone');
    }
    return AccountIdentifier(digits, false);
  }
}

class UserSession {
  const UserSession({
    required this.userId,
    required this.phone,
    required this.email,
    required this.username,
    required this.token,
    required this.adminLevel,
  });
  final String userId, phone, email, username, token;
  final int adminLevel;
  String get account => phone.isEmpty ? email : phone;
  Map<String, String> get query => {phone.isEmpty ? 'email' : 'phone_number': account};

  UserSession copyWith({String? username}) => UserSession(
    userId: userId,
    phone: phone,
    email: email,
    username: username ?? this.username,
    token: token,
    adminLevel: adminLevel,
  );

  factory UserSession.fromApi(
    Map<String, dynamic> data,
    String token, {
    AccountIdentifier? account,
    String? username,
  }) {
    final detail = Map<String, dynamic>.from(data['UserDetail'] ?? {});
    return UserSession(
      userId: '${data['user_id'] ?? detail['user_id'] ?? account?.value ?? ''}',
      phone:
          data['phone_number'] ??
          detail['phone_num'] ??
          detail['phone_number'] ??
          (account != null && !account.isEmail ? account.value : ''),
      email:
          data['email'] ??
          detail['email'] ??
          (account != null && account.isEmail ? account.value : ''),
      username: data['username'] ?? detail['username'] ?? username ?? account?.value ?? '',
      token: token,
      adminLevel: intValue(data['is_admin'] ?? detail['is_admin']),
    );
  }

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
    userId: '${json['userID'] ?? ''}',
    phone: json['phoneNumber'] ?? '',
    email: json['email'] ?? '',
    username: json['username'] ?? '',
    token: json['authToken'] ?? '',
    adminLevel: intValue(json['adminLevel']),
  );
  Map<String, dynamic> toJson() => {
    'userID': userId,
    'phoneNumber': phone,
    'email': email,
    'username': username,
    'authToken': token,
    'adminLevel': adminLevel,
  };
}

class NearbyDevice {
  const NearbyDevice(this.id, this.name, this.kind, this.rssi);
  final String id, name;
  final DeviceKind kind;
  final int rssi;
  int get signal => rssi >= -55
      ? 3
      : rssi >= -70
      ? 2
      : 1;
}

class DeviceIdentity {
  const DeviceIdentity(this.name, this.serial, {this.mac, this.uuid});
  final String name, serial;
  final String? mac, uuid;
  Map<String, dynamic> get json => {
    'serial_number': serial,
    'device_name': name,
    if (mac != null) 'mac_NIR': mac,
    if (uuid != null) 'uuid': uuid,
  };
}

class AnalysisMode {
  const AnalysisMode(this.id, this.name, this.englishName, this.monthlyUse);
  final String id, name;
  final String? englishName;
  final int monthlyUse;
  String title(bool english) =>
      english && (englishName?.trim().isNotEmpty ?? false) ? englishName! : name;
  factory AnalysisMode.fromJson(Map<String, dynamic> j) => AnalysisMode(
    j['model_name'] as String,
    j['name'] as String,
    j['name_en'] as String?,
    intValue(j['use_count_month']),
  );
  static List<AnalysisMode> parse(dynamic list) => ((list as List?) ?? [])
      .map((e) => AnalysisMode.fromJson(Map<String, dynamic>.from(e as Map)))
      .where((m) => m.id != 'LINE' && m.id != 'REPORT')
      .toList();
}

class ManagedDevice {
  const ManagedDevice(this.serial, this.name, this.monthlyUse, this.history, this.shareable);
  final String serial, name;
  final int monthlyUse;
  final Map<String, int> history;
  final bool shareable;
  factory ManagedDevice.fromJson(Map<String, dynamic> j) => ManagedDevice(
    j['serial_number'] as String,
    j['name'] ?? j['serial_number'],
    intValue(j['use_count_month']),
    Map<String, dynamic>.from(j['use_history'] ?? {}).map((k, v) => MapEntry(k, intValue(v))),
    j['is_shareable'] == true,
  );
}

class Capture {
  Capture(this.kind, List<int> values)
    : values = List.unmodifiable(values),
      timestamp = DateTime.now() {
    if (values.length != (kind == DeviceKind.nir ? 3822 : 256)) {
      throw AppException(kind == DeviceKind.nir ? 'pred.nir_length' : 'pred.ir_length');
    }
    if (values.any((v) => v < 0 || v > (kind == DeviceKind.nir ? 255 : 65535))) {
      throw const AppException('pred.invalid_response');
    }
  }
  final DeviceKind kind;
  final List<int> values;
  final DateTime timestamp;
}

enum HomeRoute { projects, discovery, modes, workbench }
