import 'package:on_chain/on_chain.dart';

/// Central registry of ABI function fragments used by the Location Protocol.
class EASAbis {
  static final AbiFunctionFragment timestamp = AbiFunctionFragment.fromJson({
    'name': 'timestamp',
    'type': 'function',
    'stateMutability': 'nonpayable',
    'inputs': [{'name': 'data', 'type': 'bytes32'}],
    'outputs': [{'name': '', 'type': 'uint64'}],
  });

  static final AbiFunctionFragment attest = AbiFunctionFragment.fromJson({
    'name': 'attest',
    'type': 'function',
    'stateMutability': 'payable',
    'inputs': [
      {
        'name': 'request',
        'type': 'tuple',
        'components': [
          {'name': 'schema', 'type': 'bytes32'},
          {
            'name': 'data',
            'type': 'tuple',
            'components': [
              {'name': 'recipient', 'type': 'address'},
              {'name': 'expirationTime', 'type': 'uint64'},
              {'name': 'revocable', 'type': 'bool'},
              {'name': 'refUID', 'type': 'bytes32'},
              {'name': 'data', 'type': 'bytes'},
              {'name': 'value', 'type': 'uint256'},
            ],
          },
        ],
      },
    ],
    'outputs': [{'name': '', 'type': 'bytes32'}],
  });

  static final AbiFunctionFragment getAttestation = AbiFunctionFragment.fromJson({
    'name': 'getAttestation',
    'type': 'function',
    'stateMutability': 'view',
    'inputs': [{'name': 'uid', 'type': 'bytes32'}],
    'outputs': [
      {
        'name': '',
        'type': 'tuple',
        'components': [
          {'name': 'uid', 'type': 'bytes32'},
          {'name': 'schema', 'type': 'bytes32'},
          {'name': 'time', 'type': 'uint64'},
          {'name': 'expirationTime', 'type': 'uint64'},
          {'name': 'revocationTime', 'type': 'uint64'},
          {'name': 'refUID', 'type': 'bytes32'},
          {'name': 'recipient', 'type': 'address'},
          {'name': 'attester', 'type': 'address'},
          {'name': 'revocable', 'type': 'bool'},
          {'name': 'data', 'type': 'bytes'},
        ],
      },
    ],
  });

  static final AbiFunctionFragment registerSchema = AbiFunctionFragment.fromJson({
    'name': 'register',
    'type': 'function',
    'stateMutability': 'nonpayable',
    'inputs': [
      {'name': 'schema', 'type': 'string'},
      {'name': 'resolver', 'type': 'address'},
      {'name': 'revocable', 'type': 'bool'},
    ],
    'outputs': [{'name': '', 'type': 'bytes32'}],
  });

  static final AbiFunctionFragment getSchema = AbiFunctionFragment.fromJson({
    'name': 'getSchema',
    'type': 'function',
    'stateMutability': 'view',
    'inputs': [{'name': 'uid', 'type': 'bytes32'}],
    'outputs': [
      {
        'name': '',
        'type': 'tuple',
        'components': [
          {'name': 'uid', 'type': 'bytes32'},
          {'name': 'resolver', 'type': 'address'},
          {'name': 'revocable', 'type': 'bool'},
          {'name': 'schema', 'type': 'string'},
        ],
      },
    ],
  });
}
