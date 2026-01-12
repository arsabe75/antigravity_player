import 'dart:convert';

/// Utility class for obfuscating/deobfuscating sensitive configuration values.
///
/// This is NOT cryptographic security - it's obfuscation to prevent
/// casual extraction of API credentials from the application bundle.
///
/// Usage:
/// 1. Run the encode functions with your real credentials
/// 2. Copy the encoded output to your .env file
/// 3. The app will decode them at runtime
class ConfigObfuscator {
  // XOR key - change this to your own random string!
  // The longer and more random, the better.
  static const String _xorKey = 'AnT1gR4v1tY_Pl4y3r_S3cr3t_K3y_2026!';

  /// Encodes a string value for storage in .env
  /// Returns a Base64 string that can be safely stored
  static String encode(String value) {
    final xored = _xorWithKey(value);
    return base64Encode(utf8.encode(xored));
  }

  /// Decodes an obfuscated string from .env
  /// Returns the original value
  static String decode(String encoded) {
    try {
      final decoded = utf8.decode(base64Decode(encoded));
      return _xorWithKey(decoded); // XOR is symmetric
    } catch (e) {
      // If decoding fails, return empty string (fail safe)
      return '';
    }
  }

  /// Decodes an obfuscated integer (like API ID) from .env
  static int decodeInt(String encoded) {
    final decoded = decode(encoded);
    return int.tryParse(decoded) ?? 0;
  }

  /// XOR each character with the key (repeating key if needed)
  static String _xorWithKey(String input) {
    final result = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final charCode = input.codeUnitAt(i);
      final keyCode = _xorKey.codeUnitAt(i % _xorKey.length);
      result.writeCharCode(charCode ^ keyCode);
    }
    return result.toString();
  }
}

// =============================================================================
// HELPER: Run this once to generate your encoded credentials
// =============================================================================
// Uncomment and run with: dart run lib/infrastructure/services/config_obfuscator.dart
//
// void main() {
//   // Replace with YOUR real credentials
//   const apiId = '12345678';
//   const apiHash = 'abcdef1234567890abcdef1234567890';
//
//   print('=== Encoded credentials for .env ===');
//   print('TELEGRAM_API_ID=${ConfigObfuscator.encode(apiId)}');
//   print('TELEGRAM_API_HASH=${ConfigObfuscator.encode(apiHash)}');
//   print('');
//   print('=== Verification (decoded back) ===');
//   print('API_ID: ${ConfigObfuscator.decode(ConfigObfuscator.encode(apiId))}');
//   print('API_HASH: ${ConfigObfuscator.decode(ConfigObfuscator.encode(apiHash))}');
// }
