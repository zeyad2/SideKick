import 'dart:convert';

/// Helpers for the JSONB-as-TEXT columns (see tables.dart). The values are
/// always read whole and never queried in SQL, so a plain encode/decode at the
/// repository boundary is enough — no drift TypeConverter magic.
abstract final class JsonCodecs {
  /// Decodes a stored JSON object, tolerating `null`/empty → `{}`.
  static Map<String, Object?> decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(raw);
    return decoded is Map<String, Object?>
        ? decoded
        : Map<String, Object?>.from(decoded as Map);
  }

  /// Decodes a stored JSON object that may legitimately be absent → `null`.
  static Map<String, Object?>? decodeNullableMap(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return decodeMap(raw);
  }

  /// Decodes a stored JSON array, tolerating `null`/empty → `[]`.
  static List<Object?> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <Object?>[];
    }
    return List<Object?>.from(jsonDecode(raw) as List<Object?>);
  }

  static String encode(Object? value) => jsonEncode(value);
}
