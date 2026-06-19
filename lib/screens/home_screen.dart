import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluradb/models/database_config.dart';
import 'package:pluradb/providers/app_provider.dart';
import 'package:pluradb/screens/add_database_screen.dart';
import 'package:pluradb/screens/database_view_screen.dart';
import 'package:pluradb/screens/settings_screen.dart';
import 'package:pluradb/theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.storage_rounded, color: AppTheme.accent, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('PluraDB'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final dbs = provider.databases;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your Databases', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontFamily: 'Inter')),
                    const SizedBox(height: 4),
                    Text('${dbs.length} database${dbs.length != 1 ? 's' : ''} saved', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, fontFamily: 'Inter')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: dbs.isEmpty
                    ? _emptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: dbs.length + 1,
                        itemBuilder: (context, index) {
                          if (index == dbs.length) return const SizedBox(height: 80);
                          final db = dbs[index];
                          return _DatabaseCard(
                            database: db,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DatabaseViewScreen(database: db))),
                            onDelete: () => _confirmDelete(context, provider, db),
                            onEdit: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddDatabaseScreen(existing: db))),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDatabaseScreen())),
        backgroundColor: AppTheme.accent,
        foregroundColor: AppTheme.background,
        icon: const Icon(Icons.add),
        label: const Text('Add Database', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 56, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            const Text('No databases added', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary, fontFamily: 'Inter')),
            const SizedBox(height: 8),
            const Text('Tap + to add your first database', style: TextStyle(fontSize: 13, color: AppTheme.textMuted, fontFamily: 'Inter')),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppProvider provider, DatabaseConfig db) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Database'),
        content: Text('Remove "${db.name}" from PluraDB?\n\nThis only removes the saved connection, not the actual database.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () { provider.deleteDatabase(db.id); Navigator.pop(ctx); },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _DatabaseCard extends StatelessWidget {
  final DatabaseConfig database;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _DatabaseCard({required this.database, required this.onTap, required this.onDelete, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final providerColor = Color(int.parse(database.provider.color.replaceFirst('#', '0xFF')));
    final initial = database.provider.displayName[0];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: providerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: providerColor.withValues(alpha: 0.25), width: 0.5),
                  ),
                  child: Center(
                    child: Text(initial, style: TextStyle(color: providerColor, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Inter')),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(database.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontFamily: 'Inter'), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: providerColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(database.provider.displayName, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontFamily: 'Inter')),
                          if (database.projectName.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(database.projectName, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontFamily: 'Inter'), overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 20),
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppTheme.border)),
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                    if (value == 'edit') onEdit();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Edit')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: AppTheme.error, size: 18), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppTheme.error))])),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
