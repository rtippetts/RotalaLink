import 'package:flutter/material.dart';

class Task {
  Task({
    required this.id,
    required this.title,
    this.completed = false,
  });

  final String id;
  final String title;
  bool completed;
}

/// Single task row that:
/// 1. Shows the checkbox animation
/// 2. Waits briefly
/// 3. Calls onMoveToCompleted so the parent can move it
class TaskItem extends StatefulWidget {
  const TaskItem({
    super.key,
    required this.task,
    required this.onMoveToCompleted,
  });

  final Task task;
  final VoidCallback onMoveToCompleted;

  @override
  State<TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends State<TaskItem> {
  late bool _localCompleted;

  @override
  void initState() {
    super.initState();
    _localCompleted = widget.task.completed;
  }

  @override
  void didUpdateWidget(covariant TaskItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.completed != widget.task.completed) {
      _localCompleted = widget.task.completed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: _localCompleted ? 0.5 : 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Checkbox(
          value: _localCompleted,
          onChanged: (value) async {
            if (value == true && !_localCompleted) {
              // Show check and slight fade
              setState(() => _localCompleted = true);

              // Give the user a moment to see the checkmark
              await Future.delayed(const Duration(milliseconds: 220));

              // Tell parent to move this to Completed
              widget.onMoveToCompleted();
            }
          },
        ),
        title: Text(
          widget.task.title,
          style: TextStyle(
            color: Colors.white,
            decoration:
                _localCompleted ? TextDecoration.lineThrough : TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// Screen that holds open and completed tasks
/// and shows SnackBar with Undo when a task is completed
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  // TODO: replace with your real data source and model
  final List<Task> _openTasks = [
    Task(id: '1', title: 'Change filter'),
    Task(id: '2', title: 'Test water for 40 gal tank'),
    Task(id: '3', title: 'Wipe front glass'),
  ];

  final List<Task> _completedTasks = [];

  void _completeTask(Task task, int originalIndex) {
    setState(() {
      _openTasks.removeAt(originalIndex);
      task.completed = true;
      _completedTasks.insert(0, task);
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Task moved to Completed'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              _completedTasks.remove(task);
              task.completed = false;
              final safeIndex = originalIndex.clamp(0, _openTasks.length);
              _openTasks.insert(safeIndex, task);
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        elevation: 0,
        title: const Text(
          'Tasks',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text(
              'Open tasks',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),

            if (_openTasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No open tasks. Nice work.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _openTasks.length,
                itemBuilder: (context, index) {
                  final task = _openTasks[index];

                  return TaskItem(
                    task: task,
                    onMoveToCompleted: () {
                      _completeTask(task, index);
                    },
                  );
                },
              ),

            const SizedBox(height: 24),

            const Text(
              'Completed',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),

            if (_completedTasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Tasks you complete will appear here.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _completedTasks.length,
                itemBuilder: (context, index) {
                  final task = _completedTasks[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                    ),
                    title: Text(
                      task.title,
                      style: const TextStyle(
                        color: Colors.white70,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
