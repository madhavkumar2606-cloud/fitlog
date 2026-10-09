import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../util.dart';
import '../widgets.dart';
import 'session_screen.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  List<Routine> _routines = [];
  List<SessionSummary> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.instance.routines();
    final h = await AppDb.instance.recentSessions();
    if (!mounted) return;
    setState(() {
      _routines = r;
      _history = h;
      _loading = false;
    });
  }

  Future<void> _start(Routine r) async {
    final saved =
        await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ActiveSessionScreen(routine: r)));
    if (saved == true) await _load();
  }

  Future<void> _edit([Routine? r]) async {
    final changed =
        await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RoutineEditorScreen(routine: r)));
    if (changed == true) await _load();
  }

  Future<void> _openSession(SessionSummary s) async {
    final changed =
        await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SessionDetailScreen(summary: s)));
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workouts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _start(Routine(name: 'Quick workout')),
        icon: const Icon(Icons.bolt),
        label: const Text('Quick workout'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  SectionHeader(
                    title: 'Routines',
                    trailing: TextButton.icon(
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add),
                      label: const Text('New routine'),
                    ),
                  ),
                  if (_routines.isEmpty) const EmptyNote('Create a routine to load your usual workout in one tap.'),
                  for (final r in _routines)
                    Card(
                      child: ListTile(
                        title: Text(r.name),
                        subtitle: Text(
                          r.items.map((i) => i.exerciseName).join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _edit(r),
                        trailing: FilledButton(onPressed: () => _start(r), child: const Text('Start')),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const SectionHeader(title: 'History'),
                  if (_history.isEmpty) const EmptyNote('Finished workouts show up here.'),
                  for (final s in _history)
                    Card(
                      child: ListTile(
                        title: Text(s.routineName),
                        subtitle: Text(
                            '${prettyDay(s.date)}, ${s.sets} sets, ${s.volume.round()} kg lifted, ${s.durationMin} min'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openSession(s),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({super.key, this.routine});
  final Routine? routine;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  late final TextEditingController _name;
  late final List<RoutineItem> _items;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.routine?.name ?? '');
    _items = [
      for (final i in widget.routine?.items ?? <RoutineItem>[])
        RoutineItem(
          exerciseId: i.exerciseId,
          exerciseName: i.exerciseName,
          muscle: i.muscle,
          sets: i.sets,
          repMin: i.repMin,
          repMax: i.repMax,
        ),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    final ex = await Navigator.push<Exercise>(context, MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (ex == null) return;
    setState(() => _items.add(RoutineItem(exerciseId: ex.id, exerciseName: ex.name, muscle: ex.muscle)));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _items.isEmpty) {
      showSnack(context, 'Add a name and at least one exercise.');
      return;
    }
    await AppDb.instance.saveRoutine(Routine(id: widget.routine?.id, name: name, items: _items));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final id = widget.routine?.id;
    if (id == null) return;
    final ok = await confirmDialog(context, 'Delete routine?', 'Past workouts stay in your history.', 'Delete');
    if (!ok) return;
    await AppDb.instance.deleteRoutine(id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _items.length) return;
    setState(() {
      final tmp = _items[i];
      _items[i] = _items[j];
      _items[j] = tmp;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routine == null ? 'New routine' : 'Edit routine'),
        actions: [
          if (widget.routine != null)
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete routine', onPressed: _delete),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Routine name')),
          const SizedBox(height: 16),
          for (var i = 0; i < _items.length; i++) _itemCard(i),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _addExercise, icon: const Icon(Icons.add), label: const Text('Add exercise')),
        ],
      ),
    );
  }

  Widget _itemCard(int i) {
    final it = _items[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(it.exerciseName, style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Move up',
              onPressed: i > 0 ? () => _move(i, -1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Remove',
              onPressed: () => setState(() => _items.removeAt(i)),
            ),
          ]),
          Wrap(spacing: 4, children: [
            Counter(label: 'Sets', value: it.sets, max: 10, onChanged: (v) => setState(() => it.sets = v)),
            Counter(
              label: 'Min reps',
              value: it.repMin,
              onChanged: (v) => setState(() {
                it.repMin = v;
                if (it.repMax < v) it.repMax = v;
              }),
            ),
            Counter(
              label: 'Max reps',
              value: it.repMax,
              onChanged: (v) => setState(() {
                it.repMax = v;
                if (it.repMin > v) it.repMin = v;
              }),
            ),
          ]),
        ]),
      ),
    );
  }
}

class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key});

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  static const _muscles = [
    'Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps', 'Quads',
    'Hamstrings', 'Glutes', 'Calves', 'Core', 'Full body', 'Cardio',
  ];

  List<Exercise> _all = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    AppDb.instance.exercises().then((v) {
      if (mounted) setState(() => _all = v);
    });
  }

  Future<void> _create() async {
    final muscle = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Muscle group for "$_q"'),
        children: [
          for (final m in _muscles) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, m), child: Text(m)),
        ],
      ),
    );
    if (muscle == null) return;
    final ex = await AppDb.instance.addExercise(_q, muscle);
    if (!mounted) return;
    Navigator.pop(context, ex);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final filtered = q.isEmpty
        ? _all
        : _all.where((e) => e.name.toLowerCase().contains(q) || e.muscle.toLowerCase().contains(q)).toList();
    final exact = _all.any((e) => e.name.toLowerCase() == q);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search exercises', border: InputBorder.none),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
      ),
      body: ListView(children: [
        if (_q.isNotEmpty && !exact)
          ListTile(leading: const Icon(Icons.add), title: Text('Create "$_q"'), onTap: _create),
        for (final e in filtered)
          ListTile(title: Text(e.name), subtitle: Text(e.muscle), onTap: () => Navigator.pop(context, e)),
      ]),
    );
  }
}

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.summary});
  final SessionSummary summary;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final Map<String, List<SetEntry>> _byExercise = {};

  @override
  void initState() {
    super.initState();
    AppDb.instance.sessionDetail(widget.summary.id).then((rows) {
      if (!mounted) return;
      setState(() {
        for (final r in rows) {
          _byExercise
              .putIfAbsent(r['ename'] as String, () => [])
              .add(SetEntry(toD(r['weight']), r['reps'] as int));
        }
      });
    });
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, 'Delete workout?', 'This removes it from your history and charts.', 'Delete');
    if (!ok) return;
    await AppDb.instance.deleteSession(widget.summary.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.routineName),
        actions: [IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete workout', onPressed: _delete)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${shortDate(s.date)}: ${s.durationMin} min, ${s.volume.round()} kg lifted, about ${s.kcalBurned.round()} kcal burned',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          for (final e in _byExercise.entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.key, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (var i = 0; i < e.value.length; i++)
                    Text('Set ${i + 1}: ${e.value[i].weight > 0 ? '${fmtW(e.value[i].weight)} kg x ' : ''}${e.value[i].reps} reps'),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
