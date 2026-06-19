import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pluradb/models/database_config.dart';
import 'package:pluradb/models/query_history.dart';

class StorageService {
  static const String _dbFile = 'pluradb_databases.json';
  static const String _historyFile = 'pluradb_history.json';

  Future<Directory> _getDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/pluradb');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // === Databases ===

  Future<List<DatabaseConfig>> getDatabases() async {
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/$_dbFile');
      if (!await file.exists()) return [];
      final str = await file.readAsString();
      final List data = jsonDecode(str);
      return data.map((e) => DatabaseConfig.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDatabases(List<DatabaseConfig> dbs) async {
    final dir = await _getDir();
    final file = File('${dir.path}/$_dbFile');
    final json = jsonEncode(dbs.map((d) => d.toJson()).toList());
    await file.writeAsString(json);
  }

  Future<void> addDatabase(DatabaseConfig db) async {
    final dbs = await getDatabases();
    dbs.add(db);
    await saveDatabases(dbs);
  }

  Future<void> updateDatabase(DatabaseConfig db) async {
    final dbs = await getDatabases();
    final idx = dbs.indexWhere((d) => d.id == db.id);
    if (idx >= 0) {
      dbs[idx] = db;
      await saveDatabases(dbs);
    }
  }

  Future<void> deleteDatabase(String id) async {
    final dbs = await getDatabases();
    dbs.removeWhere((d) => d.id == id);
    await saveDatabases(dbs);
  }

  // === Query History ===

  Future<List<QueryHistoryEntry>> getQueryHistory(String databaseId) async {
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/$_historyFile');
      if (!await file.exists()) return [];
      final str = await file.readAsString();
      final List data = jsonDecode(str);
      return data
          .map((e) => QueryHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .where((h) => h.databaseId == databaseId)
          .toList()
        ..sort((a, b) => b.executedAt.compareTo(a.executedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> addQueryHistory(QueryHistoryEntry entry) async {
    final dir = await _getDir();
    final file = File('${dir.path}/$_historyFile');
    List data = [];
    if (await file.exists()) {
      data = jsonDecode(await file.readAsString());
    }
    data.add(entry.toJson());
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> clearAllHistory() async {
    final dir = await _getDir();
    final file = File('${dir.path}/$_historyFile');
    if (await file.exists()) await file.delete();
  }

  // === Export / Import ===

  Future<String> exportAll() async {
    final dbs = await getDatabases();
    return jsonEncode({'version': 1, 'databases': dbs.map((d) => d.toJson()).toList()});
  }

  Future<void> importAll(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = (data['databases'] as List).map((e) => DatabaseConfig.fromJson(Map<String, dynamic>.from(e))).toList();
    await saveDatabases(list);
  }

  Future<void> clearAll() async {
    final dir = await _getDir();
    final dbFile = File('${dir.path}/$_dbFile');
    final histFile = File('${dir.path}/$_historyFile');
    if (await dbFile.exists()) await dbFile.delete();
    if (await histFile.exists()) await histFile.delete();
  }
}
