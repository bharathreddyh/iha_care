import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/billing/bill.dart';
import '../models/billing/referral_doctor.dart';
import '../models/billing/scan_type.dart';
import 'currency_formatter.dart';
import 'date_formatter.dart';

// ── Font loader (Noto Sans — full Unicode including ₹) ────────────────────────

Future<_Fonts> _loadFonts() async {
  final regular = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();
  final italic = await PdfGoogleFonts.notoSansItalic();
  return _Fonts(regular: regular, bold: bold, italic: italic);
}

class _Fonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  const _Fonts({required this.regular, required this.bold, required this.italic});

  pw.TextStyle style({
    double fontSize = 10,
    bool isBold = false,
    bool isItalic = false,
    PdfColor? color,
  }) =>
      pw.TextStyle(
        font: isBold ? bold : (isItalic ? italic : regular),
        fontSize: fontSize,
        color: color,
      );
}

// ── Receipt ───────────────────────────────────────────────────────────────────

Future<Uint8List> generateReceipt(
  Bill bill,
  ScanType? scanType,
  ReferralDoctor? referralDoctor, {
  String header1 = 'Sahyadri Scan and Diagnostics',
  String header2 = 'Scan and Diagnostics Centre',
  String footer  = 'Thank you for visiting Sahyadri Scan and Diagnostics',
}) async {
  final f = await _loadFonts();
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(header1, style: f.style(fontSize: 20, isBold: true)),
                if (header2.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(header2, style: f.style(fontSize: 11)),
                ],
              ],
            ),
          ),
          pw.Divider(thickness: 1.5),
          pw.SizedBox(height: 8),

          _row('Bill No', bill.id, f),
          _row('Date', formatDateTime(bill.createdAt), f),
          pw.SizedBox(height: 6),
          pw.Divider(),
          pw.SizedBox(height: 6),

          _row('Patient Name', bill.patientName, f),
          if (bill.patientId != null && bill.patientId!.isNotEmpty)
            _row('Patient ID', bill.patientId!, f),
          if (bill.patientPhone != null && bill.patientPhone!.isNotEmpty)
            _row('Phone', bill.patientPhone!, f),
          pw.SizedBox(height: 6),
          pw.Divider(),
          pw.SizedBox(height: 6),

          _row('Scan Type', scanType?.name ?? 'N/A', f),
          _row('Scan Fee', formatCurrency(bill.scanFee), f),
          if (bill.discount > 0)
            _row('Discount', '- ${formatCurrency(bill.discount)}', f),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Amount', style: f.style(fontSize: 13, isBold: true)),
              pw.Text(formatCurrency(bill.finalAmount),
                  style: f.style(fontSize: 13, isBold: true)),
            ],
          ),
          pw.SizedBox(height: 4),
          _row('Payment Mode', bill.paymentMode, f),
          if (referralDoctor != null)
            _row('Referred By', 'Dr. ${referralDoctor.name}', f),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 8),

          pw.Center(
            child: pw.Text(footer, style: f.style(fontSize: 10)),
          ),
        ],
      ),
    ),
  );

  return pdf.save();
}

// ── Incentive report ──────────────────────────────────────────────────────────

Future<Uint8List> generateIncentiveReport({
  required String month,
  required List<Map<String, dynamic>> rows,
  required Map<String, ReferralDoctor> doctors,
}) async {
  final f = await _loadFonts();
  final pdf = pw.Document();

  // Group rows by doctor
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final id = r['referral_doctor_id'] as String;
    grouped.putIfAbsent(id, () => []).add(r);
  }
  final sortedDoctorIds = grouped.keys.toList()
    ..sort((a, b) {
      final na = doctors[a]?.name ?? a;
      final nb = doctors[b]?.name ?? b;
      return na.compareTo(nb);
    });

  final docSections = <pw.Widget>[];
  for (final doctorId in sortedDoctorIds) {
    final doctorRows = grouped[doctorId]!;
    final doctor = doctors[doctorId];
    final doctorName =
        doctor != null ? 'Dr. ${doctor.name}' : doctorId;

    double doctorTotal = 0;
    final dataRows = <pw.TableRow>[];
    for (final r in doctorRows) {
      final incentive = (r['incentive_rate'] as num).toDouble();
      doctorTotal += incentive;
      dataRows.add(_tableRow([
        r['patient_name'] as String,
        formatDate(r['created_at'] as String),
        r['scan_type_name'] as String,
        formatCurrency(incentive),
      ], f));
    }

    docSections.add(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              doctorName,
              style: f.style(fontSize: 13, isBold: true),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FlexColumnWidth(2),
            },
            children: [
              _tableHeader(
                  ['Patient Name', 'Date', 'Scan Type', 'Incentive (₹)'], f),
              ...dataRows,
              _tableRow(
                [
                  'Total — ${doctorRows.length} referral${doctorRows.length == 1 ? '' : 's'}',
                  '',
                  '',
                  formatCurrency(doctorTotal),
                ],
                f,
                bold: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Sahyadri Scan and Diagnostics — Referral Incentive Report',
                  style: f.style(fontSize: 16, isBold: true),
                ),
                pw.Text(formatMonthYear(month), style: f.style(fontSize: 12)),
                pw.SizedBox(height: 8),
              ],
            )
          : pw.SizedBox(),
      build: (ctx) => docSections.isEmpty
          ? [
              pw.Center(
                child: pw.Text('No referral data for this month.',
                    style: f.style(fontSize: 11)),
              )
            ]
          : docSections,
    ),
  );

  return pdf.save();
}

// ── Monthly report ────────────────────────────────────────────────────────────

Future<Uint8List> generateMonthlyReport({
  required String month,
  required Map<String, dynamic> data,
  required bool includeExcluded,
  required bool includeCancelled,
}) async {
  final f = await _loadFonts();
  final pdf = pw.Document();

  final scanVolume = (data['scanVolume'] as List).cast<Map<String, dynamic>>();
  final paymentSplit =
      (data['paymentSplit'] as List).cast<Map<String, dynamic>>();
  final totalCount = data['totalCount'] as int? ?? 0;
  final totalRevenue = (data['totalRevenue'] as num? ?? 0).toDouble();
  final totalDiscount = (data['totalDiscount'] as num? ?? 0).toDouble();
  final excludedCount = data['excludedCount'] as int? ?? 0;
  final excludedRevenue = (data['excludedRevenue'] as num? ?? 0).toDouble();
  final cancelledCount = data['cancelledCount'] as int? ?? 0;
  final pcpdntCount = data['pcpdntCount'] as int? ?? 0;

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Text('Sahyadri Scan and Diagnostics — Monthly Report',
            style: f.style(fontSize: 16, isBold: true)),
        pw.Text(formatMonthYear(month), style: f.style(fontSize: 12)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated ${formatDateTime(DateTime.now().toIso8601String())}',
          style: f.style(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Filters: '
          '${includeExcluded ? "incl. excluded" : "excl. excluded"}, '
          '${includeCancelled ? "incl. cancelled" : "excl. cancelled"}',
          style: f.style(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 16),

        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _row('Total Bills', totalCount.toString(), f),
              _row('Gross Revenue', formatCurrency(totalRevenue), f),
              _row('Total Discount', formatCurrency(totalDiscount), f),
              _row('PCPNDT Form-F Count', pcpdntCount.toString(), f),
              if (excludedCount > 0)
                _row('Excluded from this report',
                    '$excludedCount bills · ${formatCurrency(excludedRevenue)}', f),
              if (cancelledCount > 0)
                _row('Cancelled this month', '$cancelledCount bills', f),
            ],
          ),
        ),
        pw.SizedBox(height: 16),

        pw.Text('Scan Volume', style: f.style(fontSize: 13, isBold: true)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            _tableHeader(['Scan Type', 'Count', 'Revenue'], f),
            if (scanVolume.isEmpty) _tableRow(['No data', '', ''], f),
            ...scanVolume.map((r) => _tableRow([
                  (r['name'] as String?) ?? 'Unknown',
                  ((r['cnt'] as int?) ?? 0).toString(),
                  formatCurrency((r['revenue'] as num? ?? 0).toDouble()),
                ], f)),
          ],
        ),
        pw.SizedBox(height: 16),

        pw.Text('Payment Mode Split', style: f.style(fontSize: 13, isBold: true)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            _tableHeader(['Mode', 'Count', 'Total'], f),
            if (paymentSplit.isEmpty) _tableRow(['No data', '', ''], f),
            ...paymentSplit.map((r) => _tableRow([
                  (r['payment_mode'] as String?) ?? '-',
                  ((r['cnt'] as int?) ?? 0).toString(),
                  formatCurrency((r['total'] as num? ?? 0).toDouble()),
                ], f)),
            _tableRow(
              ['TOTAL', totalCount.toString(), formatCurrency(totalRevenue)],
              f,
              bold: true,
            ),
          ],
        ),
      ],
    ),
  );

  return pdf.save();
}

// ── Shared helpers ────────────────────────────────────────────────────────────

pw.Widget _row(String label, String value, _Fonts f) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: f.style(fontSize: 10)),
          pw.Text(value, style: f.style(fontSize: 10)),
        ],
      ),
    );

pw.TableRow _tableHeader(List<String> cells, _Fonts f) => pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: cells
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(c, style: f.style(fontSize: 9, isBold: true)),
              ))
          .toList(),
    );

pw.TableRow _tableRow(List<String> cells, _Fonts f,
        {bool bold = false, bool isBreakdown = false}) =>
    pw.TableRow(
      decoration: isBreakdown
          ? const pw.BoxDecoration(color: PdfColors.grey100)
          : null,
      children: cells
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  c,
                  style: f.style(
                    fontSize: isBreakdown ? 8 : 9,
                    isBold: bold,
                    color: isBreakdown ? PdfColors.grey700 : PdfColors.black,
                  ),
                ),
              ))
          .toList(),
    );
