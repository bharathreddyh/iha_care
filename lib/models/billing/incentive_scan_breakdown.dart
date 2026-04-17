class IncentiveScanBreakdown {
  final String scanTypeId;
  final String scanTypeName;
  final int count;
  final double rate;
  final double total; // count × rate

  const IncentiveScanBreakdown({
    required this.scanTypeId,
    required this.scanTypeName,
    required this.count,
    required this.rate,
    required this.total,
  });
}
