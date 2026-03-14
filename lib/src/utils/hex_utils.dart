import 'dart:typed_data';
import 'package:blockchain_utils/blockchain_utils.dart';

/// Extension methods for making hex string manipulation more readable.
extension HexStringX on String {
  /// Removes the '0x' prefix if present. Returns the original string otherwise.
  String get strip0x => startsWith('0x') ? substring(2) : this;

  /// Safely converts a hex string (with or without '0x') to a Uint8List.
  Uint8List toBytes() {
    return Uint8List.fromList(BytesUtils.fromHexString(strip0x));
  }
}
