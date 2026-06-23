import '../models/sync_job.dart';
import '../models/sync_response.dart';

/// Transport contract used by the [SyncManager] to deliver a [SyncJob].
///
/// The package ships a [HttpSyncClient] reference implementation backed by
/// `package:http`. Swap in your own implementation to use Dio, Chopper,
/// GraphQL, gRPC, or a fully custom protocol.
abstract class SyncApiClient {
  Future<SyncResponse> execute(SyncJob job);
}
