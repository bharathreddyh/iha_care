import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../models/billing/bill.dart';
import '../../models/billing/referral_doctor.dart';
import '../../models/billing/scan_type.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
import '../../utils/pdf_generator.dart';

class ReceiptPreviewScreen extends StatelessWidget {
  final Bill bill;
  final ScanType? scanType;
  final ReferralDoctor? referralDoctor;

  const ReceiptPreviewScreen({
    super.key,
    required this.bill,
    this.scanType,
    this.referralDoctor,
  });

  Future<void> _printOrShare(BuildContext context) async {
    final bytes = await generateReceipt(bill, scanType, referralDoctor);
    await Printing.sharePdf(bytes: bytes, filename: 'receipt_${bill.id}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Receipt — ${bill.id}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print / Share',
            onPressed: () => _printOrShare(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Sahyadri Scan and Diagnostics',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Scan and Diagnostics Centre',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 24, thickness: 1.5),
                    _row(context, 'Bill No', bill.id),
                    _row(context, 'Date', formatDateTime(bill.createdAt)),
                    const Divider(),
                    _row(context, 'Patient', bill.patientName),
                    if (bill.patientId != null && bill.patientId!.isNotEmpty)
                      _row(context, 'Patient ID', bill.patientId!),
                    if (bill.patientPhone != null && bill.patientPhone!.isNotEmpty)
                      _row(context, 'Phone', bill.patientPhone!),
                    const Divider(),
                    _row(context, 'Scan', scanType?.name ?? 'N/A'),
                    _row(context, 'Scan Fee', formatCurrency(bill.scanFee)),
                    if (bill.discount > 0)
                      _row(context, 'Discount', '- ${formatCurrency(bill.discount)}',
                          valueColor: Colors.green),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Amount',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formatCurrency(bill.finalAmount),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _row(context, 'Payment', bill.paymentMode),
                    if (referralDoctor != null)
                      _row(context, 'Referred By', 'Dr. ${referralDoctor!.name}'),
                    const Divider(height: 24),
                    Center(
                      child: Text(
                        'Thank you for visiting Sahyadri Scan and Diagnostics',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Print / Share Receipt'),
            onPressed: () => _printOrShare(context),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
