class QueryHistoryEntry {
  final String id;
  final String databaseId;
  String query;
  DateTime executedAt;
  int? rowCount;
  String? error;

  QueryHistoryEntry({
    required this.id,
    required this.databaseId,
    required this.query,
    DateTime? executedAt,
    this.rowCount,
    this.error,
  }) : executedAt = executedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'databaseId': databaseId,
        'query': query,
        'executedAt': executedAt.toIso8601String(),
        'rowCount': rowCount,
        'error': error,
      };

  factory QueryHistoryEntry.fromJson(Map<String, dynamic> json) => QueryHistoryEntry(
        id: json['id'] as String,
        databaseId: json['databaseId'] as String,
        query: json['query'] as String,
        executedAt: DateTime.parse(json['executedAt'] as String),
        rowCount: json['rowCount'] as int?,
        error: json['error'] as String?,
      );
}
