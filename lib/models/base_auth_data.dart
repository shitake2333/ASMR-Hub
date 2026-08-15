import 'dart:convert';

/// Base class for auth data that can be serialized to/from JSON for
/// persistence (each source implements [toJson] and a fromJson factory).
abstract class BaseAuthData {
  Map<String, dynamic> toJson();

  String serialize() => jsonEncode(toJson());
}
