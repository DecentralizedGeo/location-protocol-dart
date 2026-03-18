/// Schema-agnostic Dart library implementing the Location Protocol
/// base data model on the Ethereum Attestation Service (EAS).
library location_protocol;

// LP layer
export 'src/lp/lp_payload.dart';
export 'src/lp/lp_version.dart';
export 'src/lp/location_serializer.dart';
export 'src/lp/location_validator.dart';

// Schema layer
export 'src/schema/schema_field.dart';
export 'src/schema/schema_definition.dart';
export 'src/schema/schema_uid.dart';

// EAS layer
export 'src/eas/constants.dart';
export 'src/eas/abi_encoder.dart';
export 'src/eas/offchain_signer.dart';
export 'src/eas/onchain_client.dart';
export 'src/eas/schema_registry.dart';
export 'src/eas/signer.dart';
export 'src/eas/local_key_signer.dart';

// Config
export 'src/config/chain_config.dart';

// Models
export 'src/models/attestation.dart';
export 'src/models/signature.dart';
export 'src/models/verification_result.dart';
export 'src/models/attest_result.dart';
export 'src/models/timestamp_result.dart';
export 'src/models/register_result.dart';

// RPC
export 'src/rpc/rpc_provider.dart';
export 'src/rpc/default_rpc_provider.dart';
export 'src/rpc/transaction_receipt.dart';

// Utils
export 'src/utils/tx_utils.dart';
