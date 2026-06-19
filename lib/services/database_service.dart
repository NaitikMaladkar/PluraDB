import 'dart:convert';
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
      case ProviderType.custom:
        return CustomPostgresService(config);
    }
  }
}

class SupabaseService implements DatabaseService {
  final DatabaseConfig config;
  SupabaseService(this.config);

  Map<String, String> get _headers {
    final key = config.serviceRoleKey.isNotEmpty ? config.serviceRoleKey : config.anonKey;
    return {
      'apikey': config.anonKey,
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
    };
  }

  String get _baseUrl {
    final url = config.projectUrl.replaceAll(RegExp(r'/+$'), '');
    return '$url/rest/v1';
  }

  @override
  Future<bool> testConnection() async {
    try {
      final resp = await http.get(Uri.parse('$_baseUrl/'), headers: _headers).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200 || resp.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> getSchema() async {
    try {
      final url = config.projectUrl.replaceAll(RegExp(r'/+$'), '');
      final resp = await http.get(Uri.parse('$url/rest/v1/'), headers: {..._headers, 'Accept': 'application/json'}).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return QueryResult(error: 'Failed to fetch schema: ${resp.statusCode}');
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
            final columns = ((selectParam['schema']?['enum'] as List?) ?? ['*']).map((c) => c.toString().trim()).where((c) => c != '*').toList();
            schemas.add({
              'table': tableName,
              'columns': columns.isEmpty ? '*' : columns.join(', '),
            });
          }
        }
      }

      if (schemas.isEmpty) {
        return await executeQuery(
            "SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position");
      }

      return QueryResult(
        columns: ['Table', 'Columns'],
        rows: schemas.map((s) => {'Table': s['table'] as String, 'Columns': s['columns'] as String}).toList(),
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

      if (resp.statusCode == 406) return QueryResult(error: 'Table "$table" not found or access denied');
      if (resp.statusCode != 200) return QueryResult(error: 'Error ${resp.statusCode}: ${resp.body}');

      final data = jsonDecode(resp.body) as List;
      if (data.isEmpty) return QueryResult(columns: [], rows: [], rowCount: 0);

      final columns = (data[0] as Map<String, dynamic>).keys.toList();
      final rows = data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
      final contentRange = resp.headers['content-range'];
      int? totalCount;
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
      if (trimmedSql.startsWith('SELECT') || trimmedSql.startsWith('WITH')) {
        final tableMatch = RegExp(r'FROM\s+(\w+)', caseSensitive: false).firstMatch(sql);
        if (tableMatch != null) return getTableData(tableMatch.group(1)!);
        if (config.serviceRoleKey.isEmpty) {
          return QueryResult(error: 'Service role key required for raw SQL. Add it in database settings.');
        }
        final url = config.projectUrl.replaceAll(RegExp(r'/+$'), '');
        final resp = await http.post(Uri.parse('$url/rest/v1/rpc/'), headers: _headers, body: jsonEncode({'query': sql})).timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200 && resp.statusCode != 201) {
          return QueryResult(error: 'Query error (${resp.statusCode}): ${resp.body}');
        }
        try {
          final data = jsonDecode(resp.body);
          if (data is List) {
            if (data.isEmpty) return QueryResult(columns: [], rows: [], rowCount: 0);
            final columns = (data[0] as Map<String, dynamic>).keys.toList();
            final rows = data.map((r) => Map<String, dynamic>.from(r as Map)).toList();
            return QueryResult(columns: columns, rows: rows, rowCount: rows.length);
          }
        } catch (_) {}
        return QueryResult(columns: [], rows: []);
      }

      if (config.serviceRoleKey.isEmpty) return QueryResult(error: 'Service role key required for write operations');
      final url = config.projectUrl.replaceAll(RegExp(r'/+$'), '');
      final resp = await http.post(Uri.parse('$url/rest/v1/rpc/exec_sql'), headers: _headers, body: jsonEncode({'sql_query': sql})).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        if (trimmedSql.startsWith('INSERT')) {
          final tableMatch = RegExp(r'INTO\s+(\w+)', caseSensitive: false).firstMatch(sql);
          if (tableMatch != null) {
            final insertResp = await http.post(Uri.parse('$_baseUrl/${tableMatch.group(1)}'), headers: _headers, body: '{}').timeout(const Duration(seconds: 15));
            if (insertResp.statusCode == 201) return QueryResult(affectedRows: 1, columns: [], rows: []);
          }
        }
        return QueryResult(error: 'Query error (${resp.statusCode}): ${resp.body}');
      }
      return QueryResult(columns: ['result'], rows: [{'result': 'Query executed successfully'}]);
    } catch (e) {
      return QueryResult(error: 'Query execution error: $e');
    }
  }
}

class NeonService implements DatabaseService {
  final DatabaseConfig config;
  NeonService(this.config);

  @override
  Future<bool> testConnection() async {
    try {
      final result = await executeQuery('SELECT 1');
      return result.isSuccess;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final host = config.connectionString.isNotEmpty ? Uri.parse(config.connectionString).host : config.host;
      final uri = Uri.parse('https://$host/sql').replace(queryParameters: {
        'database': config.databaseName,
        'user': config.user,
        'password': config.password,
      });
      final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'query': sql})).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return QueryResult(error: 'Neon error (${resp.statusCode}): ${resp.body}');
      final data = jsonDecode(resp.body);
      if (data['error'] != null) return QueryResult(error: data['error'].toString());
      final rows = (data['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      if (rows.isEmpty) {
        final tag = data['command_tag'] as String?;
        final match = tag != null ? RegExp(r'(\d+)').firstMatch(tag) : null;
        return QueryResult(columns: [], rows: [], rowCount: 0, affectedRows: match != null ? int.parse(match.group(1)!) : null);
      }
      return QueryResult(columns: rows.first.keys.toList(), rows: rows, rowCount: rows.length);
    } catch (e) {
      return QueryResult(error: 'Neon connection error: $e');
    }
  }

  @override
  Future<QueryResult> getSchema() async {
    return executeQuery("SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) async {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}

class PlanetScaleService implements DatabaseService {
  final DatabaseConfig config;
  PlanetScaleService(this.config);

  @override
  Future<bool> testConnection() async {
    try {
      final result = await executeQuery('SELECT 1');
      return result.isSuccess;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final uri = Uri.parse('https://${config.host}/v1/tables/${config.databaseName}/query');
      final resp = await http.post(uri, headers: {'Authorization': 'Bearer ${config.password}', 'Content-Type': 'application/json'}, body: jsonEncode({'query': sql})).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return QueryResult(error: 'PlanetScale error (${resp.statusCode}): ${resp.body}');
      final data = jsonDecode(resp.body);
      final rows = (data['results'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      return QueryResult(columns: rows.isEmpty ? [] : rows.first.keys.toList(), rows: rows, rowCount: rows.length);
    } catch (e) {
      return QueryResult(error: 'PlanetScale connection error: $e');
    }
  }

  @override
  Future<QueryResult> getSchema() async {
    return executeQuery("SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = DATABASE() ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) async {
    return executeQuery('SELECT * FROM `$table` LIMIT $limit OFFSET $offset');
  }
}

class TursoService implements DatabaseService {
  final DatabaseConfig config;
  TursoService(this.config);

  @override
  Future<bool> testConnection() async {
    try {
      final result = await executeQuery('SELECT 1');
      return result.isSuccess;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final dbUrl = config.databaseUrl;
      String orgName = '_';
      String dbName = '_';
      final match = RegExp(r'libsql://([a-z0-9-]+)-([a-z0-9-]+)-').firstMatch(dbUrl);
      if (match != null) {
        orgName = match.group(1)!;
        dbName = match.group(2)!;
      }
      final endpoint = Uri.parse('https://api.turso.tech/v1/organizations/$orgName/databases/$dbName/query');
      final resp = await http.post(endpoint, headers: {'Authorization': 'Bearer ${config.authToken}', 'Content-Type': 'application/json'}, body: jsonEncode({'query': sql})).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return QueryResult(error: 'Turso error (${resp.statusCode}): ${resp.body}');
      final data = jsonDecode(resp.body);
      final results = data['results'] as Map<String, dynamic>? ?? {};
      final rows = (results['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      final cols = (results['cols'] as List?)?.map((c) => c['name'].toString()).toList() ?? [];
      return QueryResult(columns: cols, rows: rows, rowCount: rows.length);
    } catch (e) {
      return QueryResult(error: 'Turso connection error: $e');
    }
  }

  @override
  Future<QueryResult> getSchema() async {
    return executeQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) async {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}

class CustomPostgresService implements DatabaseService {
  final DatabaseConfig config;
  CustomPostgresService(this.config);

  @override
  Future<bool> testConnection() async {
    try {
      final result = await executeQuery('SELECT 1 as test');
      return result.isSuccess;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QueryResult> executeQuery(String sql) async {
    try {
      final uri = Uri.parse('http://${config.host}:${config.port}/sql');
      final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'query': sql, 'database': config.databaseName, 'user': config.user, 'password': config.password})).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return QueryResult(error: 'Connection error (${resp.statusCode}). Custom databases require an HTTP SQL proxy endpoint.');
      final data = jsonDecode(resp.body);
      final rows = (data['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
      return QueryResult(columns: rows.isEmpty ? [] : rows.first.keys.toList(), rows: rows, rowCount: rows.length);
    } catch (e) {
      return QueryResult(error: 'Custom DB connection error: $e. Note: Custom databases require an HTTP SQL proxy to be accessible from a mobile app.');
    }
  }

  @override
  Future<QueryResult> getSchema() async {
    return executeQuery("SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position");
  }

  @override
  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) async {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }
}
