import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const KanbanApp());
}

class KanbanApp extends StatelessWidget {
  const KanbanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Kanban',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const RootHome(),
    );
  }
}

class RootHome extends StatefulWidget {
  const RootHome({super.key});

  @override
  State<RootHome> createState() => _RootHomeState();
}

class _RootHomeState extends State<RootHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tab == 0 ? const BoardScreen() : const StatsScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.view_kanban_outlined), label: 'Board'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Stats'),
        ],
        onDestinationSelected: (i) => setState(() => _tab = i),
      ),
    );
  }
}

// ===== DATA LAYER =====

enum TaskStatus { todo, done }

class Task {
  final String id;
  String title;
  TaskStatus status;
  DateTime createdAt;
  DateTime? doneAt;

  Task({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    this.doneAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'doneAt': doneAt?.toIso8601String(),
      };

  static Task fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        title: json['title'],
        status: (json['status'] == 'done') ? TaskStatus.done : TaskStatus.todo,
        createdAt: DateTime.parse(json['createdAt']),
        doneAt: json['doneAt'] != null ? DateTime.parse(json['doneAt']) : null,
      );
}

class TaskStore extends ChangeNotifier {
  static const _storageKey = 'tasks_v1';
  final List<Task> _tasks = [];

  List<Task> get tasks => List.unmodifiable(_tasks);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _tasks
        ..clear()
        ..addAll(list.map(Task.fromJson));
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey, jsonEncode(_tasks.map((t) => t.toJson()).toList()));
  }

  Future<void> add(String title) async {
    final t = Task(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.trim(),
      status: TaskStatus.todo,
      createdAt: DateTime.now(),
    );
    _tasks.insert(0, t);
    await _persist();
    notifyListeners();
  }

  Future<void> updateStatus(String id, TaskStatus status) async {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i == -1) return;
    _tasks[i].status = status;
    _tasks[i].doneAt = (status == TaskStatus.done) ? DateTime.now() : null;
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> rename(String id, String title) async {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i == -1) return;
    _tasks[i].title = title.trim();
    await _persist();
    notifyListeners();
  }

  // Stats helpers
  List<Task> tasksInLast7DaysCreated() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    return _tasks.where((t) => t.createdAt.isAfter(start.subtract(const Duration(seconds: 1)))).toList();
  }

  List<Task> tasksInLast7DaysDone() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    return _tasks.where((t) => t.doneAt != null && t.doneAt!.isAfter(start.subtract(const Duration(seconds: 1)))).toList();
  }

  Map<DateTime, int> donePerDayLast7() {
    final map = <DateTime, int>{};
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      map[d] = 0;
    }
    for (final t in tasksInLast7DaysDone()) {
      final d = DateTime(t.doneAt!.year, t.doneAt!.month, t.doneAt!.day);
      if (map.containsKey(d)) map[d] = (map[d] ?? 0) + 1;
    }
    return map;
  }
}

class TaskProvider extends InheritedNotifier<TaskStore> {
  const TaskProvider({
    super.key,
    required TaskStore notifier,
    required Widget child,
  }) : super(notifier: notifier, child: child);

  static TaskStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TaskProvider>()!.notifier!;
}

// ===== UI: BOARD =====

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final TaskStore store = TaskStore();
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    return TaskProvider(
      notifier: store,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Kanban (To Do • Done)'),
          actions: [
            IconButton(
              tooltip: 'Clear input',
              onPressed: () => _controller.clear(),
              icon: const Icon(Icons.clear_all),
            )
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Add a task for today…',
                        prefixIcon: Icon(Icons.add_task),
                      ),
                      onSubmitted: (v) async {
                        if (v.trim().isEmpty) return;
                        await store.add(v);
                        _controller.clear();
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final v = _controller.text;
                      if (v.trim().isEmpty) return;
                      await store.add(v);
                      _controller.clear();
                      setState(() {});
                    },
                    child: const Text('Add'),
                  )
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: const [
                    Expanded(child: _ColumnList(title: 'To Do', status: TaskStatus.todo)),
                    SizedBox(width: 12),
                    Expanded(child: _ColumnList(title: 'Done', status: TaskStatus.done)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColumnList extends StatefulWidget {
  final String title;
  final TaskStatus status;
  const _ColumnList({required this.title, required this.status});

  @override
  State<_ColumnList> createState() => _ColumnListState();
}

class _ColumnListState extends State<_ColumnList> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final store = TaskProvider.of(context);
    final items = store.tasks.where((t) => t.status == widget.status).toList();

    return DragTarget<String>(
      onWillAccept: (_) { setState(() => _hovering = true); return true; },
      onLeave: (_) => setState(() => _hovering = false),
      onAccept: (taskId) async {
        await store.updateStatus(taskId, widget.status);
        setState(() => _hovering = false);
      },
      builder: (context, candidate, rejected) {
        return Card(
          elevation: _hovering ? 4 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '${widget.title} (${items.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (widget.status == TaskStatus.done)
                      const Icon(Icons.check_circle, size: 20)
                    else
                      const Icon(Icons.radio_button_unchecked, size: 20),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            widget.status == TaskStatus.todo
                                ? 'No tasks. Add one above.'
                                : 'Nothing done yet.',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) => TaskTile(task: items[i]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TaskTile extends StatelessWidget {
  final Task task;
  const TaskTile({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final store = TaskProvider.of(context);

    return LongPressDraggable<String>(
      data: task.id,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: _tileContent(context, dragging: true),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _tileContent(context)),
      child: _tileContent(context),
    );
  }

  Widget _tileContent(BuildContext context, {bool dragging = false}) {
    final store = TaskProvider.of(context);
    final subtle = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        tileColor: dragging ? subtle : null,
        title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${task.status == TaskStatus.done ? "Done" : "Created"} • '
          '${DateFormat('EEE, d MMM, h:mma').format(task.status == TaskStatus.done ? (task.doneAt ?? task.createdAt) : task.createdAt)}',
        ),
        leading: IconButton(
          tooltip: task.status == TaskStatus.todo ? 'Mark as Done' : 'Move to To Do',
          icon: Icon(task.status == TaskStatus.todo ? Icons.check_circle_outline : Icons.undo),
          onPressed: () async {
            await store.updateStatus(
                task.id, task.status == TaskStatus.todo ? TaskStatus.done : TaskStatus.todo);
          },
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
          onSelected: (v) async {
            if (v == 'delete') {
              await store.delete(task.id);
            } else if (v == 'rename') {
              final controller = TextEditingController(text: task.title);
              final newTitle = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Rename task'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Task title'),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
                  ],
                ),
              );
              if (newTitle != null && newTitle.trim().isNotEmpty) {
                await store.rename(task.id, newTitle);
              }
            }
          },
        ),
      ),
    );
  }
}

// ===== UI: STATS =====

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final TaskStore store = TaskStore();

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    return TaskProvider(
      notifier: store,
      child: Scaffold(
        appBar: AppBar(title: const Text('Weekly Summary')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) {
              final created = store.tasksInLast7DaysCreated().length;
              final done = store.tasksInLast7DaysDone().length;
              final percent = created == 0 ? 0 : ((done / created) * 100).round();

              final bars = store.donePerDayLast7();
              final days = bars.keys.toList()..sort();

              return ListView(
                children: [
                  _KpiCard(
                    title: 'Completion this week',
                    value: '$percent%',
                    subtitle: '$done of $created tasks done',
                    icon: Icons.check_circle,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tasks completed per day (last 7 days)',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          if (days.isEmpty) const SizedBox(height: 200, child: Center(child: Text('No data yet')))
                          else SizedBox(
                            height: 220,
                            child: BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                titlesData: FlTitlesData(
                                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (x, meta) {
                                        final idx = x.toInt();
                                        if (idx < 0 || idx >= days.length) {
                                          return const SizedBox.shrink();
                                        }
                                        final label = DateFormat('E').format(days[idx]);
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 6.0),
                                          child: Text(label, style: const TextStyle(fontSize: 11)),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                gridData: const FlGridData(show: true),
                                barGroups: List.generate(days.length, (i) {
                                  final d = days[i];
                                  final v = bars[d] ?? 0;
                                  return BarChartGroupData(
                                    x: i,
                                    barRods: [BarChartRodData(toY: v.toDouble(), width: 18, borderRadius: BorderRadius.circular(6))],
                                  );
                                }),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('This week details', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('Week of ${_weekRangeLabel()}'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            children: [
                              _ChipStat(icon: Icons.add_task, label: 'Created', value: '$created'),
                              _ChipStat(icon: Icons.done_all, label: 'Done', value: '$done'),
                              _ChipStat(icon: Icons.percent, label: 'Complete', value: '$percent%'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _weekRangeLabel() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final f = DateFormat('d MMM');
    return '${f.format(start)} - ${f.format(now)}';
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _KpiCard({required this.title, required this.value, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Row(
  
