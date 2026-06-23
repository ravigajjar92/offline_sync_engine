import 'package:uuid/uuid.dart';

/// Generates unique job ids. Abstracted so tests can inject deterministic ids.
abstract class IdGenerator {
  String generate();
}

class UuidV4IdGenerator implements IdGenerator {
  final Uuid _uuid;
  UuidV4IdGenerator([Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  @override
  String generate() => _uuid.v4();
}
