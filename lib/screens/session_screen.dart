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

const _ink = Color(0xFF1B1F27);

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

List<Color> _gradientFor(String muscle) {
  final c = muscleColor(muscle);
  final hsl = HSLColor.fromColor(c);
  return [c, hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor()];
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
  final _confetti = ConfettiController();
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
    _confetti.dispose();
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
    _confetti.burst();
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
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _confetti.burst();
    });
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
          context, 'No sets completed', 'Tap "Complete set" after each set you finish. Discard this workout?', 'Discard');
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
        backgroundColor: const Color(0xFF121820),
        body: Stack(children: [
          const Positioned.fill(child: AppBackground()),
          SafeArea(
            child: Column(children: [
              _topBar(),
              if (_ready && _blocks.isNotEmpty) _exerciseStrip(),
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
          Positioned.fill(child: ConfettiLayer(controller: _confetti)),
          if (_prText != null) Positioned(left: 20, right: 20, top: 110, child: _prBadge(_prText!)),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: IgnorePointer(
              ignoring: _restLeft == 0,
              child: AnimatedSlide(
                offset: _restLeft > 0 ? Offset.zero : const Offset(0, 1.6),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                child: _restPanel(),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _topBar() {
    final theme = Theme.of(context);
    var total = 0, done = 0;
    for (final b in _blocks) {
      total += b.rows.length;
      done += b.doneCount;
    }
    final pct = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Leave workout',
          onPressed: () => Navigator.maybePop(context),
        ),
        AnimatedRing(
          value: pct,
          color: pct >= 1 ? goodColor : theme.colorScheme.primary,
          size: 44,
          stroke: 5,
          child: Text('${(pct * 100).round()}', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.routine.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text('${_fmt(_elapsed)}  |  $done/$total sets', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ]),
        ),
        IconButton(icon: const Icon(Icons.add), tooltip: 'Add exercise', onPressed: _pickExercise),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: pct >= 1 ? goodColor : null),
          onPressed: _saving ? null : _finish,
          child: const Text('Finish'),
        ),
      ]),
    );
  }

  Widget _exerciseStrip() {
    return SizedBox(
      height: 46,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _blocks.length,
        itemBuilder: (context, i) {
          final b = _blocks[i];
          final c = muscleColor(b.muscle);
          final active = i == _index;
          final frac = b.rows.isEmpty ? 0.0 : b.doneCount / b.rows.length;
          return GestureDetector(
            onTap: () => _page.animateToPage(i, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                color: active ? c.withAlpha(60) : Colors.white.withAlpha(14),
                border: Border.all(color: active ? c : Colors.transparent, width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: b.complete
                      ? const Icon(Icons.check_circle, size: 18, color: goodColor)
                      : CircularProgressIndicator(value: frac, strokeWidth: 3, color: c, backgroundColor: c.withAlpha(50)),
                ),
                const SizedBox(width: 8),
                Text(b.name, style: TextStyle(fontWeight: active ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          LiftFigure(kind: LiftKind.press, color: theme.colorScheme.primary, size: 160),
          const SizedBox(height: 16),
          Text('Quick workout', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Add your first exercise to get going.', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          GradientButton(label: 'Add exercise', icon: Icons.add, onPressed: _pickExercise),
        ]),
      ),
    );
  }

  Widget _exercisePage(_Block b) {
    final theme = Theme.of(context);
    final g = _gradientFor(b.muscle);
    final c = muscleColor(b.muscle);
    final row = b.rows.isEmpty ? null : b.rows[b.selected.clamp(0, b.rows.length - 1)];
    final setNo = b.selected + 1;
    final prev = b.selected < b.last.length ? b.last[b.selected] : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
      children: [
        // Hero
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: g.last.withAlpha(90), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(80), borderRadius: BorderRadius.circular(10)),
                  child: Text(b.muscle.toUpperCase(),
                      style: const TextStyle(color: _ink, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                ),
                const SizedBox(height: 10),
                Text(b.name, style: const TextStyle(color: _ink, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(height: 6),
                Text(
                  b.complete ? 'All ${b.rows.length} sets done!' : 'Set $setNo of ${b.rows.length}  |  ${b.repMin}-${b.repMax} reps',
                  style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            Stack(alignment: Alignment.center, children: [
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(50)),
              ),
              LiftFigure(kind: liftKindFor(b.name, b.muscle), color: _ink, size: 120),
              if (b.complete)
                const CircleAvatar(radius: 26, backgroundColor: goodColor, child: Icon(Icons.check, color: _ink, size: 32)),
            ]),
          ]),
        ),
        if (b.suggestion != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.auto_graph, color: c, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(b.suggestion!.text, style: theme.textTheme.bodySmall)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        // Set bubbles
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var i = 0; i < b.rows.length; i++) _setBubble(b, i, c),
          GestureDetector(
            onTap: () => _addSet(b),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1.5)),
              child: const Icon(Icons.add, size: 20),
            ),
          ),
          if (b.rows.length > 1)
            TextButton(onPressed: () => _removeSet(b), child: const Text('Remove set')),
        ]),
        const SizedBox(height: 16),
        if (row != null) ...[
          Row(children: [
            Expanded(
              child: _stepper(
                label: 'WEIGHT',
                value: row.weight <= 0 ? 'BW' : fmtW(row.weight),
                unit: row.weight <= 0 ? 'bodyweight' : 'kg',
                color: c,
                enabled: !row.done,
                onMinus: () => _nudge(row, weight: -2.5),
                onPlus: () => _nudge(row, weight: 2.5),
                onTap: () => _typeValue(row, weight: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _stepper(
                label: 'REPS',
                value: '${row.reps}',
                unit: 'target ${b.repMin}-${b.repMax}',
                color: c,
                enabled: !row.done,
                onMinus: () => _nudge(row, reps: -1),
                onPlus: () => _nudge(row, reps: 1),
                onTap: () => _typeValue(row, weight: false),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Center(
            child: Text(
              prev == null
                  ? 'First time doing this set. Pick a weight with 1-2 reps in reserve.'
                  : 'Last time: ${prev.weight > 0 ? '${fmtW(prev.weight)} kg x ' : ''}${prev.reps} reps',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          row.done
              ? OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => _complete(b),
                  icon: const Icon(Icons.undo),
                  label: Text('Undo set $setNo'),
                )
              : GradientButton(
                  label: 'Complete set $setNo',
                  icon: Icons.check_rounded,
                  colors: g,
                  onPressed: () => _complete(b),
                ),
        ],
        if (b.doneCount > 0) ...[
          const SizedBox(height: 20),
          Text('Done', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < b.rows.length; i++)
              if (b.rows[i].done)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: c.withAlpha(35), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    'Set ${i + 1}: ${b.rows[i].weight > 0 ? '${fmtW(b.rows[i].weight)} x ' : ''}${b.rows[i].reps}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
          ]),
        ],
      ],
    );
  }

  Widget _setBubble(_Block b, int i, Color c) {
    final row = b.rows[i];
    final selected = i == b.selected;
    Widget inner = Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800));
    if (row.done) {
      return GestureDetector(
        onTap: () => setState(() => b.selected = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c,
            border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
          ),
          child: const Icon(Icons.check, color: _ink, size: 22),
        ),
      );
    }
    if (selected) {
      return PulseCircle(color: c, child: inner);
    }
    return GestureDetector(
      onTap: () => setState(() => b.selected = i),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.withAlpha(110), width: 1.5)),
        child: inner,
      ),
    );
  }

  Widget _stepper({
    required String label,
    required String value,
    required String unit,
    required Color color,
    required bool enabled,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    Widget btn(IconData icon, VoidCallback f) => Material(
          color: enabled ? color.withAlpha(45) : Colors.white10,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? f : null,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, color: enabled ? color : Colors.white38)),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withAlpha(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Text(value,
                key: ValueKey(value),
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: enabled ? Colors.white : Colors.white54)),
          ),
        ),
        Text(unit, style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          btn(Icons.remove, onMinus),
          btn(Icons.add, onPlus),
        ]),
      ]),
    );
  }

  Widget _prBadge(String text) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFFF2C94C), Color(0xFFF4A259)]),
          boxShadow: const [BoxShadow(color: Color(0x88F2C94C), blurRadius: 30)],
        ),
        child: Row(children: [
          const Text('🏆', style: TextStyle(fontSize: 34)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('NEW PERSONAL RECORD!', style: TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 16)),
              Text(text, style: const TextStyle(color: _ink, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _restPanel() {
    final theme = Theme.of(context);
    String next = '';
    if (_blocks.isNotEmpty) {
      final b = _blocks[_index.clamp(0, _blocks.length - 1)];
      final n = b.nextUndone;
      if (n != null) {
        final r = b.rows[n];
        next = 'Next: set ${n + 1}, ${r.weight > 0 ? '${fmtW(r.weight)} kg x ' : ''}${r.reps}';
      } else if (_index < _blocks.length - 1) {
        next = 'Next: ${_blocks[_index + 1].name}';
      } else {
        next = 'Last set done. Tap Finish!';
      }
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: const Color(0xFF243447),
        border: Border.all(color: Colors.white.withAlpha(25)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(children: [
        AnimatedRing(
          value: _restTotal <= 0 ? 0 : _restLeft / _restTotal,
          color: infoColor,
          size: 76,
          stroke: 7,
          child: Text(_fmt(Duration(seconds: _restLeft)),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rest & breathe', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(next, style: theme.textTheme.bodySmall, maxLines: 2),
            const SizedBox(height: 8),
            Row(children: [
              _restChip('-15s', () => setState(() => _restLeft = math.max(0, _restLeft - 15))),
              _restChip('+15s', () => setState(() {
                    _restLeft += 15;
                    if (_restLeft > _restTotal) _restTotal = _restLeft;
                  })),
              _restChip('Skip', () => setState(() => _restLeft = 0)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _restChip(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
}

/// Shown after finishing a workout: XP earned, records, level and badges, with confetti.
class SessionSummaryScreen extends StatefulWidget {
  const SessionSummaryScreen({super.key, required this.summary, required this.reward});
  final SessionSummary summary;
  final SessionReward reward;

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  final _confetti = ConfettiController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confetti.burst();
      HapticFeedback.mediumImpact();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = widget.summary;
    final reward = widget.reward;
    final g = reward.state;
    return Scaffold(
      backgroundColor: const Color(0xFF121820),
      body: Stack(children: [
        const Positioned.fill(child: AppBackground()),
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (context, s, child) => Transform.scale(scale: s, child: child),
                  child: Container(
                    width: 110,
                    height: 110,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFFF2C94C), Color(0xFFF4A259)]),
                      boxShadow: const [BoxShadow(color: Color(0x88F4A259), blurRadius: 40)],
                    ),
                    child: const Text('💪', style: TextStyle(fontSize: 56)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(child: Text('${summary.routineName} complete!',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
              const SizedBox(height: 6),
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: reward.xp.toDouble()),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(
                    '+${v.round()} XP',
                    style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w900, color: xpColor),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (reward.leveledUp)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(colors: [Color(0xFFB794F6), Color(0xFF805AD5)]),
                  ),
                  child: Row(children: [
                    const Icon(Icons.keyboard_double_arrow_up, color: _ink, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Level up! Level ${g.level}',
                            style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w900)),
                        Text('New title: ${g.title}', style: const TextStyle(color: _ink)),
                      ]),
                    ),
                  ]),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Level ${g.level}', style: theme.textTheme.titleMedium),
                      const SizedBox(width: 8),
                      Text(g.title, style: theme.textTheme.bodyMedium?.copyWith(color: xpColor)),
                      const Spacer(),
                      Text('${g.xpToNext} XP to go', style: theme.textTheme.bodySmall),
                    ]),
                    const SizedBox(height: 10),
                    AnimatedBar(value: g.levelProgress, color: xpColor, height: 12),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: StatTile(value: '${summary.sets}', label: 'sets', icon: Icons.format_list_numbered)),
                const SizedBox(width: 8),
                Expanded(child: StatTile(value: fmtInt(summary.volume), label: 'kg lifted', icon: Icons.fitness_center)),
                const SizedBox(width: 8),
                Expanded(child: StatTile(value: '${summary.durationMin}', label: 'minutes', icon: Icons.timer_outlined)),
              ]),
              if (reward.prs.isNotEmpty) ...[
                const SectionHeader(title: 'New personal records'),
                for (final name in reward.prs)
                  Card(
                    child: ListTile(
                      leading: const Text('🏆', style: TextStyle(fontSize: 28)),
                      title: Text(name),
                      subtitle: const Text('Best estimated max ever'),
                      trailing: const XpPill(XpRules.pr, done: true),
                    ),
                  ),
              ],
              if (g.newBadges.isNotEmpty) ...[
                const SectionHeader(title: 'Badges unlocked'),
                for (final b in g.newBadges)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: xpColor, child: Icon(b.icon, color: _ink)),
                      title: Text(b.name),
                      subtitle: Text(b.description),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text('About ${summary.kcalBurned.round()} kcal burned. Your calorie target already accounts for training days.',
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              GradientButton(label: 'Done', icon: Icons.check_rounded, onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
        Positioned.fill(child: ConfettiLayer(controller: _confetti)),
      ]),
    );
  }
}
