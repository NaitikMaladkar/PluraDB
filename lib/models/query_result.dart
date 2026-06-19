class QueryResult {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final String? error;
  final int? rowCount;
  final int? affectedRows;

  QueryResult({
    this.columns = const [],
    this.rows = const [],
    this.error,
    this.rowCount,
    this.affectedRows,
  });

  bool get isSuccess => error == null;
}
