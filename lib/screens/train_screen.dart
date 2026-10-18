import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../util.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'session_screen.dart';
import 'workout_screen.dart';

/// Kept for compatibility with older code: routines no longer have colours in the Sumi design.
List<Color> routineGradient(Routine r) => const [Sumi.ink, Sumi.ink2];

int estMinutes(Routine r) => math.max(10, (r.items.fold<int>(0, (a, i) => a + i.sets) * 2.5).round());

List<String> routineMuscles(Routine r) {
  final seen = <String>[];
  for (final i in r.items) {
    if (!seen.contains(i.muscle)) seen.add(i.muscle);
  }
  return seen;
}

String _ago(String? date) {
  if (date == null) return 'Not done yet';
  final d = daysBetween(parseDay(date), DateTime.now());
  if (d <= 0) return 'Done today';
  if (d == 1) return 'Done yesterday';
  return 'Done $d days ago';
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  List<Routine> _routines = [];
  List<SessionSummary> _history = [];
  Map<int, String> _lastDone = {};
  Map<String, String> _muscleLast = {};
  Map<int, int> _prs = {};
  int _weekTarget = 3;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final r = await db.routines();
    final h = await db.recentSessions(limit: 40);
    final last = await db.routineLastDone();
    final muscles = await db.muscleLastTrained();
    final prs = await db.prCountsBySession();
    final per4w = await db.sessionCountSince(daysAgoKey(28));
    if (!mounted) return;
    setState(() {
      _routines = r;
      _history = h;
      _lastDone = last;
      _muscleLast = muscles;
      _prs = prs;
      _weekTarget = math.max(3, math.min(6, (per4w / 4).round()));
      _loading = false;
    });
  }

  /// The routine you've gone longest without doing (never-done routines first).
  Routine? get _upNext {
    if (_routines.isEmpty) return null;
    final sorted = [..._routines]..sort((a, b) {
        final da = _lastDone[a.id] ?? '';
        final db = _lastDone[b.id] ?? '';
        return da.compareTo(db);
      });
    return sorted.first;
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

  void _muscleSheet(String muscle) {
    final theme = Theme.of(context);
    final matches = _routines.where((r) => r.items.any((i) => i.muscle == muscle)).toList();
    final last = _muscleLast[muscle];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(muscle, style: serif(30)),
            const SizedBox(height: 4),
            Text(last == null ? 'Not trained yet.' : 'Last trained ${prettyDay(last).toLowerCase()}.',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (matches.isEmpty)
              const Text('None of your routines train this muscle yet. Add an exercise to a routine.')
            else
              for (final r in matches)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.name, style: serif(20)),
                  subtitle: Text(r.items.where((i) => i.muscle == muscle).map((i) => i.exerciseName).join(', ')),
                  trailing: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _start(r);
                    },
                    child: const Text('Start'),
                  ),
                ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _start(Routine(name: 'Quick workout')),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Quick workout'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 100),
                  children: [
                    _weekHeader(),
                    const SizedBox(height: 22),
                    if (_upNext != null) _upNextCard(_upNext!),
                    const SizedBox(height: 8),
                    SectionHeader(
                      title: 'Routines',
                      trailing: TextButton(onPressed: () => _edit(), child: const Text('+ New')),
                    ),
                    _routineList(),
                    const SizedBox(height: 10),
                    _recoveryCard(),
                    const SectionHeader(title: 'History'),
                    if (_history.isEmpty) const EmptyNote('Your finished workouts appear here.'),
                    ..._timeline(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _weekHeader() {
    final ws = weekStart(DateTime.now());
    final wsKey = weekStartKey();
    final today = todayKey();
    final week = _history.where((s) => s.date.compareTo(wsKey) >= 0).toList();
    final trainedDays = week.map((s) => s.date).toSet();
    final volume = week.fold<double>(0, (a, s) => a + s.volume);
    final sets = week.fold<int>(0, (a, s) => a + s.sets);
    final minutes = week.fold<int>(0, (a, s) => a + s.durationMin);
    final n = week.length;
    final done = n >= _weekTarget;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SumiLabel('Train · $n of $_weekTarget this week'),
      const SizedBox(height: 8),
      Text('Train', style: serif(42)),
      const SizedBox(height: 4),
      Text(
        done ? 'Weekly goal reached. Extra sessions are a bonus.' : '${_weekTarget - n} more to reach your weekly goal.',
        style: serif(16, italic: true, color: Sumi.muted),
      ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final key = dayKey(DateTime(ws.year, ws.month, ws.day + i));
            return Column(children: [
              SumiLabel(weekdayShort[i].substring(0, 1), color: key == today ? Sumi.ink : Sumi.muted),
              const SizedBox(height: 6),
              Enso(value: trainedDays.contains(key) ? 1.0 : 0.0, size: 32, stroke: 3.8, seed: i),
            ]);
          }),
      ]),
      const SizedBox(height: 16),
      Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Sumi.rule), bottom: BorderSide(color: Sumi.rule)),
        ),
        child: Row(children: [
          _miniStat(fmtInt(volume), 'kg'),
          _miniStat('$sets', 'sets'),
          _miniStat('$minutes', 'min'),
        ]),
      ),
    ]);
  }

  Widget _miniStat(String value, String unit) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(children: [
          SumiLabel(unit, size: 9),
          const SizedBox(height: 2),
          Text(value, style: serif(24)),
        ]),
      ),
    );
  }

  Widget _upNextCard(Routine r) {
    return SumiCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      onTap: () => _start(r),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SumiLabel('Up next'),
          const Spacer(),
          Text(_ago(_lastDone[r.id]), style: const TextStyle(fontSize: 11.5, color: Sumi.muted)),
        ]),
        const SizedBox(height: 8),
        Text(r.name, style: serif(32)),
        const SizedBox(height: 4),
        Text(
          r.items.isEmpty ? 'No exercises yet' : r.items.map((i) => i.exerciseName).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Sumi.muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: () => _start(r), child: Text('Begin ${r.name}')),
        ),
      ]),
    );
  }

  Widget _routineList() {
    if (_routines.isEmpty) {
      return const EmptyNote('No routines yet. Tap "+ New" to make your first one.');
    }
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Sumi.rule))),
      child: Column(children: [
        for (final r in _routines)
          SumiRow(
            title: r.name,
            subtitle: '${r.items.length} exercises · about ${estMinutes(r)} min · ${_ago(_lastDone[r.id]).toLowerCase()}',
            onTap: () => _edit(r),
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 16)),
              onPressed: () => _start(r),
              child: const Text('Start'),
            ),
          ),
      ]),
    );
  }

  Widget _recoveryCard() {
    final muscles = muscleColors.keys.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Recovery', style: serif(26)),
          const Spacer(),
          const Text('tap a muscle', style: TextStyle(fontSize: 11, color: Sumi.muted)),
        ]),
      ),
      const Text('A full circle means rested and ready.', style: TextStyle(fontSize: 12, color: Sumi.muted)),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final w = ((c.maxWidth - 16) / 3).floorToDouble();
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in muscles) _muscleChip(m, w),
        ]);
      }),
    ]);
  }

  Widget _muscleChip(String m, double width) {
    final last = _muscleLast[m];
    final days = last == null ? null : daysBetween(parseDay(last), DateTime.now());
    final String label;
    final double fresh; // 0 = just trained, 1 = fully rested
    if (days == null) {
      label = 'not trained';
      fresh = 1;
    } else if (days <= 1) {
      label = days == 0 ? 'today' : 'yesterday';
      fresh = days == 0 ? 0.15 : 0.5;
    } else if (days <= 4) {
      label = '$days days · ready';
      fresh = 1;
    } else {
      label = '$days days · due';
      fresh = 1;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _muscleSheet(m),
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Sumi.porcelain.withAlpha(170),
          border: Border.all(color: Sumi.rule),
        ),
        child: Row(children: [
          Enso(value: fresh, size: 26, stroke: 3, seed: m.length),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
              Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Sumi.muted)),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _timeline() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final maxVol = _history.fold<double>(1, (a, s) => math.max(a, s.volume));
    final out = <Widget>[];
    for (final s in _history) {
      final d = parseDay(s.date);
      final prs = _prs[s.id] ?? 0;
      out.add(InkWell(
        onTap: () => _openSession(s),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Sumi.rule))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 46,
              child: Column(children: [
                Text('${d.day}', style: serif(26, height: 1)),
                SumiLabel(months[d.month - 1], size: 9),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.routineName, style: serif(20)),
                const SizedBox(height: 8),
                AnimatedBar(value: s.volume / maxVol, color: Sumi.ink, height: 3),
                const SizedBox(height: 6),
                Text('${fmtInt(s.volume)} kg · ${s.sets} sets · ${s.durationMin} min',
                    style: const TextStyle(fontSize: 11.5, color: Sumi.muted)),
              ]),
            ),
            if (prs > 0) ...[
              const SizedBox(width: 10),
              InkSeal(prs > 1 ? '$prs\nPRs' : 'PR', size: 38),
            ],
          ]),
        ),
      ));
    }
    return out;
  }
}
