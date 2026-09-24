import 'package:flutter_test/flutter_test.dart';
import 'package:fabriclab/models.dart';
import 'package:fabriclab/services/ble_protocol.dart';

List<int> irFrame(int address, List<int> payload) {
  final length = 8 + payload.length;
  final body = [
    0xDD,
    0xC4,
    length >> 8,
    length & 255,
    address >> 24,
    (address >> 16) & 255,
    (address >> 8) & 255,
    address & 255,
    ...payload,
  ];
  return [0x55, 0xD5, ...body, body.fold<int>(0, (sum, value) => (sum + value) & 255)];
}

void main() {
  test('IR command matches the legacy serial-number request', () {
    expect(IrProtocol.command(0x40003007, [0, 16]), [
      0x55,
      0xD5,
      0xCD,
      0xC4,
      0,
      10,
      0x40,
      0,
      0x30,
      7,
      0,
      16,
      0x22,
    ]);
  });
  test('IR parser reassembles fragments, ignores junk and rejects corrupt checksums', () {
    final frame = irFrame(0x40003007, [1, ...List.filled(8, 65)]);
    final bad = [...frame]..[frame.length - 1] ^= 1;
    final parser = IrAssembler();
    expect(parser.feed([9, 8, ...bad, ...frame.take(5)]), isEmpty);
    expect(parser.feed([...frame.skip(5), ...frame]), [frame, frame]);
  });
  test('IR spectrum orders 64 groups and decodes big endian intensities', () {
    final groups = {
      for (var i = 64; i >= 1; i--) i: [0, i, 1, i, 2, i, 3, i],
    };
    final spectrum = IrProtocol.spectrum(groups);
    expect(spectrum.length, 256);
    expect(spectrum.take(4), [1, 257, 513, 769]);
    expect(spectrum.last, 832);
    groups.remove(5);
    expect(() => IrProtocol.spectrum(groups), throwsA(isA<AppException>()));
  });
  test('NIR transfer skips metadata and requires 3822 bytes at terminal packet', () {
    final assembler = NirAssembler();
    assembler.feed([0, 99, 99]);
    for (var i = 1; i <= 201; i++) {
      expect(assembler.feed([i, ...List.filled(19, i)]), isNull);
    }
    final bytes = assembler.feed([202, 1, 2, 3])!;
    expect(bytes.length, 3822);
    expect(bytes.take(19), List.filled(19, 1));
    expect(bytes.sublist(3819), [1, 2, 3]);
    expect(() => assembler.feed([202, 1]), throwsA(isA<AppException>()));
  });
  test('NIR overflow is rejected and next transfer can restart', () {
    final assembler = NirAssembler();
    expect(() => assembler.feed([1, ...List.filled(3823, 0)]), throwsA(isA<AppException>()));
    expect(assembler.feed([202, ...List.filled(3822, 0)])!.length, 3822);
  });
  test('Capture rejects malformed lengths and out-of-range bytes', () {
    expect(() => Capture(DeviceKind.nir, List.filled(3822, 256)), throwsA(isA<AppException>()));
    expect(() => Capture(DeviceKind.ir2210, [1, 2]), throwsA(isA<AppException>()));
  });
  test('IR battery command and reply match protocol item 4', () {
    expect(IrProtocol.command(0x40003004, [0, 1]), [
      0x55,
      0xD5,
      0xCD,
      0xC4,
      0,
      10,
      0x40,
      0,
      0x30,
      4,
      0,
      1,
      0x10,
    ]);
    const reply = [0x55, 0xD5, 0xDD, 0xC4, 0, 9, 0x40, 0, 0x30, 4, 0x64, 0x82];
    expect(irFrame(0x40003004, [0x64]), reply);
    final frames = IrAssembler().feed(reply);
    expect(frames, [reply]);
    expect(IrProtocol.address(frames.single), 0x40003004);
    expect(parseBatteryLevel([frames.single[10]]), 100);
  });
  test('Battery level is a single percent byte', () {
    expect(parseBatteryLevel([80]), 80);
    expect(parseBatteryLevel([0]), 0);
    expect(parseBatteryLevel([100]), 100);
    expect(() => parseBatteryLevel([]), throwsA(isA<AppException>()));
    expect(() => parseBatteryLevel([101]), throwsA(isA<AppException>()));
  });
}
