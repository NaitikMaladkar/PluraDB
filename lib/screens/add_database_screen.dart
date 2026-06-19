import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluradb/models/database_config.dart';
import 'package:pluradb/models/provider_type.dart';
import 'package:pluradb/providers/app_provider.dart';
import 'package:pluradb/services/database_service.dart';
import 'package:pluradb/theme/app_theme.dart';

class AddDatabaseScreen extends StatefulWidget {
  final DatabaseConfig? existing;
  const AddDatabaseScreen({super.key, this.existing});

  @override
  State<AddDatabaseScreen> createState() => _AddDatabaseScreenState();
}

class _AddDatabaseScreenState extends State<AddDatabaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _projectNameController = TextEditingController();

  // Supabase
  final _projectUrlController = TextEditingController();
  final _anonKeyController = TextEditingController();
  final _serviceRoleKeyController = TextEditingController();

  // Neon
  final _connectionStringController = TextEditingController();
  final _neonHostController = TextEditingController();
  final _neonDbNameController = TextEditingController();
  final _neonUserController = TextEditingController();
  final _neonPasswordController = TextEditingController();
  final _neonBranchController = TextEditingController();

  // PlanetScale
  final _psHostController = TextEditingController();
  final _psDbNameController = TextEditingController();
  final _psUserController = TextEditingController();
  final _psPasswordController = TextEditingController();

  // Turso
  final _tursoUrlController = TextEditingController();
  final _tursoTokenController = TextEditingController();

  // Custom
  final _customHostController = TextEditingController();
  final _customPortController = TextEditingController(text: '5432');
  final _customDbNameController = TextEditingController();
  final _customUserController = TextEditingController();
  final _customPasswordController = TextEditingController();

  ProviderType _selectedProvider = ProviderType.supabase;
  bool _testing = false;
  bool _testSuccess = false;
  String? _testError;
  late final bool _isEditing;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existing != null;
    if (_isEditing) {
      final db = widget.existing!;
      _selectedProvider = db.provider;
      _nameController.text = db.name;
      _projectNameController.text = db.projectName;
      _projectUrlController.text = db.projectUrl;
      _anonKeyController.text = db.anonKey;
      _serviceRoleKeyController.text = db.serviceRoleKey;
      _connectionStringController.text = db.connectionString;
      _neonHostController.text = db.host;
      _neonDbNameController.text = db.databaseName;
      _neonUserController.text = db.user;
      _neonPasswordController.text = db.password;
      _neonBranchController.text = db.branch;
      _psHostController.text = db.host;
      _psDbNameController.text = db.databaseName;
      _psUserController.text = db.user;
      _psPasswordController.text = db.password;
      _tursoUrlController.text = db.databaseUrl;
      _tursoTokenController.text = db.authToken;
      _customHostController.text = db.host;
      _customPortController.text = db.port;
      _customDbNameController.text = db.databaseName;
      _customUserController.text = db.user;
      _customPasswordController.text = db.password;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _projectNameController.dispose();
    _projectUrlController.dispose();
    _anonKeyController.dispose();
    _serviceRoleKeyController.dispose();
    _connectionStringController.dispose();
    _neonHostController.dispose();
    _neonDbNameController.dispose();
    _neonUserController.dispose();
    _neonPasswordController.dispose();
    _neonBranchController.dispose();
    _psHostController.dispose();
    _psDbNameController.dispose();
    _psUserController.dispose();
    _psPasswordController.dispose();
    _tursoUrlController.dispose();
    _tursoTokenController.dispose();
    _customHostController.dispose();
    _customPortController.dispose();
    _customDbNameController.dispose();
    _customUserController.dispose();
    _customPasswordController.dispose();
    super.dispose();
  }

  DatabaseConfig _buildConfig() {
    final existing = widget.existing;
    return switch (_selectedProvider) {
      ProviderType.supabase => DatabaseConfig(
          id: existing?.id ?? '', name: _nameController.text.trim(), projectName: _projectNameController.text.trim(), provider: ProviderType.supabase,
          projectUrl: _projectUrlController.text.trim(), anonKey: _anonKeyController.text.trim(), serviceRoleKey: _serviceRoleKeyController.text.trim(),
        ),
      ProviderType.neon => DatabaseConfig(
          id: existing?.id ?? '', name: _nameController.text.trim(), projectName: _projectNameController.text.trim(), provider: ProviderType.neon,
          connectionString: _connectionStringController.text.trim(), host: _neonHostController.text.trim(), databaseName: _neonDbNameController.text.trim(),
          user: _neonUserController.text.trim(), password: _neonPasswordController.text.trim(), branch: _neonBranchController.text.trim(),
        ),
      ProviderType.planetscale => DatabaseConfig(
          id: existing?.id ?? '', name: _nameController.text.trim(), projectName: _projectNameController.text.trim(), provider: ProviderType.planetscale,
          host: _psHostController.text.trim(), databaseName: _psDbNameController.text.trim(), user: _psUserController.text.trim(), password: _psPasswordController.text.trim(),
        ),
      ProviderType.turso => DatabaseConfig(
          id: existing?.id ?? '', name: _nameController.text.trim(), projectName: _projectNameController.text.trim(), provider: ProviderType.turso,
          databaseUrl: _tursoUrlController.text.trim(), authToken: _tursoTokenController.text.trim(),
        ),
      ProviderType.custom => DatabaseConfig(
          id: existing?.id ?? '', name: _nameController.text.trim(), projectName: _projectNameController.text.trim(), provider: ProviderType.custom,
          host: _customHostController.text.trim(), port: _customPortController.text.trim(), databaseName: _customDbNameController.text.trim(),
          user: _customUserController.text.trim(), password: _customPasswordController.text.trim(),
        ),
    };
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testSuccess = false; _testError = null; });
    try {
      final config = _buildConfig();
      final service = DatabaseServiceFactory.create(config);
      final ok = await service.testConnection();
      setState(() { _testing = false; _testSuccess = ok; if (!ok) _testError = 'Connection failed. Check your credentials.'; });
    } catch (e) {
      setState(() { _testing = false; _testError = e.toString(); });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<AppProvider>();
    final config = _buildConfig();
    if (_isEditing) {
      provider.updateDatabase(config);
    } else {
      provider.addDatabase(config);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Database' : 'Add Database'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Database name
            _label('DATABASE NAME'),
            const SizedBox(height: 8),
            TextFormField(controller: _nameController, decoration: const InputDecoration(hintText: 'My Production DB', prefixIcon: Icon(Icons.label_outline, color: AppTheme.textMuted)), validator: (v) => v?.trim().isEmpty ?? true ? 'Name is required' : null),
            const SizedBox(height: 12),
            // Project name (optional label)
            TextFormField(controller: _projectNameController, decoration: const InputDecoration(hintText: 'Project name (optional)', prefixIcon: Icon(Icons.folder_outlined, color: AppTheme.textMuted))),
            const SizedBox(height: 24),

            // Provider selector
            _label('PROVIDER'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.border)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ProviderType>(
                  value: _selectedProvider,
                  isExpanded: true,
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Inter', fontSize: 14),
                  items: ProviderType.values.map((p) => DropdownMenuItem(value: p, child: Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(int.parse(p.color.replaceFirst('#', '0xFF'))), shape: BoxShape.circle)), const SizedBox(width: 10), Text(p.displayName)]))).toList(),
                  onChanged: (v) => setState(() { _selectedProvider = v!; _testSuccess = false; _testError = null; }),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Dynamic fields
            ..._buildFields(),
            const SizedBox(height: 24),

            // Status
            if (_testError != null)
              Container(
                padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.error.withValues(alpha: 0.3))),
                child: Row(children: [const Icon(Icons.error_outline, color: AppTheme.error, size: 20), const SizedBox(width: 8), Expanded(child: Text(_testError!, style: const TextStyle(color: AppTheme.error, fontSize: 13, fontFamily: 'Inter')))]),
              ),
            if (_testSuccess)
              Container(
                padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.success.withValues(alpha: 0.3))),
                child: const Row(children: [Icon(Icons.check_circle_outline, color: AppTheme.success, size: 20), SizedBox(width: 8), Text('Connection successful!', style: TextStyle(color: AppTheme.success, fontSize: 13, fontFamily: 'Inter'))]),
              ),

            OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent)) : const Icon(Icons.wifi_tethering),
              label: Text(_testing ? 'Testing...' : 'Test Connection'),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _save, child: Text(_isEditing ? 'Save Changes' : 'Add Database')),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFields() {
    return switch (_selectedProvider) {
      ProviderType.supabase => [
        _label('CONNECTION DETAILS'), const SizedBox(height: 8),
        _field(_projectUrlController, 'Project URL', 'https://xxxxx.supabase.co', Icons.link),
        const SizedBox(height: 12),
        _field(_anonKeyController, 'Anon Key', 'eyJhbGciOi...', Icons.key),
        const SizedBox(height: 12),
        _field(_serviceRoleKeyController, 'Service Role Key (optional)', 'For write operations', Icons.vpn_key, obscure: true),
        const SizedBox(height: 8),
        const Text('Get these from Project Settings > API in your Supabase dashboard', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ],
      ProviderType.neon => [
        _label('CONNECTION DETAILS'), const SizedBox(height: 8),
        _field(_connectionStringController, 'Connection String (optional)', 'postgresql://user:pass@host/db', Icons.link),
        const SizedBox(height: 16),
        const Text('Or fill in manually:', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 12),
        _field(_neonHostController, 'Host', 'ep-xxx.region.aws.neon.tech', Icons.dns),
        const SizedBox(height: 12),
        _field(_neonDbNameController, 'Database Name', 'neondb', Icons.storage),
        const SizedBox(height: 12),
        _field(_neonUserController, 'User', 'neondb_owner', Icons.person),
        const SizedBox(height: 12),
        _field(_neonPasswordController, 'Password', '', Icons.lock, obscure: true),
        const SizedBox(height: 12),
        _field(_neonBranchController, 'Branch (optional)', 'main', Icons.call_split),
      ],
      ProviderType.planetscale => [
        _label('CONNECTION DETAILS'), const SizedBox(height: 8),
        _field(_psHostController, 'Host', 'xxx.psdb.cloud', Icons.dns),
        const SizedBox(height: 12),
        _field(_psDbNameController, 'Database Name', 'my-db', Icons.storage),
        const SizedBox(height: 12),
        _field(_psUserController, 'User', '', Icons.person),
        const SizedBox(height: 12),
        _field(_psPasswordController, 'Password', '', Icons.lock, obscure: true),
      ],
      ProviderType.turso => [
        _label('CONNECTION DETAILS'), const SizedBox(height: 8),
        _field(_tursoUrlController, 'Database URL', 'libsql://my-db-orgname.turso.io', Icons.link),
        const SizedBox(height: 12),
        _field(_tursoTokenController, 'Auth Token', '', Icons.key, obscure: true),
      ],
      ProviderType.custom => [
        _label('CONNECTION DETAILS'), const SizedBox(height: 8),
        _field(_customHostController, 'Host', '192.168.1.100', Icons.dns),
        const SizedBox(height: 12),
        _field(_customPortController, 'Port', '5432', Icons.numbers),
        const SizedBox(height: 12),
        _field(_customDbNameController, 'Database Name', 'mydb', Icons.storage),
        const SizedBox(height: 12),
        _field(_customUserController, 'User', 'postgres', Icons.person),
        const SizedBox(height: 12),
        _field(_customPasswordController, 'Password', '', Icons.lock, obscure: true),
        const SizedBox(height: 8),
        const Text('Custom databases require an HTTP SQL proxy endpoint for mobile access', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ],
    };
  }

  Widget _field(TextEditingController c, String label, String hint, IconData icon, {bool obscure = false}) {
    return TextFormField(controller: c, obscureText: obscure, decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20)));
  }

  Widget _label(String text) {
    return Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted, letterSpacing: 1.2, fontFamily: 'Inter'));
  }
}
