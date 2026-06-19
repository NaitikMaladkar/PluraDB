import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pluradb/providers/app_provider.dart';
import 'package:pluradb/theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('DATA MANAGEMENT', [
            _tile(Icons.upload_file_outlined, 'Export Configuration', 'Share your saved databases as JSON', () => _export(context)),
            _tile(Icons.file_download_outlined, 'Import Configuration', 'Paste JSON to restore databases', () => _import(context)),
          ]),
          const SizedBox(height: 24),
          _section('DANGER ZONE', [
            _tile(Icons.delete_forever_outlined, 'Clear All Data', 'Remove all databases and history', () => _clearAll(context), color: AppTheme.error),
          ]),
          const SizedBox(height: 24),
          _section('ABOUT', [
            ListTile(leading: const Icon(Icons.info_outline, color: AppTheme.textMuted, size: 20), title: const Text('PluraDB', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)), subtitle: const Text('Multi-database manager for Android'), trailing: const Text('v1.1.0', style: TextStyle(color: AppTheme.textMuted, fontSize: 13))),
            const ListTile(leading: Icon(Icons.shield_outlined, color: AppTheme.textMuted, size: 20), title: Text('Privacy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)), subtitle: Text('All data stored locally on your device.')),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted, letterSpacing: 1.2, fontFamily: 'Inter')),
        const SizedBox(height: 8),
        Card(child: Column(children: tiles)),
      ],
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppTheme.textMuted, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: AppTheme.textMuted),
      onTap: onTap,
    );
  }

  Future<void> _export(BuildContext context) async {
    try {
      final provider = context.read<AppProvider>();
      final jsonStr = await provider.exportConfig();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pluradb-config.json');
      await file.writeAsString(jsonStr);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')], subject: 'PluraDB Configuration');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _import(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Paste your PluraDB JSON config below:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
              decoration: const InputDecoration(hintText: '{"version":1,"databases":[...]}', alignLabelWithHint: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Import')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      jsonDecode(result);
      if (!context.mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Import'),
          content: const Text('This will replace all current data. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
          ],
        ),
      );
      if (confirm == true && context.mounted) {
        await context.read<AppProvider>().importConfig(result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuration imported successfully')));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid JSON: $e')));
    }
  }

  void _clearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text('Permanently delete all databases and history. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () { context.read<AppProvider>().clearAllData(); Navigator.pop(ctx); Navigator.pop(context); },
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );
  }
}
