enum ProviderType {
  supabase('Supabase', '#3ECF8E'),
  neon('Neon', '#7C3AED'),
  planetscale('PlanetScale', '#0EA5E9'),
  turso('Turso', '#F97316'),
  cockroachdb('CockroachDB', '#6933FF'),
  custom('Custom', '#6B7280');

  final String displayName;
  final String color;
  const ProviderType(this.displayName, this.color);
}
