/// Location Protocol version constants and validation.
class LPVersion {
  /// Current LP spec version.
  static const String current = '0.2.0';

  /// Regex pattern for valid semver: major.minor.patch (digits only).
  static final RegExp semverPattern = RegExp(r'^\d+\.\d+\.\d+$');

  /// Validates a version string matches semver format.
  static bool isValid(String version) => semverPattern.hasMatch(version);
}
