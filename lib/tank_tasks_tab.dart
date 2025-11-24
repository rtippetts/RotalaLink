import 'package:flutter/material.dart';
import 'package:your_app/models/tank_models.dart';

class TankTasksTab extends StatelessWidget {
  const TankTasksTab({
    super.key,
    required this.cardColor,
    required this.tasks,
    required this.timeExact,
    required this.onToggleDone,
    required this.onCreateOrEdit,
    required this.onDelete,
  });

  final Color cardColor;
  final List<TaskItem> tasks;
  final String Function(DateTime) timeExact;
  final void Function(TaskItem, bool) onToggleDone;
  final void Function({TaskItem? existing}) onCreateOrEdit;
  final void Function(TaskItem) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == tasks.length) {
          return OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: () => onCreateOrEdit(),
            icon: const Icon(Icons.add_task),
            label: const Text('Add Task'),
          );
        }
        final t = tasks[i];
        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: CheckboxListTile(
            value: t.done,
            onChanged: (v) => onToggleDone(t, v ?? false),
            title: Text(
              t.title,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.due != null)
                  Text(
                    'Due ${timeExact(t.due!)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
            controlAffinity: ListTileControlAffinity.leading,
            checkboxShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            activeColor: Colors.teal,
            secondary: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              onSelected: (v) {
                if (v == 'edit') onCreateOrEdit(existing: t);
                if (v == 'delete') onDelete(t);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        );
      },
    );
  }
}
