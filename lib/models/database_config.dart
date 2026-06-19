import 'package:pluradb/models/provider_type.dart';

class DatabaseConfig {
  final String id;
  String name;
  String projectName;
  ProviderType provider;
  // Supabase
  String projectUrl;
  String anonKey;
  String serviceRoleKey;
  // Neon / PlanetScale / Custom
  String host;
  String port;
  String databaseName;
  String user;
  String password;
  String branch;
  String connectionString;
  // Turso
  String databaseUrl;
  String authToken;
  DateTime createdAt;

  DatabaseConfig({
    required this.id,
    required this.name,
    required this.provider,
    this.projectName = '',
    this.projectUrl = '',
    this.anonKey = '',
    this.serviceRoleKey = '',
    this.host = '',
    this.port = '5432',
    this.databaseName = '',
    this.user = '',
    this.password = '',
    this.branch = '',
    this.connectionString = '',
    this.databaseUrl = '',
    this.authToken = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'projectName': projectName,
        'provider': provider.index,
        'projectUrl': projectUrl,
        'anonKey': anonKey,
        'serviceRoleKey': serviceRoleKey,
        'host': host,
        'port': port,
        'databaseName': databaseName,
        'user': user,
        'password': password,
        'branch': branch,
        'connectionString': connectionString,
        'databaseUrl': databaseUrl,
        'authToken': authToken,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DatabaseConfig.fromJson(Map<String, dynamic> json) => DatabaseConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        projectName: json['projectName'] as String? ?? '',
        provider: ProviderType.values[json['provider'] as int],
        projectUrl: json['projectUrl'] as String? ?? '',
        anonKey: json['anonKey'] as String? ?? '',
        serviceRoleKey: json['serviceRoleKey'] as String? ?? '',
        host: json['host'] as String? ?? '',
        port: json['port'] as String? ?? '5432',
        databaseName: json['databaseName'] as String? ?? '',
        user: json['user'] as String? ?? '',
        password: json['password'] as String? ?? '',
        branch: json['branch'] as String? ?? '',
        connectionString: json['connectionString'] as String? ?? '',
        databaseUrl: json['databaseUrl'] as String? ?? '',
        authToken: json['authToken'] as String? ?? '',
        createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
      );
}
