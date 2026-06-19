import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:pluradb/models/database_config.dart';
import 'package:pluradb/models/provider_type.dart';
import 'package:pluradb/models/query_result.dart';

abstract class DatabaseService {
  Future<QueryResult> executeQuery(String sql);
  Future<QueryResult> getSchema();
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50});
  Future<bool> testConnection();
}

class DatabaseServiceFactory {
  static DatabaseService create(DatabaseConfig config) {
    switch (config.provider) {
      case ProviderType.supabase:
        return SupabaseService(config);
      case ProviderType.neon:
        return NeonService(config);
      case ProviderType.planetscale:
        return PlanetScaleService(config);
      case ProviderType.turso:
        return TursoService(config);
      case ProviderType.cockroachdb:
        return CockroachDBService(config);
      case ProviderType.custom:
        return CustomPostgresService(config);
    }
  }
}

// ═══════════════════════════════════════════════════
// SUPABASE — PostgREST HTTP API
// Docs: https://supabase.com/docs/guides/api/rest/using-the-postgrest-client
// The REST API is at {project_url}/rest/v1/
// OpenAPI spec is at {project_url}/rest/v1/
// Requires: apikey header (anon key) + Authorization header
// ═══════════════════════════════════════════════════

class SupabaseService implements DatabaseService {
  final DatabaseConfig config;
  SupabaseService(this.config);

  /// Build REST base URL, stripping trailing slashes
  String get _baseUrl {
    final url = config.projectUrl.replaceAll(RegExp(r'/+$'), '');
    return '$url/rest/v1';
  }

  /// Build auth headers. Service role key gives full access, anon key is read-only.
  Map<String, String> get _headers {
    final bearerKey = config.serviceRoleKey.isNotEmpty ? config.serviceRoleKey : config.anonKey;
    return {
      'apikey': config.anonKey,
      'Authorization': 'Bearer $bearerKey',
      'Content-Type': 'application/json',
    };
  }

  @override
  Future<bool> testConnection() async {
    try {
      // Hit the OpenAPI spec endpoint — always available for valid projects
      final resp = await http
          .get(Uri.parse('$_baseUrl/'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      // 200 = success, 401 = URL is valid but key is wrong (still reachable)
      return resp.statusCode == 200 || resp.statusCode == 401;
    } on SocketException {
      return false;
    } on HandshakeException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> getSchema() async {
    try {
      final url = config.projectUrl.replaceAll(RegExp(r'/+$'), '');
      final resp = await http
          .get(Uri.parse('$url/rest/v1/'), headers: {..._headers, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 401) {
        return QueryResult(error: 'Authentication failed. Check your anon key in Supabase Dashboard > Settings > API.');
      }
      if (resp.statusCode != 200) {
        return QueryResult(error: 'Failed to fetch schema (HTTP ${resp.statusCode}). Is the project URL correct?');
      }

      final data = jsonDecode(resp.body);
      final paths = data['paths'] as Map<String, dynamic>? ?? {};
      final schemas = <Map<String, String>>[];

      for (final path in paths.keys) {
        // Only match root-level table endpoints: /tablename
        final match = RegExp(r'^/(\w+)$').firstMatch(path);
        if (match != null) {
          final tableName = match.group(1)!;
          schemas.add({'table': tableName, 'columns': '*'});
        }
      }

      return QueryResult(
        columns: ['Table'],
        rows: schemas.map((s) => {'Table': s['table'] as String}).toList(),
        rowCount: schemas.length,
      );
    } on SocketException catch (e) {
      return QueryResult(error: 'Network error: Cannot reach Supabase. Check your internet connection.\n$e');
    } catch (e) {
      return QueryResult(error: 'Schema fetch error: $e');
    }
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) async {
    try {
      final uri = Uri.parse('$_baseUrl/$table').replace(queryParameters: {
        'select': '*',
        'offset': offset.toString(),
        'limit': limit.toString(),
      });
      final resp = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 401) {
        return QueryResult(error: 'Authentication failed. Check your API key.');
      }
      if (resp.statusCode == 406) {
        return QueryResult(error: 'Table "$table" not found or RLS policy prevents access.');
      }
      if (resp.statusCode != 200) {
        return QueryResult(error: 'HTTP ${resp.statusCode}: ${resp.body}');
      }

      final data = jsonDecode(resp.body) as List;
      if (data.isEmpty) return QueryResult(columns: [], rows: [], rowCount: 0);

      final columns = (data[0] as Map<String, dynamic>).keys.toList();
      final rows = data.map((row) => Map<String, dynamic>.from(row as Map)).toList();

      int? totalCount;
      final contentRange = resp.headers['content-range'];
      if (contentRange != null) {
        final parts = contentRange.split('/');
        if (parts.length == 2) totalCount = int.tryParse(parts[1]);
      }

      return QueryResult(columns: columns, rows: rows, rowCount: totalCount ?? rows.length);
    } on SocketException {
      return QueryResult(error: 'Network error. Check your internet connection.');
    } catch (e) {
      return QueryResult(error: 'Error fetching table data: $e');
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final trimmedSql = sql.trim().toUpperCase();

      // SELECT: try to extract table and use PostgREST
      if (trimmedSql.startsWith('SELECT') || trimmedSql.startsWith('WITH')) {
        final tableMatch = RegExp(r'FROM\s+(\w+)', caseSensitive: false).firstMatch(sql);
        if (tableMatch != null) {
          return getTableData(tableMatch.group(1)!);
        }
        return QueryResult(error: 'Could not parse table name from SELECT. For complex queries, use a table name directly.');
      }

      // INSERT via PostgREST
      if (trimmedSql.startsWith('INSERT')) {
        if (config.serviceRoleKey.isEmpty) {
          return QueryResult(error: 'Service Role Key is required for INSERT. Add it in database settings.');
        }
        final tableMatch = RegExp(r'INTO\s+(\w+)', caseSensitive: false).firstMatch(sql);
        if (tableMatch == null) {
          return QueryResult(error: 'Could not parse table name from INSERT.');
        }
        final tableName = tableMatch.group(1)!;

        // Try to extract column names and values
        final colsValues = _parseInsert(sql);
        final resp = await http
            .post(Uri.parse('$_baseUrl/$tableName'), headers: _headers, body: jsonEncode(colsValues))
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode == 201) {
          return QueryResult(affectedRows: 1, columns: ['result'], rows: [{'result': 'Row inserted'}]);
        }
        if (resp.statusCode == 401) {
          return QueryResult(error: 'Auth failed. Service Role Key required for INSERT.');
        }
        return QueryResult(error: 'Insert error (HTTP ${resp.statusCode}): ${resp.body}');
      }

      // UPDATE via PostgREST
      if (trimmedSql.startsWith('UPDATE')) {
        if (config.serviceRoleKey.isEmpty) {
          return QueryResult(error: 'Service Role Key is required for UPDATE.');
        }
        final tableMatch = RegExp(r'UPDATE\s+(\w+)', caseSensitive: false).firstMatch(sql);
        if (tableMatch == null) {
          return QueryResult(error: 'Could not parse table from UPDATE.');
        }
        final tableName = tableMatch.group(1)!;
        final setData = _parseSetClause(sql);

        final resp = await http
            .patch(Uri.parse('$_baseUrl/$tableName'), headers: _headers, body: jsonEncode(setData))
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode == 200) {
          final updated = jsonDecode(resp.body) as List;
          return QueryResult(affectedRows: updated.length, columns: ['result'], rows: [{'result': '${updated.length} row(s) updated'}]);
        }
        return QueryResult(error: 'Update error (HTTP ${resp.statusCode}): ${resp.body}');
      }

      // DELETE via PostgREST
      if (trimmedSql.startsWith('DELETE')) {
        if (config.serviceRoleKey.isEmpty) {
          return QueryResult(error: 'Service Role Key is required for DELETE.');
        }
        final tableMatch = RegExp(r'FROM\s+(\w+)', caseSensitive: false).firstMatch(sql);
        if (tableMatch == null) {
          return QueryResult(error: 'Could not parse table from DELETE.');
        }
        final tableName = tableMatch.group(1)!;

        final resp = await http
            .delete(Uri.parse('$_baseUrl/$tableName'), headers: _headers)
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode == 204 || resp.statusCode == 200) {
          return QueryResult(affectedRows: 1, columns: ['result'], rows: [{'result': 'Deleted'}]);
        }
        return QueryResult(error: 'Delete error (HTTP ${resp.statusCode}): ${resp.body}');
      }

      return QueryResult(error: 'Unsupported query. PostgREST supports SELECT, INSERT, UPDATE, DELETE on tables.');
    } on SocketException {
      return QueryResult(error: 'Network error. Check your internet connection.');
    } catch (e) {
      return QueryResult(error: 'Query error: $e');
    }
  }

  Map<String, dynamic> _parseInsert(String sql) {
    // Try: INSERT INTO table (col1, col2) VALUES (val1, val2)
    final colsMatch = RegExp(r'INSERT\s+INTO\s+\w+\s*\(([^)]+)\)', caseSensitive: false).firstMatch(sql);
    final valsMatch = RegExp(r'VALUES\s*\((.+)\)', caseSensitive: false).firstMatch(sql);
    if (colsMatch != null && valsMatch != null) {
      final cols = colsMatch.group(1)!.split(',').map((c) => c.trim()).toList();
      final vals = valsMatch.group(1)!.split(',').map((v) => _parseValue(v.trim())).toList();
      final row = <String, dynamic>{};
      for (int i = 0; i < cols.length && i < vals.length; i++) {
        row[cols[i]] = vals[i];
      }
      return row;
    }
    return {};
  }

  dynamic _parseValue(String v) {
    if ((v.startsWith("'") && v.endsWith("'")) || (v.startsWith('"') && v.endsWith('"'))) {
      return v.substring(1, v.length - 1);
    }
    if (v.toLowerCase() == 'null') return null;
    if (v.toLowerCase() == 'true') return true;
    if (v.toLowerCase() == 'false') return false;
    return int.tryParse(v) ?? double.tryParse(v) ?? v;
  }

  Map<String, dynamic> _parseSetClause(String sql) {
    final setMatch = RegExp(r'SET\s+(.+?)(?:\s+WHERE\s+|$)', caseSensitive: false, dotAll: true).firstMatch(sql);
    if (setMatch == null) return {};
    final result = <String, dynamic>{};
    for (final pair in setMatch.group(1)!.split(',')) {
      final parts = pair.trim().split(RegExp(r'\s*=\s*'));
      if (parts.length == 2) {
        result[parts[0].trim()] = _parseValue(parts[1].trim());
      }
    }
    return result;
  }
}

// ═══════════════════════════════════════════════════
// NEON — HTTP SQL API
// Neon exposes an HTTP endpoint at https://<host>/sql
// Requires: Neon-Connection-String header + Basic auth
// Response format: {"results": [...], "command_tag": "..."} on success
//                  {"message": "...", "code": "..."} on error
// ═══════════════════════════════════════════════════

class NeonService implements DatabaseService {
  final DatabaseConfig config;
  NeonService(this.config);

  String get _host {
    // If connection string provided, extract host from it
    if (config.connectionString.isNotEmpty) {
      try {
        return Uri.parse(config.connectionString).host;
      } catch (_) {}
    }
    return config.host;
  }

  String get _user {
    if (config.connectionString.isNotEmpty) {
      try {
        return Uri.parse(config.connectionString).userInfo.split(':').first;
      } catch (_) {}
    }
    return config.user;
  }

  String get _password {
    if (config.connectionString.isNotEmpty) {
      try {
        final info = Uri.parse(config.connectionString).userInfo;
        final parts = info.split(':');
        return parts.length > 1 ? parts.sublist(1).join(':') : '';
      } catch (_) {}
    }
    return config.password;
  }

  String get _dbName {
    if (config.connectionString.isNotEmpty) {
      try {
        final uri = Uri.parse(config.connectionString);
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : config.databaseName;
      } catch (_) {}
    }
    return config.databaseName;
  }

  Map<String, String> get _headers {
    final creds = base64Encode(utf8.encode('$_user:$_password'));
    return {
      'Authorization': 'Basic $creds',
      'Content-Type': 'application/json',
      'Neon-Connection-String': 'postgresql://$_user:$_password@$_host/$_dbName',
    };
  }

  @override
  Future<bool> testConnection() async {
    try {
      final result = await executeQuery('SELECT 1 as test');
      return result.error == null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final resp = await http
          .post(Uri.parse('https://$_host/sql'), headers: _headers, body: jsonEncode({'query': sql}))
          .timeout(const Duration(seconds: 15));

      // Neon HTTP API returns {"message": "..."} on error
      if (resp.statusCode != 200) {
        try {
          final errData = jsonDecode(resp.body);
          final msg = errData['message'] ?? resp.body;
          return QueryResult(error: 'Neon error (HTTP ${resp.statusCode}): $msg');
        } catch (_) {
          return QueryResult(error: 'Neon error (HTTP ${resp.statusCode}): ${resp.body}');
        }
      }

      final data = jsonDecode(resp.body);

      // Success format: {"results": [{"columns": [...], "rows": [...]}], "command_tag": "SELECT 1"}
      if (data is Map<String, dynamic>) {
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map<String, dynamic>;
          final cols = (first['columns'] as List?)?.map((c) => c.toString()).toList() ?? [];
          final rows = (first['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
          return QueryResult(columns: cols, rows: rows, rowCount: rows.length);
        }

        // No results (DDL or empty result set)
        final tag = data['command_tag'] as String?;
        if (tag != null) {
          final numMatch = RegExp(r'(\d+)').firstMatch(tag);
          return QueryResult(columns: [], rows: [], affectedRows: numMatch != null ? int.parse(numMatch.group(1)!) : 0);
        }

        // Completely empty response
        return QueryResult(columns: [], rows: []);
      }

      return QueryResult(error: 'Unexpected response format from Neon.');
    } on SocketException catch (e) {
      return QueryResult(error: 'Cannot reach $_host. Check host and internet.\n$e');
    } catch (e) {
      return QueryResult(error: 'Neon connection error: $e');
    }
  }

  @override
  Future<QueryResult> getSchema() {
    return executeQuery(
        "SELECT table_name, column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}

// ═══════════════════════════════════════════════════
// PLANETSCALE — HTTP API
// PlanetScale has REST API endpoints. For direct SQL,
// an HTTP SQL proxy is needed.
// ═══════════════════════════════════════════════════

class PlanetScaleService implements DatabaseService {
  final DatabaseConfig config;
  PlanetScaleService(this.config);

  @override
  Future<bool> testConnection() async {
    try {
      final result = await executeQuery('SELECT 1 as test');
      return result.error == null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final uri = Uri.parse('https://${config.host}/v1/databases/${config.databaseName}/query');
      final resp = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${config.password}',
              'Content-Type': 'application/json',
              'X-PlanetScale-Format': 'json',
            },
            body: jsonEncode({'query': sql}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        return _parseResponse(resp.body);
      }

      // Try alternative: treat host as proxy URL
      final proxyUri = Uri.parse('https://${config.host}/query');
      final proxyResp = await http
          .post(proxyUri, headers: {'Authorization': 'Bearer ${config.password}', 'Content-Type': 'application/json'}, body: jsonEncode({'query': sql, 'database': config.databaseName}))
          .timeout(const Duration(seconds: 15));

      if (proxyResp.statusCode == 200) {
        return _parseResponse(proxyResp.body);
      }

      return QueryResult(
          error: 'PlanetScale error (HTTP ${resp.statusCode}). '
              'Ensure the host URL and API token are correct.\n'
              'Note: PlanetScale requires an HTTP SQL proxy for direct query access.');
    } on SocketException catch (e) {
      return QueryResult(error: 'Cannot reach ${config.host}. Check host and internet.\n$e');
    } catch (e) {
      return QueryResult(error: 'PlanetScale connection error: $e');
    }
  }

  QueryResult _parseResponse(String body) {
    final data = jsonDecode(body);
    final rows = (data['results'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
    if (rows.isEmpty) return QueryResult(columns: [], rows: []);
    return QueryResult(columns: rows.first.keys.toList(), rows: rows, rowCount: rows.length);
  }

  @override
  Future<QueryResult> getSchema() {
    return executeQuery(
        'SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = DATABASE() ORDER BY table_name, ordinal_position');
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM `$table` LIMIT $limit OFFSET $offset');
  }
}

// ═══════════════════════════════════════════════════
// TURSO — libsql HTTP API
// Endpoint: https://api.turso.tech/v1/organizations/{org}/databases/{db}/query
// Auth: Bearer token
// URL format: libsql://dbname-orgname.turso.io
// ═══════════════════════════════════════════════════

class TursoService implements DatabaseService {
  final DatabaseConfig config;
  TursoService(this.config);

  /// Parse libsql:// URL to extract org and db names
  /// Format: libsql://dbname-orgname.turso.io
  void _parseUrl(String url, {required void Function(String org, String db) onSuccess}) {
    // Standard format: libsql://dbname-orgname.turso.io
    final domainMatch = RegExp(r'libsql://([a-z0-9_-]+)\.turso\.io').firstMatch(url);
    if (domainMatch != null) {
      final name = domainMatch.group(1)!;
      final lastDash = name.lastIndexOf('-');
      if (lastDash > 0) {
        onSuccess(name.substring(lastDash + 1), name.substring(0, lastDash));
        return;
      }
      onSuccess('_', name);
      return;
    }

    // With path: libsql://anything.turso.io/dbname
    final pathMatch = RegExp(r'libsql://[^/]+/([^/?]+)').firstMatch(url);
    if (pathMatch != null) {
      onSuccess('_', pathMatch.group(1)!);
      return;
    }

    onSuccess('_', '_');
  }

  @override
  Future<bool> testConnection() async {
    try {
      final result = await executeQuery('SELECT 1 as test');
      return result.error == null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      late String orgName;
      late String dbName;
      _parseUrl(config.databaseUrl, onSuccess: (org, db) {
        orgName = org;
        dbName = db;
      });

      final endpoint = Uri.parse('https://api.turso.tech/v1/organizations/$orgName/databases/$dbName/query');
      final resp = await http
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer ${config.authToken}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'query': sql}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 404) {
        return QueryResult(
            error: 'Database not found. URL format should be: libsql://<dbname>-<orgname>.turso.io\n'
                'Parsed: org="$orgName", db="$dbName"');
      }
      if (resp.statusCode == 401) {
        return QueryResult(error: 'Authentication failed. Check your Turso auth token.');
      }
      if (resp.statusCode != 200) {
        return QueryResult(error: 'Turso error (HTTP ${resp.statusCode}): ${resp.body}');
      }

      final data = jsonDecode(resp.body);
      final results = data['results'] as Map<String, dynamic>? ?? {};
      final rows = (results['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      final cols = (results['cols'] as List?)?.map((c) => (c['name'] ?? c).toString()).toList() ?? [];

      return QueryResult(columns: cols, rows: rows, rowCount: rows.length);
    } on SocketException catch (e) {
      return QueryResult(error: 'Cannot reach Turso API. Check internet.\n$e');
    } catch (e) {
      return QueryResult(error: 'Turso connection error: $e');
    }
  }

  @override
  Future<QueryResult> getSchema() {
    return executeQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}

// ═══════════════════════════════════════════════════
// COCKROACHDB — HTTP SQL Proxy
// Default port: 26257
// Requires HTTP SQL proxy for mobile access
// ═══════════════════════════════════════════════════

class CockroachDBService implements DatabaseService {
  final DatabaseConfig config;
  CockroachDBService(this.config);

  String get _proxyUrl {
    if (config.host.startsWith('http://') || config.host.startsWith('https://')) {
      return config.host.replaceAll(RegExp(r'/+$'), '');
    }
    return 'http://${config.host}:${config.port.isNotEmpty ? config.port : '26257'}';
  }

  Map<String, String> get _headers {
    if (config.anonKey.isNotEmpty) {
      return {'Authorization': 'Bearer ${config.anonKey}', 'Content-Type': 'application/json'};
    }
    final creds = base64Encode(utf8.encode('${config.user}:${config.password}'));
    return {'Authorization': 'Basic $creds', 'Content-Type': 'application/json'};
  }

  @override
  Future<bool> testConnection() async {
    try {
      final result = await executeQuery('SELECT 1 as test');
      return result.error == null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final body = jsonEncode({
        'query': sql,
        'database': config.databaseName,
        'user': config.user,
        'password': config.password,
      });

      final resp = await http
          .post(Uri.parse('$_proxyUrl/sql'), headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) return _parseResponse(resp.body);

      // Try /query endpoint as fallback
      final altResp = await http
          .post(Uri.parse('$_proxyUrl/query'), headers: _headers, body: body)
          .timeout(const Duration(seconds: 10));

      if (altResp.statusCode == 200) return _parseResponse(altResp.body);

      return QueryResult(
          error: 'CockroachDB proxy error (HTTP ${resp.statusCode}). '
              'Ensure your HTTP SQL proxy is running at $_proxyUrl\n'
              'CockroachDB requires a proxy like "postgres-http-proxy" for mobile access.');
    } on SocketException catch (e) {
      return QueryResult(error: 'Cannot reach $_proxyUrl. Is the proxy running?\n$e');
    } catch (e) {
      return QueryResult(error: 'CockroachDB error: $e');
    }
  }

  QueryResult _parseResponse(String body) {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      if (data['error'] != null) return QueryResult(error: data['error'].toString());
      final rows = (data['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      if (rows.isNotEmpty) return QueryResult(columns: rows.first.keys.toList(), rows: rows, rowCount: rows.length);
      return QueryResult(columns: [], rows: [], affectedRows: data['affected_rows'] as int?);
    }
    return QueryResult(columns: [], rows: []);
  }

  @override
  Future<QueryResult> getSchema() {
    return executeQuery("SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}

// ═══════════════════════════════════════════════════
// CUSTOM POSTGRESQL — HTTP SQL Proxy
// Any PostgreSQL accessible via HTTP proxy
// ═══════════════════════════════════════════════════

class CustomPostgresService implements DatabaseService {
  final DatabaseConfig config;
  CustomPostgresService(this.config);

  String get _proxyUrl {
    if (config.host.startsWith('http://') || config.host.startsWith('https://')) {
      return config.host.replaceAll(RegExp(r'/+$'), '');
    }
    return 'http://${config.host}:${config.port.isNotEmpty ? config.port : '5432'}';
  }

  Map<String, String> get _headers {
    if (config.anonKey.isNotEmpty) {
      return {'Authorization': 'Bearer ${config.anonKey}', 'Content-Type': 'application/json'};
    }
    final creds = base64Encode(utf8.encode('${config.user}:${config.password}'));
    return {'Authorization': 'Basic $creds', 'Content-Type': 'application/json'};
  }

  @override
  Future<bool> testConnection() async {
    try {
      final result = await executeQuery('SELECT 1 as test');
      return result.error == null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final body = jsonEncode({
        'query': sql,
        'database': config.databaseName,
        'user': config.user,
        'password': config.password,
      });

      final resp = await http
          .post(Uri.parse('$_proxyUrl/sql'), headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) return _parseResponse(resp.body);

      // Try /query endpoint as fallback
      final altResp = await http
          .post(Uri.parse('$_proxyUrl/query'), headers: _headers, body: body)
          .timeout(const Duration(seconds: 10));

      if (altResp.statusCode == 200) return _parseResponse(altResp.body);

      return QueryResult(
          error: 'Connection error (HTTP ${resp.statusCode}). '
              'Custom databases need an HTTP SQL proxy (e.g. "postgres-http-proxy") running at $_proxyUrl');
    } on SocketException catch (e) {
      return QueryResult(error: 'Cannot reach $_proxyUrl. Is the proxy running?\n$e');
    } catch (e) {
      return QueryResult(error: 'Custom DB error: $e');
    }
  }

  QueryResult _parseResponse(String body) {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      if (data['error'] != null) return QueryResult(error: data['error'].toString());
      final rows = (data['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      if (rows.isNotEmpty) return QueryResult(columns: rows.first.keys.toList(), rows: rows, rowCount: rows.length);
      return QueryResult(columns: [], rows: [], affectedRows: data['affected_rows'] as int?);
    }
    return QueryResult(columns: [], rows: []);
  }

  @override
  Future<QueryResult> getSchema() {
    return executeQuery("SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}
