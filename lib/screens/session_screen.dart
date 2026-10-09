import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import '../models.dart';
import '../util.dart';
import '../widgets.dart';
import 'workout_screen.dart';

class _SetRow {
  _SetRow({String weight = ''})
      : w = TextEditingController(text: weight),
        r = TextEditingController();
  final TextEditingController w;
  final TextEditingController r;
  bool done = false;

  void dispose() {
    w.dispose();
    r.dispose();
  }
}

class _Block {
  _Block({
    required this.exerciseId,
    required this.name,
    required this.muscle,
    required this.repMin,
    required this.repMax,
  });
  final int exerciseId;
  final String name;
  final String muscle;
  final int repMin, repMax;
  final List<_SetRow> rows = [];
  List<SetEntry> last = [];
  Suggestion? suggestion;
}

class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key, required this.routine});
  final Routine routine;

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  static const _restDefault = 90;

  final List<_Block> _blocks = [];
  late final DateTime _startedAt;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  int _restLeft = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt);
        if (_restLeft > 0) _restLeft--;
      });
    });
    _init();
  }

  Future<void> _init() async {
    for (final it in widget.routine.items) {
      await _addBlock(it.exerciseId, it.exerciseName, it.muscle, it.sets, it.repMin, it.repMax);
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _addBlock(int exId, String name, String muscle, int sets, int repMin, int repMax) async {
    final b = _Block(exerciseId: exId, name: name, muscle: muscle, repMin: repMin, repMax: repMax);
    b.last = await AppDb.instance.lastSetsFor(exId);
    b.suggestion = suggestNext(b.last, repMin, repMax, increment: incrementFor(muscle));
    final w = b.suggestion?.weight;
    for (var i = 0; i < sets; i++) {
      b.rows.add(_SetRow(weight: w == null ? '' : fmtW(w)));
    }
    if (!mounted) return;
    setState(() => _blocks.add(b));
  }

  Future<void> _pickExercise() async {
    final ex = await Navigator.push<Exercise>(context, MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (ex == null) return;
    await _addBlock(ex.id, ex.name, ex.muscle, 3, 8, 12);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final b in _blocks) {
      for (final r in b.rows) {
        r.dispose();
      }
    }
    super.dispose();
  }

  void _toggleDone(_SetRow row) {
    if (!row.done) {
      final reps = int.tryParse(row.r.text.trim());
      final weight = row.w.text.trim().isEmpty ? 0.0 : parseNum(row.w.text);
      if (reps == null || reps <= 0 || weight == null || weight < 0) {
        showSnack(context, 'Enter your reps. Leave weight empty for bodyweight exercises.');
        return;
      }
    }
    setState(() {
      row.done = !row.done;
      if (row.done) _restLeft = _restDefault;
    });
  }

  List<LoggedExercise> _collect() {
    final out = <LoggedExercise>[];
    for (final b in _blocks) {
      final sets = <SetEntry>[];
      for (final r in b.rows) {
        if (!r.done) continue;
        final reps = int.tryParse(r.r.text.trim());
        final w = r.w.text.trim().isEmpty ? 0.0 : parseNum(r.w.text);
        if (reps == null || reps <= 0 || w == null) continue;
        sets.add(SetEntry(w, reps));
      }
      if (sets.isNotEmpty) out.add(LoggedExercise(b.exerciseId, sets));
    }
    return out;
  }

  Future<void> _finish() async {
    final logged = _collect();
    if (logged.isEmpty) {
      final discard = await confirmDialog(
          context, 'No sets completed', 'Tick the check mark on each set you finish. Discard this workout?', 'Discard');
      if (discard && mounted) Navigator.pop(context, false);
      return;
    }
    final profile = await AppDb.instance.getProfile();
    final minutes = math.max(1, _elapsed.inMinutes);
    final kcal = strengthKcal(profile?.weightKg ?? 70, minutes);
    await AppDb.instance.saveSession(
      date: dayKey(_startedAt),
      routineId: widget.routine.id,
      routineName: widget.routine.name,
      startedAt: _startedAt,
      durationMin: minutes,
      kcalBurned: kcal,
      exercises: logged,
    );
    if (!mounted) return;
    final sets = logged.fold<int>(0, (a, e) => a + e.sets.length);
    showSnack(context, 'Workout saved: $sets sets in $minutes min, about ${kcal.round()} kcal burned.');
    Navigator.pop(context, true);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await confirmDialog(context, 'Leave workout?', 'Sets you have not saved will be lost.', 'Leave');
        if (leave && context.mounted) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.routine.name),
          actions: [
            Center(child: Text(_fmt(_elapsed), style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(width: 12),
            FilledButton(onPressed: _finish, child: const Text('Finish')),
            const SizedBox(width: 12),
          ],
        ),
        body: !_ready
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                children: [
                  if (_blocks.isEmpty) const EmptyNote('Add an exercise to get started.'),
                  for (final b in _blocks) _blockCard(b),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickExercise,
                    icon: const Icon(Icons.add),
                    label: const Text('Add exercise'),
                  ),
                ],
              ),
        bottomNavigationBar: _restLeft > 0 ? _restBar() : null,
      ),
    );
  }

  Widget _restBar() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Icon(Icons.timer_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Text('Rest ${_fmt(Duration(seconds: _restLeft))}',
                style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 18, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(onPressed: () => setState(() => _restLeft = math.max(0, _restLeft - 15)), child: const Text('-15s')),
            TextButton(onPressed: () => setState(() => _restLeft += 15), child: const Text('+15s')),
            TextButton(onPressed: () => setState(() => _restLeft = 0), child: const Text('Skip')),
          ]),
        ),
      ),
    );
  }

  Widget _blockCard(_Block b) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelSmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.name, style: theme.textTheme.titleMedium),
          if (b.suggestion != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.trending_up, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(b.suggestion!.text, style: theme.textTheme.bodySmall)),
              ]),
            ),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 28, child: Text('Set', style: label)),
            Expanded(flex: 3, child: Text('Last time', style: label)),
            Expanded(flex: 3, child: Text('kg', style: label, textAlign: TextAlign.center)),
            Expanded(flex: 3, child: Text('Reps', style: label, textAlign: TextAlign.center)),
            const SizedBox(width: 48),
          ]),
          for (var i = 0; i < b.rows.length; i++) _setRow(b, i),
          Row(children: [
            TextButton.icon(
              onPressed: () => setState(() => b.rows.add(_SetRow(weight: b.rows.isEmpty ? '' : b.rows.last.w.text))),
              icon: const Icon(Icons.add),
              label: const Text('Add set'),
            ),
            if (b.rows.length > 1)
              TextButton(
                onPressed: () {
                  final removed = b.rows.last;
                  setState(() => b.rows.removeLast());
                  WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                },
                child: const Text('Remove set'),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _setRow(_Block b, int i) {
    final row = b.rows[i];
    final scheme = Theme.of(context).colorScheme;
    final prev = i < b.last.length
        ? (b.last[i].weight > 0 ? '${fmtW(b.last[i].weight)} x ${b.last[i].reps}' : '${b.last[i].reps} reps')
        : '-';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: row.done ? scheme.primary.withAlpha(35) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        SizedBox(width: 28, child: Text('${i + 1}', textAlign: TextAlign.center)),
        Expanded(flex: 3, child: Text(prev, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: TextField(
              controller: row.w,
              enabled: !row.done,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'BW'),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: TextField(
              controller: row.r,
              enabled: !row.done,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: '${b.repMin}-${b.repMax}'),
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: IconButton(
            icon: Icon(row.done ? Icons.check_circle : Icons.check_circle_outline),
            color: row.done ? scheme.primary : null,
            tooltip: row.done ? 'Undo' : 'Complete set',
            onPressed: () => _toggleDone(row),
          ),
        ),
      ]),
    );
  }
}
