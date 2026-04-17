class AppCentre {
  final String id;
  final String name;
  final String code;
  final String role; // 'staff' or 'owner'

  const AppCentre({
    required this.id,
    required this.name,
    required this.code,
    required this.role,
  });
}
