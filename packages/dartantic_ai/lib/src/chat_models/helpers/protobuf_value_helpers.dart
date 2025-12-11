import 'package:google_cloud_protobuf/protobuf.dart' as pb;

/// Utilities for converting between loosely typed JSON structures and
/// protobuf [pb.Struct]/[pb.Value] instances used by the Google Cloud clients.
class ProtobufValueHelpers {
  /// Converts a Dart [Map] into a protobuf [pb.Struct].
  static pb.Struct structFromJson(Map<String, dynamic> json) => pb.Struct(
    fields: json.map((key, value) => MapEntry(key, valueFromJson(value))),
  );

  /// Converts a protobuf [pb.Struct] into a `Map<String, dynamic>`.
  static Map<String, dynamic> structToJson(pb.Struct? struct) {
    if (struct?.fields == null) return const <String, dynamic>{};
    return struct!.fields.map(
      (key, value) => MapEntry(key, valueToJson(value)),
    );
  }

  /// Converts a loosely typed JSON value into a protobuf [pb.Value].
  static pb.Value valueFromJson(dynamic value) {
    if (value == null) {
      return pb.Value(nullValue: pb.NullValue.nullValue);
    }
    if (value is bool) {
      return pb.Value(boolValue: value);
    }
    if (value is num) {
      return pb.Value(numberValue: value.toDouble());
    }
    if (value is String) {
      return pb.Value(stringValue: value);
    }
    if (value is Map) {
      final map = value.map(
        (key, dynamic v) => MapEntry(key.toString(), valueFromJson(v)),
      );
      return pb.Value(structValue: pb.Struct(fields: map));
    }
    if (value is Iterable) {
      return pb.Value(
        listValue: pb.ListValue(
          values: value.map(valueFromJson).toList(growable: false),
        ),
      );
    }

    // Fallback to string representation for unsupported values (e.g. enums).
    return pb.Value(stringValue: value.toString());
  }

  /// Converts a protobuf [pb.Value] back into a loosely typed Dart value.
  static dynamic valueToJson(pb.Value? value) {
    if (value == null) return null;
    if (value.structValue != null) {
      return structToJson(value.structValue);
    }
    if (value.listValue != null) {
      final list = value.listValue!.values;
      return list.map(valueToJson).toList(growable: false);
    }
    if (value.stringValue != null) return value.stringValue;
    if (value.numberValue != null) {
      final num = value.numberValue!;
      // Convert to int if it's a whole number, preserving compatibility
      // with integer-typed tool parameters
      if (num.toInt().toDouble() == num) {
        return num.toInt();
      }
      return num;
    }
    if (value.boolValue != null) return value.boolValue;
    return null; // nullValue or unset → null
  }
}
