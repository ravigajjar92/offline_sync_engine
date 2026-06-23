/// Strategy used to reconcile a server-side conflict.
enum ConflictStrategy {
  /// Compares `updatedAt`; whichever side is newer wins.
  lastWriteWins,

  /// Drop the local change; the server's version is authoritative.
  serverWins,

  /// Force-push the local change; the server's version is discarded.
  clientWins,
}
