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
// ═══════════════════════════════════════════════════

class SupabaseService implements DatabaseService {
  final DatabaseConfig config;
  SupabaseService(this.config);

  Map<String, String> get _headers {
    final key = config.serviceRoleKey.isNotEmpty ? config.serviceRoleKey : config.anonKey;
    return {
      'apikey': config.anonKey,
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
  }

  String get _baseUrl {
    final url = config.projectUrl.replaceAll(RegExp(r'/+$'), '');
    return '$url/rest/v1';
  }

  @override
  Future<bool> testConnection() async {
    try {
      // Try fetching the OpenAPI spec — this endpoint always exists
      final resp = await http
          .get(Uri.parse('$_baseUrl/'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return true;
      // Also try a simple health check alternative
      final url = config.projectUrl.replaceAll(RegExp(r'/+$'), '');
      final healthResp = await http
          .get(Uri.parse('$url/rest/v1/'), headers: {
            'apikey': config.anonKey,
            'Authorization': 'Bearer ${config.serviceRoleKey.isNotEmpty ? config.serviceRoleKey : config.anonKey}',
          })
          .timeout(const Duration(seconds: 10));
      return healthResp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<QueryResult> getSchema() async {
    try {
      final url = config.projectUrl.replaceAll(RegExp(r'/+$'), '');
      final resp = await http
          .get(
            Uri.parse('$url/rest/v1/'),
            headers: {
              ..._headers,
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return QueryResult(error: 'Failed to fetch schema (HTTP ${resp.statusCode})');
      }

      final data = jsonDecode(resp.body);
      final paths = data['paths'] as Map<String, dynamic>? ?? {};
      final schemas = <Map<String, String>>[];

      for (final path in paths.keys) {
        final match = RegExp(r'^/(\w+)$').firstMatch(path);
        if (match != null) {
          final tableName = match.group(1)!;
          final getOp = paths[path]['get'] as Map<String, dynamic>?;
          if (getOp != null) {
            final params = (getOp['parameters'] as List?) ?? [];
            final selectParam = params.firstWhere(
              (p) => p['name'] == 'select',
              orElse: () => {'schema': {'enum': ['*']}},
            );
            final columns = ((selectParam['schema']?['enum'] as List?) ?? ['*'])
                .map((c) => c.toString().trim())
                .where((c) => c != '*')
                .toList();
            schemas.add({
              'table': tableName,
              'columns': columns.isEmpty ? '*' : columns.join(', '),
            });
          }
        }
      }

      if (schemas.isEmpty) {
        // Fallback: try to get at least table names via PostgREST
        // We'll try querying any public table
        return QueryResult(
          columns: ['Table', 'Columns'],
          rows: schemas
              .map((s) => {
                    'Table': s['table'] as String,
                    'Columns': s['columns'] as String
                  })
              .toList(),
          rowCount: schemas.length,
        );
      }

      return QueryResult(
        columns: ['Table', 'Columns'],
        rows: schemas
            .map((s) => {
                  'Table': s['table'] as String,
                  'Columns': s['columns'] as String
                })
            .toList(),
        rowCount: schemas.length,
      );
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

      if (resp.statusCode == 406) {
        return QueryResult(error: 'Table "$table" not found or access denied');
      }
      if (resp.statusCode != 200) {
        return QueryResult(error: 'Error ${resp.statusCode}: ${resp.body}');
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
    } catch (e) {
      return QueryResult(error: 'Error fetching table data: $e');
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final trimmedSql = sql.trim().toUpperCase();

      // SELECT queries — try PostgREST table-level fetch
      if (trimmedSql.startsWith('SELECT') || trimmedSql.startsWith('WITH')) {
        // Try to parse the table name from FROM clause
        final tableMatch = RegExp(r'FROM\s+(\w+)', caseSensitive: false).firstMatch(sql);
        if (tableMatch != null) {
          return getTableData(tableMatch.group(1)!);
        }
        // If no table found, it might be a complex query
        return QueryResult(error: 'Complex SELECT queries must reference a specific table for PostgREST. Try: SELECT * FROM table_name');
      }

      // INSERT via PostgREST
      if (trimmedSql.startsWith('INSERT')) {
        final tableMatch = RegExp(r'INTO\s+(\w+)', caseSensitive: false).firstMatch(sql);
        if (tableMatch != null) {
          final tableName = tableMatch.group(1)!;
          // Try to extract values from INSERT
          final valuesMatch = RegExp(r"VALUES\s*\((.+)\)", caseSensitive: false).firstMatch(sql);
          if (valuesMatch != null) {
            // Build a simple row from the VALUES clause
            final valuesStr = valuesMatch.group(1)!;
            final values = _parseSqlValues(valuesStr);
            final columnsMatch = RegExp(r'\(([^)]+)\)\s*VALUES', caseSensitive: false).firstMatch(sql);
            if (columnsMatch != null) {
              final cols = columnsMatch.group(1)!.split(',').map((c) => c.trim()).toList();
              final row = <String, dynamic>{};
              for (int i = 0; i < cols.length && i < values.length; i++) {
                row[cols[i]] = values[i];
              }
              final resp = await http
                  .post(Uri.parse('$_baseUrl/$tableName'), headers: _headers, body: jsonEncode(row))
                  .timeout(const Duration(seconds: 15));
              if (resp.statusCode == 201) {
                return QueryResult(affectedRows: 1, columns: [], rows: []);
              }
              return QueryResult(error: 'Insert error (${resp.statusCode}): ${resp.body}');
            }
          }
          // Fallback: try empty insert
          final resp = await http
              .post(Uri.parse('$_baseUrl/$tableName'), headers: _headers, body: '{}')
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode == 201) return QueryResult(affectedRows: 1, columns: [], rows: []);
          return QueryResult(error: 'Insert error (${resp.statusCode}): ${resp.body}');
        }
      }

      // UPDATE via PostgREST
      if (trimmedSql.startsWith('UPDATE')) {
        final tableMatch = RegExp(r'UPDATE\s+(\w+)', caseSensitive: false).firstMatch(sql);
        if (tableMatch != null) {
          final tableName = tableMatch.group(1)!;
          // Extract SET values
          final setMatch = RegExp(r'SET\s+(.+?)(?:\s+WHERE\s+|\s*$)', caseSensitive: false, dotAll: true).firstMatch(sql);
          if (setMatch != null) {
            final setData = _parseSetClause(setMatch.group(1)!);
            // Extract WHERE clause for PostgREST filter
            final whereMatch = RegExp(r'WHERE\s+(.+)$', caseSensitive: false).firstMatch(sql);
            String filter = '';
            if (whereMatch != null) {
              filter = '&${_sqlWhereToPostgrestFilter(whereMatch.group(1)!.trim())}';
            }
            final uri = Uri.parse('$_baseUrl/$tableName?$filter');
            final resp = await http
                .patch(uri, headers: _headers, body: jsonEncode(setData))
                .timeout(const Duration(seconds: 15));
            if (resp.statusCode == 200) {
              final updated = jsonDecode(resp.body) as List;
              return QueryResult(affectedRows: updated.length, columns: [], rows: []);
            }
            return QueryResult(error: 'Update error (${resp.statusCode}): ${resp.body}');
          }
        }
      }

      // DELETE via PostgREST
      if (trimmedSql.startsWith('DELETE')) {
        final tableMatch = RegExp(r'FROM\s+(\w+)', caseSensitive: false).firstMatch(sql);
        if (tableMatch != null) {
          final tableName = tableMatch.group(1)!;
          final whereMatch = RegExp(r'WHERE\s+(.+)$', caseSensitive: false).firstMatch(sql);
          String filter = '';
          if (whereMatch != null) {
            filter = '?${_sqlWhereToPostgrestFilter(whereMatch.group(1)!.trim())}';
          }
          final uri = Uri.parse('$_baseUrl/$tableName$filter');
          final resp = await http
              .delete(uri, headers: _headers)
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode == 204 || resp.statusCode == 200) {
            return QueryResult(affectedRows: 1, columns: [], rows: []);
          }
          return QueryResult(error: 'Delete error (${resp.statusCode}): ${resp.body}');
        }
      }

      return QueryResult(error: 'Unsupported query type. PostgREST supports SELECT, INSERT, UPDATE, DELETE on tables.');
    } catch (e) {
      return QueryResult(error: 'Query execution error: $e');
    }
  }

  List<dynamic> _parseSqlValues(String valuesStr) {
    return valuesStr.split(',').map((v) {
      v = v.trim();
      if ((v.startsWith("'") && v.endsWith("'")) || (v.startsWith('"') && v.endsWith('"'))) {
        return v.substring(1, v.length - 1);
      }
      if (v.toLowerCase() == 'null') return null;
      if (v.toLowerCase() == 'true') return true;
      if (v.toLowerCase() == 'false') return false;
      return int.tryParse(v) ?? double.tryParse(v) ?? v;
    }).toList();
  }

  Map<String, dynamic> _parseSetClause(String setStr) {
    final result = <String, dynamic>{};
    final pairs = setStr.split(',');
    for (final pair in pairs) {
      final parts = pair.trim().split(RegExp(r'\s*=\s*'));
      if (parts.length == 2) {
        final col = parts[0].trim();
        var val = parts[1].trim();
        if ((val.startsWith("'") && val.endsWith("'")) || (val.startsWith('"') && val.endsWith('"'))) {
          val = val.substring(1, val.length - 1);
        } else if (val.toLowerCase() == 'null') {
          val = '';
        }
        final numVal = int.tryParse(val) ?? double.tryParse(val);
        result[col] = numVal ?? val;
      }
    }
    return result;
  }

  String _sqlWhereToPostgrestFilter(String where) {
    // Simple WHERE clause to PostgREST filter conversion
    return where
        .replaceAll(RegExp(r"(\w+)\s*=\s*'([^']*)'"), r'\1.eq.\2')
        .replaceAll(RegExp(r"(\w+)\s*=\s*(\d+)"), r'\1.eq.\2')
        .replaceAll(RegExp(r"(\w+)\s*=\s*(\w+)"), r'\1.eq.\2')
        .replaceAll(RegExp(r'\s+AND\s+'), '&')
        .replaceAll(RegExp(r'\s+OR\s+'), '|');
  }
}

// ═══════════════════════════════════════════════════
// NEON — HTTP SQL Proxy
// ═══════════════════════════════════════════════════

class NeonService implements DatabaseService {
  final DatabaseConfig config;
  NeonService(this.config);

  String get _host {
    if (config.connectionString.isNotEmpty) {
      try {
        final uri = Uri.parse(config.connectionString);
        return uri.host;
      } catch (_) {}
    }
    return config.host;
  }

  String get _user {
    if (config.connectionString.isNotEmpty) {
      try {
        final uri = Uri.parse(config.connectionString);
        return uri.userInfo.split(':').first;
      } catch (_) {}
    }
    return config.user;
  }

  String get _password {
    if (config.connectionString.isNotEmpty) {
      try {
        final uri = Uri.parse(config.connectionString);
        final parts = uri.userInfo.split(':');
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
    final credentials = base64Encode(utf8.encode('$_user:$_password'));
    return {
      'Authorization': 'Basic $credentials',
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
      // Neon serverless driver HTTP endpoint
      final uri = Uri.parse('https://$_host/sql');
      final resp = await http
          .post(uri, headers: _headers, body: jsonEncode({'query': sql}))
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return QueryResult(error: 'Neon error (HTTP ${resp.statusCode}): ${resp.body}');
      }

      final data = jsonDecode(resp.body);

      // Handle different response formats
      if (data is Map<String, dynamic>) {
        if (data['error'] != null) {
          return QueryResult(error: 'Neon SQL error: ${data['error']}');
        }

        // Standard Neon HTTP response: {"results": [...], "command_tag": "SELECT 1"}
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map<String, dynamic>;
          final columns = (first['columns'] as List?)?.map((c) => c.toString()).toList() ?? first.keys.toList();
          final rows = (first['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
          return QueryResult(columns: columns, rows: rows, rowCount: rows.length);
        }

        // Alternative format: rows directly
        final rows = (data['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
        if (rows.isNotEmpty) {
          return QueryResult(columns: rows.first.keys.toList(), rows: rows, rowCount: rows.length);
        }

        // No rows returned (INSERT/UPDATE/DELETE)
        final tag = data['command_tag'] as String?;
        final rowCount = _parseCommandTag(tag);
        return QueryResult(columns: [], rows: [], affectedRows: rowCount);
      }

      return QueryResult(columns: [], rows: []);
    } on SocketException catch (e) {
      return QueryResult(error: 'Network error: Cannot reach $_host. Ensure the host is correct and network is available. ($e)');
    } catch (e) {
      return QueryResult(error: 'Neon connection error: $e');
    }
  }

  int? _parseCommandTag(String? tag) {
    if (tag == null) return null;
    final match = RegExp(r'(\d+)').firstMatch(tag);
    return match != null ? int.parse(match.group(1)!) : null;
  }

  @override
  Future<QueryResult> getSchema() async {
    return executeQuery(
        "SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}

// ═══════════════════════════════════════════════════
// PLANETSCALE — HTTP API
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
      // PlanetScale API: POST /v1/organizations/{org}/databases/{db}/query
      // Or use the simplified host-based endpoint
      final host = config.host.trim();
      final dbName = config.databaseName.trim();

      // Try the PlanetScale API endpoint
      final uri = Uri.parse('https://$host/v1/databases/$dbName/query');
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

      if (resp.statusCode != 200) {
        // Try alternative endpoint format
        final altUri = Uri.parse('https://$host');
        final altResp = await http
            .post(
              altUri,
              headers: {
                'Authorization': 'Bearer ${config.password}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'query': sql, 'database': dbName}),
            )
            .timeout(const Duration(seconds: 15));

        if (altResp.statusCode != 200) {
          return QueryResult(
              error: 'PlanetScale error (HTTP ${resp.statusCode}). '
                  'Ensure host and password/token are correct. '
                  'Note: PlanetScale requires an HTTP SQL proxy or API access.');
        }

        return _parsePlanetScaleResponse(altResp.body);
      }

      return _parsePlanetScaleResponse(resp.body);
    } on SocketException catch (e) {
      return QueryResult(error: 'Network error: Cannot reach ${config.host}. ($e)');
    } catch (e) {
      return QueryResult(error: 'PlanetScale connection error: $e');
    }
  }

  QueryResult _parsePlanetScaleResponse(String body) {
    final data = jsonDecode(body);
    final rows = (data['results'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
    if (rows.isEmpty) {
      return QueryResult(columns: [], rows: [], affectedRows: 0);
    }
    return QueryResult(columns: rows.first.keys.toList(), rows: rows, rowCount: rows.length);
  }

  @override
  Future<QueryResult> getSchema() async {
    return executeQuery(
        "SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = DATABASE() ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM `$table` LIMIT $limit OFFSET $offset');
  }
}

// ═══════════════════════════════════════════════════
// TURSO — libsql HTTP API
// ═══════════════════════════════════════════════════

class TursoService implements DatabaseService {
  final DatabaseConfig config;
  TursoService(this.config);

  /// Parse organization name and database name from Turso URL
  /// Format: libsql://my-db-my-org.turso.io or turso://my-db-my-org.turso.io
  Map<String, String> _parseTursoUrl(String url) {
    // Try format: libsql://dbname-orgname.turso.io
    final domainMatch = RegExp(r'libsql://([a-z0-9_-]+)\.turso\.io').firstMatch(url);
    if (domainMatch != null) {
      final name = domainMatch.group(1)!;
      // Format is typically: dbname-orgname
      final parts = name.split('-');
      if (parts.length >= 2) {
        return {'org': parts.last, 'db': parts.sublist(0, parts.length - 1).join('-')};
      }
      return {'org': '_', 'db': name};
    }

    // Try format with explicit path: libsql://orgname-tursoio.dbs.turso.io/dbname
    final pathMatch = RegExp(r'libsql://[^/]+/(.+)$').firstMatch(url);
    if (pathMatch != null) {
      final dbName = pathMatch.group(1)!;
      final orgMatch = RegExp(r'libsql://([a-z0-9-]+)\.').firstMatch(url);
      final org = orgMatch != null ? orgMatch.group(1)!.split('-').first : '_';
      return {'org': org, 'db': dbName};
    }

    return {'org': '_', 'db': '_'};
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
      final dbUrl = config.databaseUrl.trim();

      // Parse org and db from URL
      final parsed = _parseTursoUrl(dbUrl);
      final orgName = parsed['org']!;
      final dbName = parsed['db']!;

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
            error: 'Turso database not found. Check your database URL format. '
                'Expected: libsql://dbname-orgname.turso.io\n'
                'Parsed org="$orgName", db="$dbName"');
      }
      if (resp.statusCode == 401) {
        return QueryResult(error: 'Turso auth failed. Check your auth token.');
      }
      if (resp.statusCode != 200) {
        return QueryResult(error: 'Turso error (HTTP ${resp.statusCode}): ${resp.body}');
      }

      final data = jsonDecode(resp.body);
      final results = data['results'] as Map<String, dynamic>? ?? {};
      final rows = (results['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      final cols = (results['cols'] as List?)?.map((c) => (c['name'] ?? c).toString()).toList() ?? [];

      if (rows.isEmpty && cols.isEmpty) {
        // For DDL statements or empty results
        return QueryResult(columns: [], rows: [], affectedRows: 0);
      }

      return QueryResult(columns: cols, rows: rows, rowCount: rows.length);
    } on SocketException catch (e) {
      return QueryResult(error: 'Network error: Cannot reach Turso API. ($e)');
    } catch (e) {
      return QueryResult(error: 'Turso connection error: $e');
    }
  }

  @override
  Future<QueryResult> getSchema() async {
    return executeQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}

// ═══════════════════════════════════════════════════
// COCKROACHDB — HTTP SQL Proxy
// ═══════════════════════════════════════════════════

class CockroachDBService implements DatabaseService {
  final DatabaseConfig config;
  CockroachDBService(this.config);

  /// CockroachDB uses PostgreSQL wire protocol.
  /// For HTTP access from mobile, you need an HTTP SQL proxy.
  /// The proxy endpoint is expected to accept POST /sql with JSON body.
  String get _proxyUrl {
    // User can either provide a full proxy URL or we construct one
    if (config.host.startsWith('http://') || config.host.startsWith('https://')) {
      return config.host.replaceAll(RegExp(r'/+$'), '');
    }
    final port = config.port.isNotEmpty ? config.port : '26257';
    return 'http://${config.host}:$port';
  }

  Map<String, String> get _headers {
    if (config.anonKey.isNotEmpty) {
      // If user provided an API key/token for the proxy
      return {
        'Authorization': 'Bearer ${config.anonKey}',
        'Content-Type': 'application/json',
      };
    }
    // Basic auth with user:password
    final credentials = base64Encode(utf8.encode('${config.user}:${config.password}'));
    return {
      'Authorization': 'Basic $credentials',
      'Content-Type': 'application/json',
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
      final uri = Uri.parse('$_proxyUrl/sql');
      final body = jsonEncode({
        'query': sql,
        'database': config.databaseName,
        'user': config.user,
        'password': config.password,
      });

      final resp = await http
          .post(uri, headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        // Try alternative endpoint (some proxies use /query instead of /sql)
        final altUri = Uri.parse('$_proxyUrl/query');
        final altResp = await http
            .post(altUri, headers: _headers, body: body)
            .timeout(const Duration(seconds: 10));

        if (altResp.statusCode != 200) {
          return QueryResult(
              error: 'CockroachDB proxy error (HTTP ${resp.statusCode}). '
                  'Ensure your HTTP SQL proxy is running and accessible.\n'
                  'CockroachDB requires an HTTP SQL proxy for mobile access. '
                  'Set up a proxy like "pg-proxy" or "postgres-http-proxy".');
        }
        return _parseProxyResponse(altResp.body);
      }

      return _parseProxyResponse(resp.body);
    } on SocketException catch (e) {
      return QueryResult(
          error: 'Network error: Cannot reach $_proxyUrl. '
              'Ensure your HTTP SQL proxy is running and the host/port is correct.\n'
              '($e)');
    } catch (e) {
      return QueryResult(error: 'CockroachDB connection error: $e');
    }
  }

  QueryResult _parseProxyResponse(String body) {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      if (data['error'] != null) {
        return QueryResult(error: data['error'].toString());
      }
      final rows = (data['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      if (rows.isNotEmpty) {
        return QueryResult(columns: rows.first.keys.toList(), rows: rows, rowCount: rows.length);
      }
      return QueryResult(columns: [], rows: [], affectedRows: data['affected_rows'] as int?);
    }
    return QueryResult(columns: [], rows: []);
  }

  @override
  Future<QueryResult> getSchema() async {
    return executeQuery(
        "SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}

// ═══════════════════════════════════════════════════
// CUSTOM POSTGRESQL — HTTP SQL Proxy
// ═══════════════════════════════════════════════════

class CustomPostgresService implements DatabaseService {
  final DatabaseConfig config;
  CustomPostgresService(this.config);

  String get _proxyUrl {
    if (config.host.startsWith('http://') || config.host.startsWith('https://')) {
      return config.host.replaceAll(RegExp(r'/+$'), '');
    }
    final port = config.port.isNotEmpty ? config.port : '5432';
    return 'http://${config.host}:$port';
  }

  Map<String, String> get _headers {
    if (config.anonKey.isNotEmpty) {
      return {
        'Authorization': 'Bearer ${config.anonKey}',
        'Content-Type': 'application/json',
      };
    }
    final credentials = base64Encode(utf8.encode('${config.user}:${config.password}'));
    return {
      'Authorization': 'Basic $credentials',
      'Content-Type': 'application/json',
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
      final uri = Uri.parse('$_proxyUrl/sql');
      final body = jsonEncode({
        'query': sql,
        'database': config.databaseName,
        'user': config.user,
        'password': config.password,
      });

      final resp = await http
          .post(uri, headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        // Try alternative endpoint
        final altUri = Uri.parse('$_proxyUrl/query');
        final altResp = await http
            .post(altUri, headers: _headers, body: body)
            .timeout(const Duration(seconds: 10));

        if (altResp.statusCode != 200) {
          return QueryResult(
              error: 'Connection error (HTTP ${resp.statusCode}). '
                  'Custom databases require an HTTP SQL proxy (e.g., "postgres-http-proxy") '
                  'running and accessible from your device.');
        }
        return _parseProxyResponse(altResp.body);
      }

      return _parseProxyResponse(resp.body);
    } on SocketException catch (e) {
      return QueryResult(
          error: 'Network error: Cannot reach $_proxyUrl. '
          'Ensure your HTTP SQL proxy is running.\n($e)');
    } catch (e) {
      return QueryResult(error: 'Custom DB connection error: $e');
    }
  }

  QueryResult _parseProxyResponse(String body) {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      if (data['error'] != null) {
        return QueryResult(error: data['error'].toString());
      }
      final rows = (data['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      if (rows.isNotEmpty) {
        return QueryResult(columns: rows.first.keys.toList(), rows: rows, rowCount: rows.length);
      }
      return QueryResult(columns: [], rows: [], affectedRows: data['affected_rows'] as int?);
    }
    return QueryResult(columns: [], rows: []);
  }

  @override
  Future<QueryResult> getSchema() async {
    return executeQuery(
        "SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}
