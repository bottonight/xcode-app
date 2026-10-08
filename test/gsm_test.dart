import 'package:fabriclab/gsm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device sections split only when both kinds exist', () {
    expect(splitDeviceSections(composition: 0, gsm: 0), isFalse);
    expect(splitDeviceSections(composition: 2, gsm: 0), isFalse);
    expect(splitDeviceSections(composition: 0, gsm: 3), isFalse);
    expect(splitDeviceSections(composition: 1, gsm: 1), isTrue);
  });

  test('device names keep letters, digits, spaces and Chinese within 14 widths', () {
    expect(sanitizeGsmName('克重仪 A1').value, '克重仪 A1');
    expect(sanitizeGsmName('克重仪 A1').errorKey, isNull);
    expect(sanitizeGsmName('名称😀').errorKey, 'gsm.name_invalid');
    expect(sanitizeGsmName('名称😀').value, '名称');
    expect(validateGsmName('一二三四五六七'), isNull);
    expect(validateGsmName('一二三四五六七八'), 'gsm.name_long');
    expect(validateGsmName('   '), 'gsm.name_empty');
  });

  test('history rows read grammage fields', () {
    final record = GsmRecord.fromJson({
      'id': 7,
      'time': '2026-10-08 17:05:00',
      'gsm': 180,
      'unit': 'g/m²',
      'favorite': 1,
      'image': '',
      'extra_data': {'品名': '斜纹'},
    });
    expect(record.id, '7');
    expect(record.time, '10-08 17:05');
    expect(record.gsm, '180');
    expect(record.favorite, isTrue);
    expect(record.product, '斜纹');
    final fields = gsmCustomFields({'品名': '斜纹', '缸号': 'A1', 'custom_image': 'abc'});
    expect(fields, hasLength(1));
    expect(fields.single.label, '缸号');
    expect(fields.single.value, 'A1');
  });

  test('device info packets and wifi packets follow the meter protocol', () {
    final assembler = GsmInfoAssembler();
    assembler.add([0, 5, 0, 0, 0]);
    expect(assembler.take(), isNull);
    assembler.add([1, 0x7b, 0x7d]);
    expect(assembler.take(), isNull);
    assembler.add([2, 1, 2, 3]);
    expect(assembler.take(), [0x7b, 0x7d, 1, 2, 3]);

    final packets = gsmWifiPackets([9, 8, 7]);
    expect(packets, hasLength(2));
    expect(packets.first.sublist(0, 5), [0, 3, 0, 0, 0]);
    expect(packets.last.sublist(0, 4), [1, 9, 8, 7]);
    expect(isGsmAdvertisedName('FEAT-01'), isTrue);
    expect(isGsmAdvertisedName('NIR-01'), isFalse);
    expect(gsmBleName('FEAT-车间'), '车间');
    final merged = mergeGsmDevices(
      const [GsmDevice(id: 'a', name: '旧'), GsmDevice(id: 'b', name: '本地')],
      const [GsmDevice(id: 'a', name: '新')],
    );
    expect(merged.map((device) => '${device.id}:${device.name}'), ['a:新', 'b:本地']);
  });
}
