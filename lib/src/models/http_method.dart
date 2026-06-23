/// HTTP verbs supported by the sync engine.
enum HttpMethod {
  get,
  post,
  put,
  patch,
  delete;

  /// Wire-format name, e.g. `POST`.
  String get wireName => name.toUpperCase();

  static HttpMethod fromWire(String value) {
    final lower = value.toLowerCase();
    return HttpMethod.values.firstWhere(
      (m) => m.name == lower,
      orElse: () => throw ArgumentError('Unknown HttpMethod: $value'),
    );
  }
}
