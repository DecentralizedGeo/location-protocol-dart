/// Schema-agnostic Dart library implementing the Location Protocol
/// base data model on the Ethereum Attestation Service (EAS).
library location_protocol;

// LP layer
export 'src/lp/lp_payload.dart';
export 'src/lp/location_serializer.dart';

// Schema layer
export 'src/schema/schema_field.dart';
export 'src/schema/schema_definition.dart';
export 'src/schema/schema_uid.dart';

// EAS layer
// export 'src/eas/constants.dart';
// export 'src/eas/abi_encoder.dart';
// export 'src/eas/offchain_signer.dart';
// export 'src/eas/onchain_client.dart';
// export 'src/eas/schema_registry.dart';

// Config
// export 'src/config/chain_config.dart';

// Models
// export 'src/models/attestation.dart';
// export 'src/models/signature.dart';
// export 'src/models/verification_result.dart';
