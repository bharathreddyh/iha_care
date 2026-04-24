import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/billing/referral_doctor.dart';
import 'date_formatter.dart';

/// Generates a referral summary .xlsx for [month] (YYYY-MM).
/// Returns the saved file path.
Future<String> exportReferralSummaryExcel({
  required String month,
  required List<Map<String, dynamic>> rows,     // from getReferralDetailForMonth
  required Map<String, ReferralDoctor> doctors,  // doctorId → ReferralDoctor
}) async {
  final excel = Excel.createExcel();
  // Remove the default empty sheet
  excel.delete('Sheet1');

  final sheetName = formatMonthYear(month); // e.g. "April 2026"
  final sheet = excel[sheetName];

  // ── Styles ────────────────────────────────────────────────────────────────

  CellStyle _doctorStyle() => CellStyle(
        bold: true,
        fontSize: 13,
        horizontalAlign: HorizontalAlign.Center,
        backgroundColorHex: ExcelColor.fromHexString('#DCE6F1'),
      );

  CellStyle _headerStyle() => CellStyle(
        bold: true,
        fontSize: 10,
        backgroundColorHex: ExcelColor.fromHexString('#4472C4'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );

  CellStyle _dataStyle({bool isTotal = false}) => CellStyle(
        bold: isTotal,
        fontSize: 10,
        backgroundColorHex: isTotal
            ? ExcelColor.fromHexString('#F2F2F2')
            : ExcelColor.fromHexString('#FFFFFF'),
      );

  CellStyle _amountStyle({bool isTotal = false}) => CellStyle(
        bold: isTotal,
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Right,
        backgroundColorHex: isTotal
            ? ExcelColor.fromHexString('#F2F2F2')
            : ExcelColor.fromHexString('#FFFFFF'),
      );

  // ── Set column widths ─────────────────────────────────────────────────────
  sheet.setColumnWidth(0, 30); // Patient Name
  sheet.setColumnWidth(1, 18); // Date
  sheet.setColumnWidth(2, 28); // Scan Type
  sheet.setColumnWidth(3, 16); // Incentive

  int rowIdx = 0;

  // ── Group rows by doctor ──────────────────────────────────────────────────
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final id = r['referral_doctor_id'] as String;
    grouped.putIfAbsent(id, () => []).add(r);
  }

  // Sort doctors by name
  final sortedDoctorIds = grouped.keys.toList()
    ..sort((a, b) {
      final nameA = doctors[a]?.name ?? a;
      final nameB = doctors[b]?.name ?? b;
      return nameA.compareTo(nameB);
    });

  for (final doctorId in sortedDoctorIds) {
    final doctorRows = grouped[doctorId]!;
    final doctor = doctors[doctorId];
    final doctorName = doctor != null ? 'Dr. ${doctor.name}' : doctorId;
    final clinic = doctor?.clinicName ?? '';

    // ── Doctor name row (merged across 4 columns) ─────────────────────────
    final nameCell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: 0, rowIndex: rowIdx));
    nameCell.value = TextCellValue(
        clinic.isNotEmpty ? '$doctorName — $clinic' : doctorName);
    nameCell.cellStyle = _doctorStyle();
    // Merge A..D for the doctor name
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx),
    );
    rowIdx++;

    // ── Column header row ─────────────────────────────────────────────────
    final headers = ['Patient Name', 'Date', 'Scan Type', 'Incentive (₹)'];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = _headerStyle();
    }
    rowIdx++;

    // ── Data rows ─────────────────────────────────────────────────────────
    double doctorTotal = 0;
    for (final r in doctorRows) {
      final incentive = (r['incentive_rate'] as num).toDouble();
      doctorTotal += incentive;

      final patientCell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx));
      patientCell.value = TextCellValue(r['patient_name'] as String);
      patientCell.cellStyle = _dataStyle();

      final dateCell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx));
      dateCell.value =
          TextCellValue(_formatDate(r['created_at'] as String));
      dateCell.cellStyle = _dataStyle();

      final scanCell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx));
      scanCell.value = TextCellValue(r['scan_type_name'] as String);
      scanCell.cellStyle = _dataStyle();

      final incentiveCell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx));
      incentiveCell.value = DoubleCellValue(incentive);
      incentiveCell.cellStyle = _amountStyle();
      rowIdx++;
    }

    // ── Total row ─────────────────────────────────────────────────────────
    final totalLabelCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx));
    totalLabelCell.value =
        TextCellValue('Total — ${doctorRows.length} referrals');
    totalLabelCell.cellStyle = _dataStyle(isTotal: true);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
      CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx),
    );

    final totalAmtCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx));
    totalAmtCell.value = DoubleCellValue(doctorTotal);
    totalAmtCell.cellStyle = _amountStyle(isTotal: true);
    rowIdx++;

    // ── Blank separator row ────────────────────────────────────────────────
    rowIdx++;
  }

  // ── Save file ─────────────────────────────────────────────────────────────
  final dir = await getApplicationDocumentsDirectory();
  final safeMonth = month.replaceAll('-', '_');
  final filePath = '${dir.path}/referral_summary_$safeMonth.xlsx';
  final fileBytes = excel.encode();
  if (fileBytes == null) throw Exception('Failed to encode Excel file');
  File(filePath).writeAsBytesSync(fileBytes);
  return filePath;
}

String _formatDate(String isoString) {
  try {
    final dt = DateTime.parse(isoString);
    return DateFormat('dd MMM yyyy').format(dt);
  } catch (_) {
    return isoString;
  }
}
