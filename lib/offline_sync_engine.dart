/// Offline-first synchronization engine for Flutter.
///
/// See `README.md` for installation and usage. The public API surface is
/// re-exported below.
library offline_sync_engine;

// Core facade & engine
export 'src/core/offline_sync.dart';
export 'src/core/offline_sync_config.dart';
export 'src/core/offline_sync_engine.dart';

// Models
export 'src/models/conflict_strategy.dart';
export 'src/models/http_method.dart';
export 'src/models/sync_job.dart';
export 'src/models/sync_job_status.dart';
export 'src/models/sync_response.dart';

// Repository contracts
export 'src/repository/queue_repository.dart';
export 'src/repository/queue_repository_impl.dart';

// Storage providers
export 'src/storage/file_storage_provider.dart';
export 'src/storage/in_memory_storage_provider.dart';
export 'src/storage/storage_provider.dart';

// Sync internals exposed for advanced use
export 'src/sync/retry_policy.dart';
export 'src/sync/sync_manager.dart';

// Network layer
export 'src/network/connectivity_monitor.dart';
export 'src/network/http_sync_client.dart';
export 'src/network/sync_api_client.dart';

// Conflict resolution
export 'src/conflict/conflict_resolver.dart';

// Events
export 'src/events/event_bus.dart';
export 'src/events/sync_event.dart';

// Exceptions
export 'src/exceptions/sync_exception.dart';

// Utilities
export 'src/utils/id_generator.dart';
export 'src/utils/logger.dart';
