import 'package:intl/intl.dart';

final _displayFmt = DateFormat('dd MMM yyyy, hh:mm a');
final _displayDateFmt = DateFormat('dd MMM yyyy');
final _monthYearFmt = DateFormat('MMMM yyyy');
final _monthKeyFmt = DateFormat('yyyy-MM');

String formatDateTime(String isoString) {
  try {
    return _displayFmt.format(DateTime.parse(isoString).toLocal());
  } catch (_) {
    return isoString;
  }
}

String formatDate(String isoString) {
  try {
    return _displayDateFmt.format(DateTime.parse(isoString).toLocal());
  } catch (_) {
    return isoString;
  }
}

String formatMonthYear(String yyyyMm) {
  try {
    return _monthYearFmt.format(DateFormat('yyyy-MM').parse(yyyyMm));
  } catch (_) {
    return yyyyMm;
  }
}

String currentMonthKey() => _monthKeyFmt.format(DateTime.now());
