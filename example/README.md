# Examples

This directory contains examples of how to use the `location_protocol` library.

## Getting Started

To run the main example, ensure you have the Dart SDK installed, then run:

```sh
# Install dependencies
dart pub get

# Run the example
dart run example/main.dart
```

## What's in the example?

The [main.dart](main.dart) example demonstrates the core lifecycle of the Location Protocol:
1.  **Schema Definition**: Creating an EAS-compatible schema that includes LP base fields.
2.  **Payload Construction**: Building a validated location payload.
3.  **Offchain Signing**: Generating an EIP-712 signed attestation.
4.  **Verification**: Locally verifying the cryptographic integrity and spatial validity of the record.
