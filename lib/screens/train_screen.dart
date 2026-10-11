import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../util.dart';
import '../widgets.dart';
import 'session_screen.dart';
import 'workout_screen.dart';

const _routineGradients = <List<Color>>[
  [Color(0xFFF4A259), Color(0xFFE76F51)],
  [Color(0xFF7FB2F0), Color(0xFF5A67D8)],
  [Color(0xFF6FCF97), Color(0xFF2F855A)],
  [Color(0xFFB794F6), Color(0xFF805AD5)],
  [Color(0xFFF687B3), Color(0xFFD53F8C)],
  [Color(0xFF4FD1C5), Color(0xFF2C7A7B)],
];

List<Color> routineGradient(Routine r) => _routineGradients[(r.id ?? 0).abs() % _routineGradients.length];

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
            Row(children: [
              CircleAvatar(radius: 8, backgroundColor: muscleColor(muscle)),
              const SizedBox(width: 10),
              Text(muscle, style: theme.textTheme.titleLarge),
            ]),
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
                  leading: CircleAvatar(backgroundColor: routineGradient(r).first, child: const Icon(Icons.fitness_center, size: 18)),
                  title: Text(r.name),
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
        icon: const Icon(Icons.bolt),
        label: const Text('Quick workout'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    _weekHeader(),
                    const SizedBox(height: 14),
                    if (_upNext != null) _upNextCard(_upNext!),
                    const SizedBox(height: 14),
                    _recoveryCard(),
                    SectionHeader(
                      title: 'Your routines',
                      trailing: TextButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('New')),
                    ),
                    _routineCarousel(),
                    const SectionHeader(title: 'History'),
                    if (_history.isEmpty) const EmptyNote('Your finished workouts show up here as a timeline.'),
                    ..._timeline(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _weekHeader() {
    final theme = Theme.of(context);
    final ws = weekStartKey();
    final week = _history.where((s) => s.date.compareTo(ws) >= 0).toList();
    final volume = week.fold<double>(0, (a, s) => a + s.volume);
    final sets = week.fold<int>(0, (a, s) => a + s.sets);
    final minutes = week.fold<int>(0, (a, s) => a + s.durationMin);
    final n = week.length;
    final done = n >= _weekTarget;
    return Row(children: [
      AnimatedRing(
        value: n / _weekTarget,
        color: done ? goodColor : theme.colorScheme.primary,
        size: 104,
        stroke: 10,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$n/$_weekTarget', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          Text('this week', style: theme.textTheme.labelSmall),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Train', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text(
            done ? 'Weekly goal smashed. Extra sessions are a bonus.' : '${_weekTarget - n} more to hit your weekly goal.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(children: [
            _miniStat(Icons.fitness_center, fmtInt(volume), 'kg'),
            _miniStat(Icons.format_list_numbered, '$sets', 'sets'),
            _miniStat(Icons.timer_outlined, '$minutes', 'min'),
          ]),
        ]),
      ),
    ]);
  }

  Widget _miniStat(IconData icon, String value, String unit) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        Text(unit, style: theme.textTheme.labelSmall),
      ]),
    );
  }

  Widget _upNextCard(Routine r) {
    final g = routineGradient(r);
    final muscles = routineMuscles(r);
    const ink = Color(0xFF1B1F27);
    return GestureDetector(
      onTap: () => _start(r),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Stack(children: [
          Positioned(
            right: -10,
            bottom: -18,
            child: Icon(Icons.fitness_center, size: 120, color: Colors.white.withAlpha(40)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withAlpha(70), borderRadius: BorderRadius.circular(12)),
                child: const Text('UP NEXT', style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 11)),
              ),
              const Spacer(),
              Text(_ago(_lastDone[r.id]), style: const TextStyle(color: ink, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 12),
            Text(r.name, style: const TextStyle(color: ink, fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${r.items.length} exercises  |  about ${estMinutes(r)} min',
                style: const TextStyle(color: ink, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in muscles)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withAlpha(40), borderRadius: BorderRadius.circular(12)),
                  child: Text(m, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white, minimumSize: const Size(0, 48)),
                onPressed: () => _start(r),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('Start ${r.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _recoveryCard() {
    final theme = Theme.of(context);
    final muscles = muscleColors.keys.toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Muscle recovery', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text('Tap a muscle', style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _legend(fireColor, 'Recovering'),
            _legend(goodColor, 'Ready'),
            _legend(infoColor, 'Due'),
          ]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final w = ((c.maxWidth - 16) / 3).floorToDouble();
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in muscles) _muscleChip(m, w),
            ]);
          }),
        ]),
      ),
    );
  }

  Widget _legend(Color c, String t) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(t, style: Theme.of(context).textTheme.labelSmall),
        ]),
      );

  Widget _muscleChip(String m, double width) {
    final theme = Theme.of(context);
    final last = _muscleLast[m];
    final days = last == null ? null : daysBetween(parseDay(last), DateTime.now());
    final Color state;
    final String label;
    final double fresh; // 0 = just trained, 1 = fully rested
    if (days == null) {
      state = infoColor;
      label = 'New';
      fresh = 1;
    } else if (days <= 1) {
      state = fireColor;
      label = days == 0 ? 'Today' : '1d';
      fresh = days == 0 ? 0.15 : 0.5;
    } else if (days <= 4) {
      state = goodColor;
      label = '${days}d';
      fresh = 1;
    } else {
      state = infoColor;
      label = '${days}d';
      fresh = 1;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _muscleSheet(m),
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: state.withAlpha(28),
          border: Border.all(color: state.withAlpha(110)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: muscleColor(m), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(child: Text(m, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium)),
          ]),
          const SizedBox(height: 6),
          AnimatedBar(value: fresh, color: state, height: 5),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: state, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _routineCarousel() {
    final theme = Theme.of(context);
    return SizedBox(
      height: 196,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          for (final r in _routines) _routineCard(r),
          GestureDetector(
            onTap: () => _edit(),
            child: Container(
              width: 150,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.colorScheme.outline, width: 1.5),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_circle_outline, size: 36, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                const Text('New routine'),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _routineCard(Routine r) {
    final theme = Theme.of(context);
    final g = routineGradient(r);
    final muscles = routineMuscles(r);
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _edit(r),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              height: 64,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(gradient: LinearGradient(colors: g)),
              child: Row(children: [
                Expanded(
                  child: Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF1B1F27), fontSize: 20, fontWeight: FontWeight.w900)),
                ),
                const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF1B1F27)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r.items.length} exercises  |  ~${estMinutes(r)} min', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Row(children: [
                  for (final m in muscles.take(5))
                    Tooltip(
                      message: m,
                      child: Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(color: muscleColor(m), shape: BoxShape.circle),
                      ),
                    ),
                  if (muscles.length > 5) Text('+${muscles.length - 5}', style: theme.textTheme.labelSmall),
                ]),
                const SizedBox(height: 6),
                Text(_ago(_lastDone[r.id]), style: theme.textTheme.labelSmall),
              ]),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => _start(r),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Start'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _timeline() {
    final theme = Theme.of(context);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final maxVol = _history.fold<double>(1, (a, s) => math.max(a, s.volume));
    final out = <Widget>[];
    for (var i = 0; i < _history.length; i++) {
      final s = _history[i];
      final d = parseDay(s.date);
      final prs = _prs[s.id] ?? 0;
      out.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 48,
            child: Column(children: [
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  Text('${d.day}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  Text(months[d.month - 1], style: theme.textTheme.labelSmall),
                ]),
              ),
              if (i < _history.length - 1)
                Expanded(child: Container(width: 2, color: theme.colorScheme.outlineVariant)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openSession(s),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(s.routineName, style: theme.textTheme.titleSmall)),
                      if (prs > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: warnColor.withAlpha(40), borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.emoji_events, size: 14, color: warnColor),
                            const SizedBox(width: 4),
                            Text('$prs PR${prs > 1 ? 's' : ''}',
                                style: const TextStyle(color: warnColor, fontSize: 12, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    AnimatedBar(value: s.volume / maxVol, color: theme.colorScheme.primary, height: 6),
                    const SizedBox(height: 6),
                    Text('${fmtInt(s.volume)} kg  |  ${s.sets} sets  |  ${s.durationMin} min',
                        style: theme.textTheme.bodySmall),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ));
    }
    return out;
  }
}
