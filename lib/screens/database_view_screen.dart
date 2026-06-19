import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluradb/models/database_config.dart';
import 'package:pluradb/models/query_result.dart';
import 'package:pluradb/providers/app_provider.dart';
import 'package:pluradb/theme/app_theme.dart';

class DatabaseViewScreen extends StatefulWidget {
  final DatabaseConfig database;
  const DatabaseViewScreen({super.key, required this.database});

  @override
  State<DatabaseViewScreen> createState() => _DatabaseViewScreenState();
}

class _DatabaseViewScreenState extends State<DatabaseViewScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppProvider>().selectDatabase(widget.database));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(int.parse(widget.database.provider.color.replaceFirst('#', '0xFF'))), shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.database.name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            Text(widget.database.provider.displayName, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
        ),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Schema'), Tab(text: 'Data'), Tab(text: 'Query')]),
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.lastQueryResult == null) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
          }
          if (provider.error != null && provider.selectedDatabase?.id == widget.database.id) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off, size: 48, color: AppTheme.textMuted),
                const SizedBox(height: 16),
                Text(provider.error!, style: const TextStyle(color: AppTheme.error, fontSize: 14)),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => provider.selectDatabase(widget.database), child: const Text('Retry')),
              ]),
            );
          }
          return TabBarView(controller: _tabController, children: [
            _SchemaTab(database: widget.database),
            _DataTab(database: widget.database),
            _QueryTab(database: widget.database),
          ]);
        },
      ),
    );
  }
}

// ============ SCHEMA TAB ============
class _SchemaTab extends StatefulWidget {
  final DatabaseConfig database;
  const _SchemaTab({required this.database});

  @override
  State<_SchemaTab> createState() => _SchemaTabState();
}

class _SchemaTabState extends State<_SchemaTab> {
  QueryResult? _schema;
  bool _loading = false;
  Map<String, List<Map<String, String>>> _groupedTables = {};

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  Future<void> _loadSchema() async {
    setState(() => _loading = true);
    final provider = context.read<AppProvider>();
    final result = await provider.getSchema();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _schema = result;
      if (result.isSuccess) _groupTables(result);
    });
  }

  void _groupTables(QueryResult result) {
    _groupedTables = {};
    if (result.rows.isEmpty) return;
    if (result.columns.contains('table_name') && result.columns.contains('column_name')) {
      for (final row in result.rows) {
        final t = (row['table_name'] ?? '').toString();
        if (t.isEmpty) continue;
        _groupedTables.putIfAbsent(t, () => []);
        _groupedTables[t]!.add({
          'column': (row['column_name'] ?? '').toString(),
          'type': (row['data_type'] ?? '').toString(),
          'nullable': (row['is_nullable'] ?? '').toString(),
          'default': (row['column_default'] ?? '').toString(),
        });
      }
    } else if (result.columns.contains('Table')) {
      for (final row in result.rows) {
        final t = (row['Table'] ?? '').toString();
        final c = (row['Columns'] ?? '').toString();
        if (t.isEmpty) continue;
        _groupedTables[t] = c.split(', ').map((v) => {'column': v, 'type': '', 'nullable': '', 'default': ''}).toList();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    if (_schema?.error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
        const SizedBox(height: 16),
        Text(_schema!.error!, style: const TextStyle(color: AppTheme.error, fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _loadSchema, child: const Text('Retry')),
      ]));
    }
    if (_groupedTables.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.table_chart_outlined, size: 56, color: AppTheme.textMuted),
        SizedBox(height: 16),
        Text('No tables found', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
      ]));
    }
    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: _loadSchema,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _groupedTables.length,
        itemBuilder: (context, index) {
          final tableName = _groupedTables.keys.elementAt(index);
          final columns = _groupedTables[tableName]!;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.table_chart, color: AppTheme.accent, size: 18),
              ),
              title: Text(tableName, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter', fontSize: 14)),
              subtitle: Text('${columns.length} column${columns.length != 1 ? 's' : ''}', style: const TextStyle(fontSize: 12)),
              children: [
                const Divider(height: 1),
                if (columns.any((c) => (c['type']?.isNotEmpty ?? false)))
                  _DetailedColumns(columns)
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 6, runSpacing: 6,
                      children: columns.map((c) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.border)),
                        child: Text(c['column'] ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontFamily: 'JetBrainsMono')),
                      )).toList(),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            )),
          );
        },
      ),
    );
  }
}

class _DetailedColumns extends StatelessWidget {
  final List<Map<String, String>> columns;
  const _DetailedColumns(this.columns);

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.5), 2: FlexColumnWidth(0.8), 3: FlexColumnWidth(1.2)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(decoration: BoxDecoration(color: AppTheme.surfaceLight), children: [
          _header('Column'), _header('Type'), _header('Null'), _header('Default'),
        ]),
        ...columns.map((col) => TableRow(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.3))),
          children: [
            _cell(col['column'] ?? '', bold: true),
            _cell(col['type'] ?? ''),
            _cell(col['nullable'] ?? ''),
            _cell(col['default'] ?? ''),
          ],
        )),
      ],
    );
  }

  Widget _header(String t) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted, fontFamily: 'Inter')));
  Widget _cell(String t, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text(t.isEmpty ? '-' : t, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: bold ? AppTheme.textPrimary : AppTheme.textSecondary, fontFamily: 'JetBrainsMono', fontWeight: bold ? FontWeight.w500 : FontWeight.normal)));
}

// ============ DATA TAB ============
class _DataTab extends StatefulWidget {
  final DatabaseConfig database;
  const _DataTab({required this.database});

  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  String? _selectedTable;
  int _offset = 0;
  final int _limit = 50;
  QueryResult? _result;
  bool _loading = false;
  List<String> _tables = [];

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    final provider = context.read<AppProvider>();
    final schema = await provider.getSchema();
    if (!mounted) return;
    final names = <String>{};
    if (schema.isSuccess && schema.rows.isNotEmpty) {
      if (schema.columns.contains('table_name')) {
        for (final row in schema.rows) names.add(row['table_name'].toString());
      } else if (schema.columns.contains('Table')) {
        for (final row in schema.rows) names.add(row['Table'].toString());
      }
    }
    if (names.isNotEmpty && mounted) {
      setState(() { _tables = names.toList()..sort(); _selectedTable = _tables.first; });
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (_selectedTable == null) return;
    setState(() => _loading = true);
    final provider = context.read<AppProvider>();
    final result = await provider.getTableData(_selectedTable!, offset: _offset, limit: _limit);
    if (mounted) setState(() { _loading = false; _result = result; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(
            children: [
              const Icon(Icons.table_chart_outlined, size: 18, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTable,
                  isExpanded: true,
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Inter', fontSize: 14),
                  hint: const Text('Select a table', style: TextStyle(color: AppTheme.textMuted)),
                  items: _tables.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) { setState(() { _selectedTable = v; _offset = 0; }); _loadData(); },
                ),
              )),
              if (_result?.rowCount != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(12)),
                  child: Text('${_result!.rowCount} rows', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontFamily: 'Inter')),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
              : _result == null ? const Center(child: Text('Select a table to view data', style: TextStyle(color: AppTheme.textMuted)))
              : _result!.error != null ? Center(child: Text(_result!.error!, style: const TextStyle(color: AppTheme.error)))
              : _result!.rows.isEmpty ? const Center(child: Text('No data in this table', style: TextStyle(color: AppTheme.textMuted)))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(AppTheme.surfaceLight),
                      dataRowColor: WidgetStateProperty.all(AppTheme.surface),
                      dividerThickness: 0.5,
                      horizontalMargin: 12,
                      columnSpacing: 16,
                      headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: AppTheme.textMuted, fontFamily: 'JetBrainsMono'),
                      dataTextStyle: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontFamily: 'JetBrainsMono'),
                      columns: _result!.columns.map((c) => DataColumn(label: SizedBox(width: 120, child: Text(c, overflow: TextOverflow.ellipsis)))).toList(),
                      rows: _result!.rows.map((row) => DataRow(
                        cells: _result!.columns.map((c) => DataCell(SizedBox(width: 120, child: Text((row[c] ?? '').toString(), overflow: TextOverflow.ellipsis, maxLines: 2)))).toList(),
                      )).toList(),
                    ),
                  ),
                ),
        ),
        if (_result != null && _result!.isSuccess && _result!.rows.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Showing ${_offset + 1}-${_offset + _result!.rows.length} of ${_result!.rowCount ?? _result!.rows.length}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontFamily: 'Inter')),
                Row(children: [
                  IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: _offset > 0 ? () { setState(() => _offset -= _limit); _loadData(); } : null, style: IconButton.styleFrom(minimumSize: Size(32, 32), padding: EdgeInsets.zero)),
                  IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: _result!.rows.length >= _limit ? () { setState(() => _offset += _limit); _loadData(); } : null, style: IconButton.styleFrom(minimumSize: Size(32, 32), padding: EdgeInsets.zero)),
                ]),
              ],
            ),
          ),
      ],
    );
  }
}

// ============ QUERY TAB ============
class _QueryTab extends StatefulWidget {
  final DatabaseConfig database;
  const _QueryTab({required this.database});

  @override
  State<_QueryTab> createState() => _QueryTabState();
}

class _QueryTabState extends State<_QueryTab> {
  final _controller = TextEditingController();
  bool _showHistory = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _executeQuery() {
    final sql = _controller.text.trim();
    if (sql.isEmpty) return;
    context.read<AppProvider>().executeQuery(sql);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final result = provider.lastQueryResult;

        return Column(
          children: [
            // Editor area
            Container(
              decoration: const BoxDecoration(color: AppTheme.surfaceLight, border: Border(bottom: BorderSide(color: AppTheme.border))),
              child: Column(
                children: [
                  // Toolbar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5))),
                    child: Row(
                      children: [
                        const Icon(Icons.code, size: 16, color: AppTheme.accent),
                        const SizedBox(width: 6),
                        const Text('SQL', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'JetBrainsMono')),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            final history = await provider.getQueryHistory();
                            setState(() => _showHistory = !_showHistory);
                          },
                          icon: const Icon(Icons.history, size: 14),
                          label: const Text('History', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: provider.isLoading ? null : _executeQuery,
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), textStyle: const TextStyle(fontSize: 13)),
                          child: provider.isLoading
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background))
                              : const Text('Run'),
                        ),
                      ],
                    ),
                  ),
                  // History
                  if (_showHistory) _HistoryList(database: widget.database),
                  // Editor
                  Container(
                    constraints: const BoxConstraints(minHeight: 120, maxHeight: 200),
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14, color: AppTheme.textPrimary, height: 1.5),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'SELECT * FROM users WHERE id = 1;',
                        hintStyle: TextStyle(color: AppTheme.textMuted, fontFamily: 'JetBrainsMono', fontSize: 14),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Results
            Expanded(
              child: result == null
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.terminal, size: 48, color: AppTheme.textMuted),
                      SizedBox(height: 12),
                      Text('Write a query and hit Run', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                    ]))
                  : result.error != null
                      ? Center(child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.error_outline, size: 40, color: AppTheme.error),
                            const SizedBox(height: 12),
                            Text(result.error!, style: const TextStyle(color: AppTheme.error, fontSize: 13, fontFamily: 'JetBrainsMono'), textAlign: TextAlign.center),
                          ]),
                        ))
                      : result.rows.isEmpty
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.check_circle_outline, size: 40, color: AppTheme.accent),
                              const SizedBox(height: 8),
                              Text(result.affectedRows != null ? 'Query executed. ${result.affectedRows} row(s) affected.' : 'Query executed. No results returned.', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                            ]))
                          : Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  color: AppTheme.surfaceLight,
                                  child: Row(children: [
                                    const Icon(Icons.table_rows, size: 14, color: AppTheme.accent),
                                    const SizedBox(width: 6),
                                    Text('${result.rows.length} row${result.rows.length != 1 ? "s" : ""} \u2022 ${result.columns.length} column${result.columns.length != 1 ? "s" : ""}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontFamily: 'Inter')),
                                  ]),
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SingleChildScrollView(
                                      child: DataTable(
                                        headingRowColor: WidgetStateProperty.all(AppTheme.surfaceLight),
                                        dataRowColor: WidgetStateProperty.all(AppTheme.surface),
                                        dividerThickness: 0.5,
                                        horizontalMargin: 12,
                                        columnSpacing: 16,
                                        headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: AppTheme.textMuted, fontFamily: 'JetBrainsMono'),
                                        dataTextStyle: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontFamily: 'JetBrainsMono'),
                                        columns: result.columns.map((c) => DataColumn(label: SizedBox(width: 120, child: Text(c, overflow: TextOverflow.ellipsis)))).toList(),
                                        rows: result.rows.map((row) => DataRow(
                                          cells: result.columns.map((c) => DataCell(SizedBox(width: 120, child: Text((row[c] ?? '').toString(), overflow: TextOverflow.ellipsis, maxLines: 2)))).toList(),
                                        )).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  final DatabaseConfig database;
  const _HistoryList({required this.database});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: context.read<AppProvider>().getQueryHistory(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(padding: EdgeInsets.all(12), child: Text('No query history', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)));
        }
        final history = snapshot.data!;
        return Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index];
              return InkWell(
                onTap: () {
                  final controller = TextEditingController(text: entry.query);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Query loaded into editor', style: const TextStyle(fontFamily: 'Inter')),
                      action: SnackBarAction(label: 'OK', onPressed: () {}),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.query,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontFamily: 'JetBrainsMono', color: entry.error != null ? AppTheme.error : AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text('${entry.executedAt.toString().substring(0, 19)}${entry.rowCount != null ? " \u2022 ${entry.rowCount} rows" : ""}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
