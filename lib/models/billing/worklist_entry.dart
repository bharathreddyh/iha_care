class WorklistEntry {
  final String billId;
  final String accessionNumber;
  final String patientName;
  final String? patientId;
  final String scanTypeName;
  final DateTime createdAt;
  final bool scanCompleted;
  final bool worklistPushed;

  const WorklistEntry({
    required this.billId,
    required this.accessionNumber,
    required this.patientName,
    this.patientId,
    required this.scanTypeName,
    required this.createdAt,
    required this.scanCompleted,
    required this.worklistPushed,
  });

  String get status {
    if (scanCompleted) return 'Completed';
    if (worklistPushed) return 'In Progress';
    return 'Pending';
  }
}
