import 'dart:typed_data';

/// Explicit utility class for explicit endian-aware byte conversions.
class ByteUtils {
  /// Converts an integer to a 2-byte big-endian array.
  static List<int> uint16ToBytes(int value) {
    final b = ByteData(2);
    b.setUint16(0, value, Endian.big);
    return b.buffer.asUint8List();
  }

  /// Converts a BigInt to an 8-byte big-endian array.
  static List<int> uint64ToBytes(BigInt value) {
    final b = ByteData(8);
    // Use toUnsigned(64) to handle potential signed representation quirks
    b.setUint64(0, value.toUnsigned(64).toInt(), Endian.big);
    return b.buffer.asUint8List();
  }
}
