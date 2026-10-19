import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc.dart';
import '../db.dart';
import '../game.dart';
import '../models.dart';
import '../social.dart';
import '../util.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'workout_screen.dart';

class _SetRow {
  _SetRow({String weight = '', String reps = ''})
      : w = TextEditingController(text: weight),
        r = TextEditingController(text: reps);
  final TextEditingController w;
  final TextEditingController r;
  bool done = false;

  double get weight => w.text.trim().isEmpty ? 0 : (parseNum(w.text) ?? 0);
  int get reps => int.tryParse(r.text.trim()) ?? 0;

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
  double bestE1rm = 0;
  int selected = 0;

  int get doneCount => rows.where((r) => r.done).length;
  bool get complete => rows.isNotEmpty && doneCount == rows.length;
  int? get nextUndone {
    for (var i = 0; i < rows.length; i++) {
      if (!rows[i].done) return i;
    }
    return null;
  }
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
  final _page = PageController();
  late final DateTime _startedAt;
  Timer? _ticker;
  Timer? _prTimer;
  Duration _elapsed = Duration.zero;
  int _index = 0;
  int _restLeft = 0;
  int _restTotal = _restDefault;
  bool _ready = false;
  bool _saving = false;
  String? _prText;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt);
        if (_restLeft > 0) {
          _restLeft--;
          if (_restLeft == 0) HapticFeedback.heavyImpact();
        }
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
    b.bestE1rm = await AppDb.instance.bestE1rmBefore(exId, DateTime.now().toIso8601String());
    b.suggestion = suggestNext(b.last, repMin, repMax, increment: incrementFor(muscle));
    final w = b.suggestion?.weight;
    for (var i = 0; i < sets; i++) {
      final reps = i < b.last.length ? b.last[i].reps : repMin;
      b.rows.add(_SetRow(weight: w == null ? '' : fmtW(w), reps: '$reps'));
    }
    if (!mounted) return;
    setState(() => _blocks.add(b));
  }

  Future<void> _pickExercise() async {
    final ex = await Navigator.push<Exercise>(context, MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (ex == null) return;
    await _addBlock(ex.id, ex.name, ex.muscle, 3, 8, 12);
    if (!mounted) return;
    final target = _blocks.length - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_page.hasClients) {
        _page.animateToPage(target, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _prTimer?.cancel();
    _page.dispose();
    for (final b in _blocks) {
      for (final r in b.rows) {
        r.dispose();
      }
    }
    super.dispose();
  }

  // ---------- Set actions ----------

  void _nudge(_SetRow row, {double weight = 0, int reps = 0}) {
    if (row.done) return;
    setState(() {
      if (weight != 0) row.w.text = fmtW(math.max(0, row.weight + weight));
      if (reps != 0) row.r.text = '${math.max(0, row.reps + reps)}';
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _typeValue(_SetRow row, {required bool weight}) async {
    if (row.done) return;
    final v = await askNumber(context,
        title: weight ? 'Weight (kg)' : 'Reps', initial: weight ? fmtW(row.weight) : '${row.reps}', suffix: weight ? 'kg' : '');
    if (v == null || v < 0) return;
    setState(() {
      if (weight) {
        row.w.text = fmtW(v);
      } else {
        row.r.text = '${v.round()}';
      }
    });
  }

  void _complete(_Block b) {
    final row = b.rows[b.selected];
    if (row.done) {
      setState(() => row.done = false);
      return;
    }
    if (row.reps <= 0) {
      showSnack(context, 'Set your reps first.');
      return;
    }
    HapticFeedback.mediumImpact();
    // Live personal record check.
    if (row.weight > 0) {
      final e = epley(row.weight, row.reps);
      if (b.bestE1rm > 0 && e > b.bestE1rm + 0.01) {
        _showPr('${b.name}: estimated max ${fmtW(double.parse(e.toStringAsFixed(1)))} kg');
      }
      if (e > b.bestE1rm) b.bestE1rm = e;
    }
    setState(() {
      row.done = true;
      _restLeft = _restDefault;
      _restTotal = _restDefault;
      final next = b.nextUndone;
      if (next != null) b.selected = next;
    });
    if (b.complete) {
      final i = _blocks.indexOf(b);
      if (i >= 0 && i < _blocks.length - 1) {
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted && _page.hasClients && _index == i) {
            _page.animateToPage(i + 1, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
          }
        });
      }
    }
  }

  void _showPr(String text) {
    HapticFeedback.heavyImpact();
    _prTimer?.cancel();
    setState(() => _prText = text);
    _prTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _prText = null);
    });
  }

  void _addSet(_Block b) {
    setState(() {
      final lastRow = b.rows.isEmpty ? null : b.rows.last;
      b.rows.add(_SetRow(weight: lastRow?.w.text ?? '', reps: lastRow?.r.text ?? '${b.repMin}'));
      if (b.complete == false && b.rows[b.selected].done) b.selected = b.rows.length - 1;
    });
  }

  void _removeSet(_Block b) {
    if (b.rows.length <= 1) return;
    final removed = b.rows.last;
    setState(() {
      b.rows.removeLast();
      if (b.selected >= b.rows.length) b.selected = b.rows.length - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  List<LoggedExercise> _collect() {
    final out = <LoggedExercise>[];
    for (final b in _blocks) {
      final sets = <SetEntry>[];
      for (final r in b.rows) {
        if (!r.done || r.reps <= 0) continue;
        sets.add(SetEntry(r.weight, r.reps));
      }
      if (sets.isNotEmpty) out.add(LoggedExercise(b.exerciseId, sets));
    }
    return out;
  }

  Future<void> _finish() async {
    if (_saving) return;
    final logged = _collect();
    if (logged.isEmpty) {
      final discard = await confirmDialog(
          context, 'No sets completed', 'Tap "Done" after each set you finish. Discard this workout?', 'Discard');
      if (discard && mounted) Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    final profile = await AppDb.instance.getProfile();
    final minutes = math.max(1, _elapsed.inMinutes);
    final kcal = strengthKcal(profile?.weightKg ?? 70, minutes);
    final sid = await AppDb.instance.saveSession(
      date: dayKey(_startedAt),
      routineId: widget.routine.id,
      routineName: widget.routine.name,
      startedAt: _startedAt,
      durationMin: minutes,
      kcalBurned: kcal,
      exercises: logged,
    );
    final reward = await Game.rewardSession(sid);
    Social.instance.syncQuietly(reward.state);
    final summary = await AppDb.instance.sessionSummary(sid);
    if (!mounted || summary == null) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SessionSummaryScreen(summary: summary, reward: reward)),
      result: true,
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ---------- UI ----------

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
        backgroundColor: Sumi.paper,
        body: Stack(children: [
          const Positioned.fill(child: AppBackground()),
          SafeArea(
            child: Column(children: [
              _topBar(),
              if (_ready && _blocks.length > 1) _exerciseStrip(),
              Expanded(
                child: !_ready
                    ? const Center(child: CircularProgressIndicator())
                    : _blocks.isEmpty
                        ? _emptyState()
                        : PageView.builder(
                            controller: _page,
                            itemCount: _blocks.length,
                            onPageChanged: (i) => setState(() => _index = i),
                            itemBuilder: (context, i) => _exercisePage(_blocks[i]),
                          ),
              ),
            ]),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _restLeft == 0,
              child: AnimatedOpacity(
                opacity: _restLeft > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: _restOverlay(),
              ),
            ),
          ),
          if (_prText != null) Positioned(left: 20, right: 20, top: 90, child: _prBadge(_prText!)),
        ]),
      ),
    );
  }

  Widget _topBar() {
    final b = _blocks.isEmpty ? null : _blocks[_index.clamp(0, _blocks.length - 1)];
    final pos = _blocks.isEmpty ? '' : '${_index + 1} / ${_blocks.length}  ·  ';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(children: [
        _squareKey(Icons.close, () => Navigator.maybePop(context), 'Leave workout'),
        const SizedBox(width: 8),
        _squareKey(Icons.add, _pickExercise, 'Add exercise'),
        Expanded(child: Center(child: SumiLabel('$pos${_fmt(_elapsed)}'))),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            backgroundColor: b != null && _blocks.every((x) => x.complete) ? Sumi.ink : Sumi.porcelain,
            foregroundColor: b != null && _blocks.every((x) => x.complete) ? Sumi.porcelain : Sumi.ink,
          ),
          onPressed: _saving ? null : _finish,
          child: const Text('Finish'),
        ),
      ]),
    );
  }

  Widget _squareKey(IconData icon, VoidCallback onTap, String tip) {
    return Tooltip(
      message: tip,
      child: Material(
        color: Sumi.porcelain,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF3A3733)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 18, color: Sumi.ink)),
        ),
      ),
    );
  }

  Widget _exerciseStrip() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _blocks.length,
        itemBuilder: (context, i) {
          final b = _blocks[i];
          final active = i == _index;
          final frac = b.rows.isEmpty ? 0.0 : b.doneCount / b.rows.length;
          return InkWell(
            onTap: () => _page.animateToPage(i, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Enso(value: frac, size: 18, stroke: 2.4, seed: i),
                const SizedBox(width: 6),
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(b.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? Sumi.ink : Sumi.faint,
                      )),
                  const SizedBox(height: 3),
                  Opacity(opacity: active ? 1.0 : 0.0, child: const BrushLine(width: 22, thickness: 2.2)),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Enso(value: 0.15, size: 150, stroke: 10, child: Text('Begin', style: serif(28))),
          const SizedBox(height: 22),
          Text('Quick workout', style: serif(32)),
          const SizedBox(height: 6),
          const Text('Add your first exercise to get going.', textAlign: TextAlign.center, style: TextStyle(color: Sumi.muted)),
          const SizedBox(height: 22),
          FilledButton(onPressed: _pickExercise, child: const Text('Add exercise')),
        ]),
      ),
    );
  }

  Widget _exercisePage(_Block b) {
    final row = b.rows.isEmpty ? null : b.rows[b.selected.clamp(0, b.rows.length - 1)];
    final setNo = b.selected + 1;
    final prev = b.selected < b.last.length ? b.last[b.selected] : null;
    final frac = b.rows.isEmpty ? 0.0 : b.doneCount / b.rows.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
      children: [
        Center(child: SumiLabel(b.muscle)),
        const SizedBox(height: 6),
        Center(child: Text(b.name, textAlign: TextAlign.center, style: serif(36))),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < b.rows.length; i++) _setDot(b, i),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _addSet(b),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text('+ set', style: TextStyle(fontSize: 12, color: Sumi.muted)),
            ),
          ),
          if (b.rows.length > 1)
            InkWell(
              onTap: () => _removeSet(b),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text('− set', style: TextStyle(fontSize: 12, color: Sumi.muted)),
              ),
            ),
        ]),
        const SizedBox(height: 18),
        if (row != null) ...[
          Center(
            child: Enso(
              value: b.complete ? 1.0 : frac,
              size: 236,
              stroke: 12,
              seed: b.exerciseId,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () => _typeValue(row, weight: true),
                  child: Text(row.weight <= 0 ? 'BW' : fmtW(row.weight), style: serif(58, height: 1)),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _typeValue(row, weight: false),
                  child: Text('× ${row.reps}', style: const TextStyle(fontSize: 15, color: Sumi.muted)),
                ),
                const SizedBox(height: 8),
                SumiLabel(b.complete ? 'All ${b.rows.length} sets done' : 'Set $setNo of ${b.rows.length}', size: 8.5),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: _stepper(
                value: row.weight <= 0 ? 'BW' : fmtW(row.weight),
                unit: 'KG',
                enabled: !row.done,
                onMinus: () => _nudge(row, weight: -2.5),
                onPlus: () => _nudge(row, weight: 2.5),
                onTap: () => _typeValue(row, weight: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _stepper(
                value: '${row.reps}',
                unit: 'REPS ${b.repMin}-${b.repMax}',
                enabled: !row.done,
                onMinus: () => _nudge(row, reps: -1),
                onPlus: () => _nudge(row, reps: 1),
                onTap: () => _typeValue(row, weight: false),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Text(
            b.suggestion?.text ??
                (prev == null
                    ? 'First time on this set. Pick a weight with one or two reps in reserve.'
                    : 'Last time ${prev.weight > 0 ? '${fmtW(prev.weight)} × ' : ''}${prev.reps}.'),
            textAlign: TextAlign.center,
            style: serif(16, italic: true, color: Sumi.muted, height: 1.3),
          ),
          if (b.suggestion != null && prev != null) ...[
            const SizedBox(height: 4),
            Text('Last time ${prev.weight > 0 ? '${fmtW(prev.weight)} × ' : ''}${prev.reps}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: Sumi.muted)),
          ],
          const SizedBox(height: 20),
          row.done
              ? OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: () => _complete(b),
                  child: Text('Undo set $setNo'),
                )
              : FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: () => _complete(b),
                  child: Text('Done · set $setNo', style: const TextStyle(fontSize: 16)),
                ),
        ],
        if (b.doneCount > 0) ...[
          const SizedBox(height: 22),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Sumi.rule))),
            child: Column(children: [
              for (var i = 0; i < b.rows.length; i++)
                if (b.rows[i].done)
                  InkWell(
                    onTap: () => setState(() => b.selected = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Sumi.rule))),
                      child: Row(children: [
                        SumiLabel('Set ${i + 1}'),
                        const Spacer(),
                        Text('${b.rows[i].weight > 0 ? '${fmtW(b.rows[i].weight)} × ' : ''}${b.rows[i].reps}',
                            style: serif(19)),
                        const SizedBox(width: 12),
                        const Icon(Icons.check, size: 16, color: Sumi.ink),
                      ]),
                    ),
                  ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _setDot(_Block b, int i) {
    final row = b.rows[i];
    final selected = i == b.selected;
    final size = selected ? 14.0 : 10.0;
    return GestureDetector(
      onTap: () => setState(() => b.selected = i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: row.done ? Sumi.ink : Colors.transparent,
            border: Border.all(color: row.done || selected ? Sumi.ink : Sumi.faint, width: selected ? 1.8 : 1.2),
          ),
        ),
      ),
    );
  }

  Widget _stepper({
    required String value,
    required String unit,
    required bool enabled,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required VoidCallback onTap,
  }) {
    Widget seg(String t, VoidCallback f) => InkWell(
          onTap: enabled ? f : null,
          child: SizedBox(
            width: 44,
            height: 56,
            child: Center(
              child: Text(t, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w300, color: enabled ? Sumi.ink : Sumi.faint)),
            ),
          ),
        );
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Sumi.porcelain,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3733)),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Row(children: [
          seg('−', onMinus),
          Expanded(
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: Color(0xFF2C2A27)), right: BorderSide(color: Color(0xFF2C2A27))),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(value, style: serif(22, color: enabled ? Sumi.ink : Sumi.faint, height: 1)),
                  const SizedBox(height: 2),
                  FittedBox(child: SumiLabel(unit, size: 8)),
                ]),
              ),
            ),
          ),
          seg('+', onPlus),
        ]),
      ),
    );
  }

  Widget _prBadge(String text) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        decoration: BoxDecoration(
          color: Sumi.sheet,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Sumi.ink),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: Row(children: [
          const InkSeal('PR', size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('New personal record', style: serif(20)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(fontSize: 12.5, color: Sumi.ink2)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _restOverlay() {
    String next = '';
    if (_blocks.isNotEmpty) {
      final b = _blocks[_index.clamp(0, _blocks.length - 1)];
      final n = b.nextUndone;
      if (n != null) {
        final r = b.rows[n];
        next = 'Next: set ${n + 1}, ${r.weight > 0 ? '${fmtW(r.weight)} kg × ' : ''}${r.reps}';
      } else if (_index < _blocks.length - 1) {
        next = 'Next: ${_blocks[_index + 1].name}';
      } else {
        next = 'Last set done. Tap Finish when you are ready.';
      }
    }
    return Stack(children: [
      const Positioned.fill(child: AppBackground()),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(children: [
            Row(children: [const SumiLabel('Rest'), const Spacer(), SumiLabel(_fmt(_elapsed))]),
            const Spacer(),
            Enso(
              value: _restTotal <= 0 ? 0.0 : 1 - _restLeft / _restTotal,
              size: 236,
              stroke: 12,
              seed: 7,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_fmt(Duration(seconds: _restLeft)), style: serif(58, height: 1)),
                const SizedBox(height: 6),
                SumiLabel('of ${_fmt(Duration(seconds: _restTotal))}', size: 8.5),
              ]),
            ),
            const SizedBox(height: 18),
            Text('Breathe in. Breathe out.', style: serif(18, italic: true, color: Sumi.muted)),
            const SizedBox(height: 8),
            Text(next, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: Sumi.ink2)),
            const Spacer(),
            Row(children: [
              SizedBox(
                width: 84,
                child: OutlinedButton(
                  onPressed: () => setState(() => _restLeft = math.max(0, _restLeft - 15)),
                  child: const Text('−15 s'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(() => _restLeft = 0),
                  child: const Text('Skip rest'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 84,
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _restLeft += 15;
                    if (_restLeft > _restTotal) _restTotal = _restLeft;
                  }),
                  child: const Text('+15 s'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }
}

/// Shown after finishing a workout: XP earned, records, level and seals.
class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({super.key, required this.summary, required this.reward});
  final SessionSummary summary;
  final SessionReward reward;

  @override
  Widget build(BuildContext context) {
    final g = reward.state;
    return Scaffold(
      backgroundColor: Sumi.paper,
      body: Stack(children: [
        const Positioned.fill(child: AppBackground()),
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
            children: [
              Row(children: [
                SumiLabel('${summary.routineName} · complete'),
                const Spacer(),
                SumiLabel(prettyDay(summary.date)),
              ]),
              const SizedBox(height: 26),
              Center(
                child: Enso(
                  value: 0.97,
                  size: 230,
                  stroke: 13,
                  seed: summary.id,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(fmtInt(summary.volume), style: serif(44, height: 1)),
                    const SizedBox(height: 4),
                    const SumiLabel('kg lifted', size: 8.5),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              Center(child: Text('Well done.', style: serif(40))),
              const SizedBox(height: 4),
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: reward.xp.toDouble()),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text('+${v.round()} xp',
                      style: const TextStyle(fontSize: 14, color: Sumi.muted, letterSpacing: 0.6)),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Sumi.edge), bottom: BorderSide(color: Sumi.edge)),
                ),
                child: Row(children: [
                  _stat('Sets', '${summary.sets}'),
                  Container(width: 1, height: 54, color: Sumi.edge),
                  _stat('Minutes', '${summary.durationMin}'),
                  Container(width: 1, height: 54, color: Sumi.edge),
                  _stat('Kcal', '${summary.kcalBurned.round()}'),
                ]),
              ),
              const SizedBox(height: 22),
              if (reward.leveledUp)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(children: [
                    InkSeal('LV\n${g.level}', size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Level ${g.level}', style: serif(24)),
                        Text('New title: ${g.title}', style: const TextStyle(fontSize: 13, color: Sumi.ink2)),
                      ]),
                    ),
                  ]),
                ),
              Row(children: [
                Text('Level ${g.level} · ${g.title}', style: serif(20)),
                const Spacer(),
                Text('${g.xpToNext} xp to go', style: const TextStyle(fontSize: 11.5, color: Sumi.muted)),
              ]),
              const SizedBox(height: 10),
              AnimatedBar(value: g.levelProgress, color: Sumi.ink, height: 4),
              if (reward.prs.isNotEmpty) ...[
                const SectionHeader(title: 'New records'),
                for (final name in reward.prs)
                  SumiRow(
                    title: name,
                    subtitle: 'Best estimated max ever',
                    trailing: const InkSeal('PR', size: 36),
                  ),
              ],
              if (g.newBadges.isNotEmpty) ...[
                const SectionHeader(title: 'Seals earned'),
                for (final b in g.newBadges)
                  SumiRow(
                    title: b.name,
                    subtitle: b.description,
                    trailing: InkSeal(b.name.split(' ').take(2).join('\n'), size: 40),
                  ),
              ],
              const SizedBox(height: 18),
              Text('Your calorie target already accounts for training days.',
                  textAlign: TextAlign.center, style: serif(15, italic: true, color: Sumi.muted)),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Done', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(children: [
          SumiLabel(label, size: 9),
          const SizedBox(height: 2),
          Text(value, style: serif(26)),
        ]),
      ),
    );
  }
}
