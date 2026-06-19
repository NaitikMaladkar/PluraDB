import 'package:flutter/material.dart';
import 'package:pluradb/screens/add_database_screen.dart';
import 'package:pluradb/theme/app_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.storage_rounded, color: AppTheme.accent, size: 36),
              ),
              const SizedBox(height: 24),
              const Text('PluraDB', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontFamily: 'Inter', letterSpacing: -0.5)),
              const SizedBox(height: 12),
              const Text(
                'Your multi-database manager.\nAdd databases from Supabase, Neon,\nPlanetScale, Turso, CockroachDB\nand more — in one place.',
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary, height: 1.6, fontFamily: 'Inter'),
              ),
              const Spacer(flex: 1),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(Icons.code, 'SQL Editor'),
                  _chip(Icons.table_chart_outlined, 'Schema Browser'),
                  _chip(Icons.cloud_download, 'Export/Import'),
                  _chip(Icons.shield_outlined, 'Local Storage'),
                ],
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDatabaseScreen())),
                  child: const Text('Add Your First Database'),
                ),
              ),
              const SizedBox(height: 16),
              Center(child: Text('All data stored locally on your device', style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Inter')),
        ],
      ),
    );
  }
}
