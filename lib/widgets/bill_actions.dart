import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/billing/bill.dart';
import '../services/billing_service.dart';
import '../services/inventory_service.dart';
import '../services/mwl_service.dart';

/// Shows a confirm dialog, then soft-cancels the bill, reverses inventory,
/// and removes the MWL entry. Returns true if cancelled.
Future<bool> cancelBillFlow(BuildContext context, Bill bill) async {
  if (bill.isCancelled) return false;

  final reasonController = TextEditingController();
  String selectedReason = 'Patient declined';
  const reasons = [
    'Patient declined',
    'No-show',
    'Wrong scan selected',
    'Duplicate entry',
    'Other',
  ];

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Cancel bill ${bill.id}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This bill will be marked cancelled and excluded from '
                'income reports. Inventory will be restored.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedReason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: reasons
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => setState(() => selectedReason = v ?? reasons[0]),
            ),
            if (selectedReason == 'Other') ...[
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Describe reason',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Bill'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true || !context.mounted) return false;

  final reason = selectedReason == 'Other' && reasonController.text.trim().isNotEmpty
      ? reasonController.text.trim()
      : selectedReason;

  final billing = context.read<BillingService>();
  final inventory = context.read<InventoryService>();
  final mwl = context.read<MwlService>();

  await billing.cancelBill(bill.id, reason);
  try { await inventory.reverseForBill(bill.id); } catch (_) {}
  if (bill.worklistPushed && bill.accessionNumber != null) {
    try { await mwl.removeFromWorklist(bill.accessionNumber!); } catch (_) {}
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bill ${bill.id} cancelled — $reason')),
    );
  }
  return true;
}

/// Hard-delete a recently created bill (if eligible). Returns true if deleted.
Future<bool> deleteBillFlow(BuildContext context, Bill bill) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete bill ${bill.id}?'),
      content: const Text(
        'This permanently removes the bill and creates a gap in the sequence. '
        'Only allowed for bills created within 5 minutes, with no MWL push, '
        'no payment, and not yet cloud-synced.\n\n'
        'Prefer Cancel for most situations.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final billing = context.read<BillingService>();
  final inventory = context.read<InventoryService>();

  // Reverse inventory first (delete only wipes the txn rows, not stock changes).
  try { await inventory.reverseForBill(bill.id); } catch (_) {}
  final ok = await billing.deleteBillIfEligible(bill.id);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Bill ${bill.id} deleted.'
            : 'Cannot delete — bill is too old, already synced, paid, or pushed to MWL. Use Cancel instead.'),
        backgroundColor: ok ? null : Colors.orange,
      ),
    );
  }
  return ok;
}

/// Returns true if the bill is still within the 5-min hard-delete window
/// (UI can hide the menu item when false).
bool canHardDelete(Bill bill) {
  final created = DateTime.tryParse(bill.createdAt);
  if (created == null) return false;
  return DateTime.now().difference(created).inMinutes <= 5 &&
      !bill.worklistPushed &&
      bill.amountPaid <= 0 &&
      !bill.isCancelled;
}
