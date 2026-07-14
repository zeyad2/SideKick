import 'dart:math';

/// Generates client-side UUIDs (v4). Ids are client-generated so a row exists
/// with a stable identity the instant it is written locally — before any sync.
/// This is what lets `events` push be a pure, conflict-free INSERT (D9).
class IdGenerator {
  IdGenerator([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  String v4() {
    final List<int> bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    // Set version (4) and variant (RFC 4122) bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final String hex = bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
