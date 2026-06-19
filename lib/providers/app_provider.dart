import 'package:flutter/foundation.dart';
import 'package:pluradb/models/database_config.dart';
import 'package:pluradb/models/query_history.dart';
import 'package:pluradb/models/query_result.dart';
import 'package:pluradb/services/database_service.dart';
import 'package:pluradb/services/storage_service.dart';
import 'package:uuid/uuid.dart';

class AppProvider extends ChangeNotifier {
  final StorageService _storage;
  List<DatabaseConfig> _databases = [];
  DatabaseConfig? _selectedDatabase;
  DatabaseService? _activeDbService;
  QueryResult? _lastQueryResult;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _error;

  AppProvider(this._storage) {
    _loadData();
  }

  List<DatabaseConfig> get databases => List.unmodifiable(_databases);
  DatabaseConfig? get selectedDatabase => _selectedDatabase;
  QueryResult? get lastQueryResult => _lastQueryResult;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;

  Future<void> _loadData() async {
    _databases = await _storage.getDatabases();
    _isInitialized = true;
    notifyListeners();
  }

  // Database CRUD
  Future<void> addDatabase(DatabaseConfig db) async {
    _databases.add(db);
    await _storage.addDatabase(db);
    notifyListeners();
  }

  Future<void> updateDatabase(DatabaseConfig db) async {
    final idx = _databases.indexWhere((d) => d.id == db.id);
    if (idx >= 0) {
      _databases[idx] = db;
      await _storage.updateDatabase(db);
      notifyListeners();
    }
  }

  Future<void> deleteDatabase(String dbId) async {
    _databases.removeWhere((d) => d.id == dbId);
    await _storage.deleteDatabase(dbId);
    if (_selectedDatabase?.id == dbId) {
      _selectedDatabase = null;
      _activeDbService = null;
    }
    notifyListeners();
  }

  // Connection
  Future<bool> selectDatabase(DatabaseConfig db) async {
    _selectedDatabase = db;
    _activeDbService = DatabaseServiceFactory.create(db);
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final connected = await _activeDbService!.testConnection();
      _isLoading = false;
      if (!connected) {
        _error = 'Connection failed. Check your credentials, network, and that the URL/host is correct.';
      }
      notifyListeners();
      return connected;
    } catch (e) {
      _isLoading = false;
      _error = 'Connection error: $e';
      notifyListeners();
      return false;
    }
  }

  void clearDatabaseSelection() {
    _selectedDatabase = null;
    _activeDbService = null;
    _lastQueryResult = null;
    notifyListeners();
  }

  Future<QueryResult> getSchema() async {
    if (_activeDbService == null) return QueryResult(error: 'No database selected');
    _isLoading = true;
    notifyListeners();
    try {
      final result = await _activeDbService!.getSchema();
      _lastQueryResult = result;
      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isLoading = false;
      final result = QueryResult(error: 'Schema fetch error: $e');
      _lastQueryResult = result;
      notifyListeners();
      return result;
    }
  }

  Future<QueryResult> getTableData(String table, {int offset = 0, int limit = 50}) async {
    if (_activeDbService == null) return QueryResult(error: 'No database selected');
    _isLoading = true;
    notifyListeners();
    try {
      final result = await _activeDbService!.getTableData(table, offset: offset, limit: limit);
      _lastQueryResult = result;
      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isLoading = false;
      final result = QueryResult(error: 'Error loading table data: $e');
      _lastQueryResult = result;
      notifyListeners();
      return result;
    }
  }

  Future<QueryResult> executeQuery(String sql) async {
    if (_activeDbService == null || _selectedDatabase == null) return QueryResult(error: 'No database selected');
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _activeDbService!.executeQuery(sql);
      _lastQueryResult = result;
      _isLoading = false;
      final entry = QueryHistoryEntry(
        id: const Uuid().v4(),
        databaseId: _selectedDatabase!.id,
        query: sql,
        rowCount: result.rowCount,
        error: result.error,
      );
      await _storage.addQueryHistory(entry);
      notifyListeners();
      return result;
    } catch (e) {
      _isLoading = false;
      final result = QueryResult(error: 'Query error: $e');
      _lastQueryResult = result;
      notifyListeners();
      return result;
    }
  }

  Future<List<QueryHistoryEntry>> getQueryHistory() async {
    if (_selectedDatabase == null) return [];
    return _storage.getQueryHistory(_selectedDatabase!.id);
  }

  Future<String> exportConfig() async => _storage.exportAll();

  Future<void> importConfig(String jsonStr) async {
    await _storage.importAll(jsonStr);
    await _loadData();
  }

  Future<void> clearAllData() async {
    await _storage.clearAll();
    _databases = [];
    _selectedDatabase = null;
    _activeDbService = null;
    notifyListeners();
  }
}
