// Quick test to check BigInt.zero.bitLength
import 'package:blockchain_utils/blockchain_utils.dart';

void main() {
  print('BigInt.zero.bitLength = ${BigInt.zero.bitLength}');
  print('bitlengthInBytes(BigInt.zero) = ${BigintUtils.bitlengthInBytes(BigInt.zero)}');
  final bytes = BigintUtils.toBytes(BigInt.zero, length: BigintUtils.bitlengthInBytes(BigInt.zero));
  print('toBytes(BigInt.zero) = $bytes');
  print('length = ${bytes.length}');
  
  // Also check what happens with BigInt.one
  print('');
  print('BigInt.one.bitLength = ${BigInt.one.bitLength}');
  print('bitlengthInBytes(BigInt.one) = ${BigintUtils.bitlengthInBytes(BigInt.one)}');
  final bytes1 = BigintUtils.toBytes(BigInt.one, length: BigintUtils.bitlengthInBytes(BigInt.one));
  print('toBytes(BigInt.one) = $bytes1');
}
