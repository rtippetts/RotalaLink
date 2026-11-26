import 'package:flutter/material.dart';

import '../tank_detail_page.dart';

/// Passes the existing tank object through so its tracked parameters and
/// custom ranges survive the shortcut into the reading editor.
class RecordTankPicker extends StatelessWidget {
  const RecordTankPicker({
    super.key,
    required this.tanks,
    required this.onAddTank,
  });

  final List<Tank> tanks;
  final VoidCallback onAddTank;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record a reading',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              tanks.isEmpty
                  ? 'Add your first aquarium, then log its water parameters.'
                  : 'Choose the aquarium you tested. No device is needed.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (tanks.isEmpty)
              FilledButton.icon(
                onPressed: onAddTank,
                icon: const Icon(Icons.add),
                label: const Text('Add tank'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tanks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final tank = tanks[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.water_outlined),
                      title: Text(
                        tank.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(tank.inhabitants),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pop(tank),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
