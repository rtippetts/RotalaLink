import 'package:flutter/material.dart';
import 'package:your_app/models/tank_models.dart';

class TankNotesTab extends StatelessWidget {
  const TankNotesTab({
    super.key,
    required this.cardColor,
    required this.notes,
    required this.timeExact,
    required this.onCreateOrEdit,
    required this.onDelete,
  });

  final Color cardColor;
  final List<NoteItem> notes;
  final String Function(DateTime) timeExact;
  final void Function({NoteItem? existing}) onCreateOrEdit;
  final void Function(NoteItem) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...notes.map(
          (n) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.event_note, color: Colors.white70),
              title: Text(
                n.title,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  if (n.body.trim().isNotEmpty)
                    Text(
                      n.body,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  if (n.photos.isNotEmpty) const SizedBox(height: 8),
                  if (n.photos.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in n.photos.take(3))
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              p.publicUrl,
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                            ),
                          ),
                        if (n.photos.length > 3)
                          Text(
                            '+${n.photos.length - 3} more',
                            style: const TextStyle(color: Colors.white54),
                          ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    timeExact(n.createdAt),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white70),
                onSelected: (v) {
                  if (v == 'edit') onCreateOrEdit(existing: n);
                  if (v == 'delete') onDelete(n);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
          ),
          onPressed: () => onCreateOrEdit(),
          icon: const Icon(Icons.add),
          label: const Text('Add Note'),
        ),
      ],
    );
  }
}
