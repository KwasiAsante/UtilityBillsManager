import 'package:flutter/material.dart';

import '../data/models/bill.dart';
import '../data/models/rentor.dart';
import '../utils/bills/property_manager_share.dart';

/// Read-only summary of the Property Manager's share per bill type.
///
/// The Property Manager covers whatever the active rentors don't pay, so each
/// covered [BillType] shows `100 - sum(rentor percentages)`. Shown above the
/// rentor list; renders nothing when no bill type is covered.
///
/// [rentors] should be the full, unfiltered rentor list. [asOf] defaults to
/// today and determines which rentors are active (see [Rentor.isActiveOn]).
class PropertyManagerCard extends StatelessWidget {
  final List<Rentor> rentors;
  final DateTime? asOf;

  const PropertyManagerCard({super.key, required this.rentors, this.asOf});

  @override
  Widget build(BuildContext context) {
    // Snap float noise (e.g. 1.4e-14 from 100 - (33.3 + 33.4 + 33.3)) to 0 so
    // a true 100% neither shows "-0.00%" nor misses the warning.
    final shares = {
      for (final entry
          in PropertyManagerShare.sharesAsOf(
            asOf ?? DateTime.now(),
            rentors,
          ).entries)
        entry.key: entry.value.abs() < 1e-9 ? 0.0 : entry.value,
    };
    if (shares.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final overTypes = [
      for (final entry in shares.entries)
        if (entry.value <= 0) entry.key,
    ];

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Property Manager',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Covers whatever the rentors don't pay",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in shares.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${entry.key.name}  ${entry.value.toStringAsFixed(2)}%',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            if (overTypes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Rentor percentages for '
                      '${overTypes.map((t) => t.name).join(', ')} '
                      'add up to 100% or more. '
                      'Update the rentor percentages.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
