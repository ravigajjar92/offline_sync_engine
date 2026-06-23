import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/http_method.dart';
import '../models/sync_job.dart';
import '../models/sync_response.dart';
import 'sync_api_client.dart';

/// Default [SyncApiClient] using `package:http`.
///
/// Configure with a [baseUrl] (relative endpoints in [SyncJob.endpoint] are
/// resolved against it) and optional [defaultHeaders] (e.g. auth token).
///
/// HTTP semantics applied:
///   * 2xx                → [SyncResponse.success]
///   * 409                → [SyncResponse.conflict] (server body is parsed if
///                          it's JSON; otherwise `serverState = null`)
///   * everything else    → [SyncResponse.failure]
///   * timeout / socket   → [SyncResponse.failure]
class HttpSyncClient implements SyncApiClient {
  final Uri baseUrl;
  final Map<String, String> defaultHeaders;
  final Duration timeout;
  final http.Client _client;

  HttpSyncClient({
    required this.baseUrl,
    Map<String, String>? defaultHeaders,
    this.timeout = const Duration(seconds: 30),
    http.Client? client,
  })  : defaultHeaders = defaultHeaders ?? const {},
        _client = client ?? http.Client();

  void close() => _client.close();

  Uri _resolve(String endpoint) {
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      return Uri.parse(endpoint);
    }
    return baseUrl.resolve(endpoint);
  }

  Map<String, String> _mergeHeaders(Map<String, String>? jobHeaders) {
    final merged = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      ...defaultHeaders,
    };
    if (jobHeaders != null) merged.addAll(jobHeaders);
    return merged;
  }

  @override
  Future<SyncResponse> execute(SyncJob job) async {
    final uri = _resolve(job.endpoint);
    final headers = _mergeHeaders(job.headers);
    final body = job.method == HttpMethod.get ? null : jsonEncode(job.payload);

    try {
      late http.Response response;
      switch (job.method) {
        case HttpMethod.get:
          response = await _client.get(uri, headers: headers).timeout(timeout);
          break;
        case HttpMethod.post:
          response = await _client
              .post(uri, headers: headers, body: body)
              .timeout(timeout);
          break;
        case HttpMethod.put:
          response = await _client
              .put(uri, headers: headers, body: body)
              .timeout(timeout);
          break;
        case HttpMethod.patch:
          response = await _client
              .patch(uri, headers: headers, body: body)
              .timeout(timeout);
          break;
        case HttpMethod.delete:
          response = await _client
              .delete(uri, headers: headers, body: body)
              .timeout(timeout);
          break;
      }
      return _toResponse(response);
    } on TimeoutException catch (e) {
      return SyncResponse.failure(error: 'Request timed out: $e');
    } catch (e) {
      return SyncResponse.failure(error: e.toString());
    }
  }

  SyncResponse _toResponse(http.Response response) {
    final code = response.statusCode;
    final parsed = _tryDecodeJson(response.body);

    if (code >= 200 && code < 300) {
      return SyncResponse.success(statusCode: code, body: parsed ?? response.body);
    }
    if (code == 409) {
      return SyncResponse.conflict(
        statusCode: code,
        body: parsed ?? response.body,
        serverState: parsed is Map<String, dynamic> ? parsed : null,
        error: 'Conflict (HTTP $code)',
      );
    }
    return SyncResponse.failure(
      error: 'HTTP $code: ${response.reasonPhrase ?? response.body}',
      statusCode: code,
      body: parsed ?? response.body,
    );
  }

  Object? _tryDecodeJson(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}
