import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/billing/bill.dart';
import '../models/billing/incentive_record.dart';
import '../models/billing/referral_doctor.dart';
import '../models/billing/scan_type.dart';
import 'currency_formatter.dart';
import 'date_formatter.dart';

Future<Uint8List> generateReceipt(
  Bill bill,
  ScanType? scanType,
  ReferralDoctor? referralDoctor,
) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'IHA Care USG Centre',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Diagnostic Ultrasound Services',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          pw.Divider(thickness: 1.5),
          pw.SizedBox(height: 8),

          // Bill details
          _row('Bill No', bill.id),
          _row('Date', formatDateTime(bill.createdAt)),
          pw.SizedBox(height: 6),
          pw.Divider(),
          pw.SizedBox(height: 6),

          // Patient
          _row('Patient Name', bill.patientName),
          if (bill.patientId != null && bill.patientId!.isNotEmpty)
            _row('Patient ID', bill.patientId!),
          if (bill.patientPhone != null && bill.patientPhone!.isNotEmpty)
            _row('Phone', bill.patientPhone!),
          pw.SizedBox(height: 6),
          pw.Divider(),
          pw.SizedBox(height: 6),

          // Scan
          _row('Scan Type', scanType?.name ?? 'N/A'),
          _row('Scan Fee', formatCurrency(bill.scanFee)),
          if (bill.discount > 0) _row('Discount', '- ${formatCurrency(bill.discount)}'),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total Amount',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
              pw.Text(
                formatCurrency(bill.finalAmount),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          _row('Payment Mode', bill.paymentMode),
          if (referralDoctor != null)
            _row('Referred By', 'Dr. ${referralDoctor.name}'),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 8),

          pw.Center(
            child: pw.Text(
              'Thank you for visiting IHA Care',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    ),
  );

  return pdf.save();
}

Future<Uint8List> generateIncentiveReport(
  List<IncentiveRecord> records,
  Map<String, ReferralDoctor> doctors,
  String month,
) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) {
        double totalReferrals = 0;
        double totalBilled = 0;
        double totalIncentive = 0;
        for (final r in records) {
          totalReferrals += r.referralCount;
          totalBilled += r.totalBilled;
          totalIncentive += r.incentiveAmount;
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'IHA Care — Referral Incentive Report',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              formatMonthYear(month),
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2),
              },
              children: [
                _tableHeader(['Doctor / Scan', 'Clinic', 'Referrals', 'Billed (₹)', 'Incentive (₹)']),
                ...records.expand((r) {
                  final doc = doctors[r.referralDoctorId];
                  return [
                    _tableRow([
                      doc?.name ?? r.referralDoctorId,
                      doc?.clinicName ?? '-',
                      r.referralCount.toString(),
                      formatCurrency(r.totalBilled),
                      formatCurrency(r.incentiveAmount),
                    ]),
                    // Breakdown sub-rows, one per scan type
                    ...r.breakdown.map((b) => _tableRow(
                      [
                        '  └ ${b.scanTypeName}',
                        '',
                        '${b.count} × ${formatCurrency(b.rate)}',
                        '',
                        formatCurrency(b.total),
                      ],
                      isBreakdown: true,
                    )),
                  ];
                }),
                _tableRow(
                  ['TOTAL', '', totalReferrals.toInt().toString(), formatCurrency(totalBilled), formatCurrency(totalIncentive)],
                  bold: true,
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

  return pdf.save();
}

pw.Widget _row(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );

pw.TableRow _tableHeader(List<String> cells) => pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: cells
          .map(
            (c) => pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(c, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            ),
          )
          .toList(),
    );

pw.TableRow _tableRow(List<String> cells,
        {bool bold = false, bool isBreakdown = false}) =>
    pw.TableRow(
      decoration: isBreakdown
          ? const pw.BoxDecoration(color: PdfColors.grey100)
          : null,
      children: cells
          .map(
            (c) => pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                c,
                style: pw.TextStyle(
                  fontSize: isBreakdown ? 8 : 9,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: isBreakdown ? PdfColors.grey700 : PdfColors.black,
                ),
              ),
            ),
          )
          .toList(),
    );
