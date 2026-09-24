import '../models.dart';

/// Pure protocol code shared by both mobile platforms. No native handles or UI.
class NirAssembler {
  final List<int> _bytes = [];
  void reset() => _bytes.clear();
  List<int>? feed(List<int> packet) {
    if (packet.isEmpty) return null;
    if (packet.first == 0) {
      _bytes.clear();
      return null;
    }
    _bytes.addAll(packet.skip(1));
    if (_bytes.length > 3822) {
      reset();
      throw const AppException('pred.nir_length');
    }
    if (packet.first != 202) return null;
    final result = List<int>.of(_bytes);
    reset();
    if (result.length != 3822) throw const AppException('pred.nir_length');
    return result;
  }
}

class IrProtocol {
  static List<int> command(int address, List<int> data) {
    final length = 8 + data.length;
    final body = [
      0xCD,
      0xC4,
      length >> 8,
      length & 255,
      (address >> 24) & 255,
      (address >> 16) & 255,
      (address >> 8) & 255,
      address & 255,
      ...data,
    ];
    return [0x55, 0xD5, ...body, body.fold<int>(0, (sum, b) => (sum + b) & 255)];
  }

  static bool valid(List<int> frame) =>
      frame.length >= 11 &&
      frame[2] == 0xDD &&
      frame.sublist(2, frame.length - 1).fold<int>(0, (sum, b) => (sum + b) & 255) == frame.last;
  static int address(List<int> frame) =>
      (frame[6] << 24) | (frame[7] << 16) | (frame[8] << 8) | frame[9];
  static List<int> spectrum(Map<int, List<int>> groups) {
    if (groups.length != 64) throw const AppException('bt.ir_incomplete');
    final values = <int>[];
    for (var group = 1; group <= 64; group++) {
      final bytes = groups[group];
      if (bytes == null || bytes.length != 8) {
        throw const AppException('bt.ir_incomplete');
      }
      for (var i = 0; i < 8; i += 2) {
        values.add((bytes[i] << 8) | bytes[i + 1]);
      }
    }
    return values;
  }
}

class IrAssembler {
  final List<int> _buffer = [];
  void reset() => _buffer.clear();
  List<List<int>> feed(List<int> bytes) {
    _buffer.addAll(bytes);
    final frames = <List<int>>[];
    while (_buffer.length >= 4) {
      if (_buffer[0] != 0x55 || _buffer[1] != 0xD5) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer[2] == 0xAA) {
        _buffer.removeRange(0, 4);
        continue;
      }
      if (_buffer.length < 6) break;
      final length = (_buffer[4] << 8) | _buffer[5];
      if (length < 8 || length > 64) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer.length < length + 3) break;
      final frame = _buffer.sublist(0, length + 3);
      if (!IrProtocol.valid(frame)) {
        _buffer.removeAt(0);
        continue;
      }
      _buffer.removeRange(0, length + 3);
      frames.add(frame);
    }
    return frames;
  }
}

int parseBatteryLevel(List<int> data) {
  if (data.isEmpty) throw const AppException('error.invalid_response');
  final value = data.first;
  if (value < 0 || value > 100) throw const AppException('error.invalid_response');
  return value;
}
