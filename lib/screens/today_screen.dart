import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import '../game.dart';
import '../models.dart';
import '../planner.dart';
import '../report.dart';
import '../session.dart';
import '../social.dart';
import '../util.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'game_screen.dart';
import 'me_screen.dart';
import 'report_screen.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  PlanSnapshot? _plan;
  GameState? _game;
  WeeklyReport? _report;
  Macros _eaten = Macros.zero;
  DayValue? _latestWeight;
  Map<String, int> _weekXp = {};
  Set<String> _trainedDays = {};
  bool _showEaten = false;
  int _gameBest = 0;
  int _weekTarget = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final today = todayKey();
    final game = await Game.refresh();
    Social.instance.syncQuietly(game);
    final plan = await loadPlan(today);
    final eaten = await db.totalsFor(today);
    final report = await buildReport(plan, streak: game.streak);
    final latest = await db.latestWeight();
    final ws = weekStartKey();
    final weekXp = await db.xpByDay(ws);
    final trained = (await db.sessionDatesSince(ws)).toSet();
    final gameBest = int.tryParse(await db.getMeta('game_best') ?? '') ?? 0;
    final per4w = await db.sessionCountSince(daysAgoKey(28));
    if (!mounted) return;
    setState(() {
      _gameBest = gameBest;
      _weekTarget = math.max(3, math.min(6, (per4w / 4).round()));
      _plan = plan;
      _game = game;
      _report = report;
      _eaten = eaten;
      _latestWeight = latest;
      _weekXp = weekXp;
      _trainedDays = trained;
    });
    for (final b in game.newBadges) {
      if (!mounted) return;
      await showBadgeUnlocked(context, b.name, b.description, b.icon);
    }
  }

  Future<void> _logWeight() async {
    final v = await askNumber(context,
        title: "Today's weight", initial: _latestWeight == null ? null : fmtW(_latestWeight!.value), suffix: 'kg');
    if (v == null || v < 30 || v > 300) return;
    await AppDb.instance.logWeight(todayKey(), v);
    await _load();
  }

  Future<void> _setPlanned(bool v) async {
    await AppDb.instance.setPlannedTraining(todayKey(), v);
    await _load();
  }

  Future<void> _openMe() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MeScreen()));
    await _load();
  }

  Future<void> _showDay(String date) async {
    final db = AppDb.instance;
    final totals = await db.totalsFor(date);
    final events = await db.xpEventsFor(date);
    final trained = await db.trainedOn(date);
    if (!mounted) return;
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(prettyDay(date), style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: StatTile(value: fmtInt(totals.kcal), label: 'kcal eaten', icon: Icons.local_dining)),
            const SizedBox(width: 8),
            Expanded(
                child: StatTile(value: '${totals.protein.round()} g', label: 'protein', icon: Icons.egg_outlined)),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                value: trained ? 'Yes' : 'No',
                label: 'workout',
                icon: Icons.fitness_center,
                color: trained ? goodColor : null,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text('No XP earned on this day.', style: theme.textTheme.bodyMedium)
          else
            for (final e in events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(e.label)),
                  XpPill(e.xp, done: true),
                ]),
              ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final game = _game;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: plan == null || game == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
                  children: [
                    _header(plan, game),
                    const SizedBox(height: 22),
                    _rings(plan),
                    const SizedBox(height: 18),
                    _legend(plan),
                    _planNote(plan),
                    const SizedBox(height: 18),
                    _actions(),
                    const SizedBox(height: 28),
                    _weekStrip(),
                    const SizedBox(height: 28),
                    _questsCard(game),
                    const SizedBox(height: 24),
                    _levelCard(game),
                    const SizedBox(height: 24),
                    GymDashCard(best: _gameBest, onPlayed: _load),
                    const SizedBox(height: 16),
                    if (_report != null) _reportTeaser(_report!),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(PlanSnapshot plan, GameState game) {
    final me = AppSession.instance.me;
    final name = plan.profile.name.isNotEmpty ? plan.profile.name : (me?.displayName ?? '');
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SumiLabel('${weekdayShort[now.weekday - 1]} · ${now.day} ${months[now.month - 1]}'),
          const SizedBox(height: 10),
          Text(
            firstName(name).isEmpty ? 'Ready to train?' : '${greeting()},\n${firstName(name)}',
            style: serif(34),
          ),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        GestureDetector(
          onTap: _openMe,
          child: Avatar(name: name.isEmpty ? '?' : name, color: me?.avatarColor ?? 0, size: 40, level: game.level),
        ),
        if (game.streak > 0) ...[
          const SizedBox(height: 10),
          Text('${game.streak} day streak', style: const TextStyle(fontSize: 11, color: Sumi.muted)),
        ],
      ]),
    ]);
  }

  double _ratio(double v, double t) => t <= 0 ? 0.0 : (v / t).clamp(0.0, 1.0).toDouble();

  Widget _rings(PlanSnapshot plan) {
    final t = plan.target;
    final remaining = t.kcal - _eaten.kcal;
    final over = remaining < 0;
    final big = _showEaten ? fmtInt(_eaten.kcal) : fmtInt(remaining.abs());
    final small = _showEaten ? 'KCAL EATEN' : (over ? 'KCAL OVER' : 'KCAL LEFT');
    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _showEaten = !_showEaten),
        child: TripleEnso(
          size: 264,
          values: [
            _ratio(_eaten.kcal, t.kcal),
            _ratio(_eaten.protein, t.protein),
            _ratio(_trainedDays.length.toDouble(), _weekTarget.toDouble()),
          ],
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Column(key: ValueKey(_showEaten), mainAxisSize: MainAxisSize.min, children: [
              Text(big, style: serif(34, color: over && !_showEaten ? Sumi.error : Sumi.ink)),
              const SizedBox(height: 4),
              SumiLabel(small, size: 8.5),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _legendRow(double thick, String name, String value, String of) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Sumi.rule))),
      child: Row(children: [
        BrushLine(width: 24, thickness: thick),
        const SizedBox(width: 12),
        Expanded(child: SumiLabel(name, size: 11)),
        Text(value, style: serif(22)),
        SizedBox(
          width: 74,
          child: Text(of, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, color: Sumi.muted)),
        ),
      ]),
    );
  }

  Widget _legend(PlanSnapshot plan) {
    final t = plan.target;
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Sumi.rule))),
      child: Column(children: [
        _legendRow(5, 'Eat', fmtInt(_eaten.kcal), 'of ${fmtInt(t.kcal)}'),
        _legendRow(3.6, 'Protein', '${_eaten.protein.round()} g', 'of ${t.protein.round()} g'),
        _legendRow(2.4, 'Train', '${_trainedDays.length}', 'of $_weekTarget days'),
      ]),
    );
  }

  Widget _planNote(PlanSnapshot plan) {
    final t = plan.target;
    final restDelta = (t.baseKcal - plan.restTarget.kcal).round();
    final note = plan.trainingDay && t.cycling
        ? 'Training day: +${trainingDayBonus.round()} kcal to fuel your session.'
        : t.cycling
            ? 'Rest day: $restDelta kcal lower so your week stays on plan.'
            : 'Eat about ${fmtInt(t.kcal)} kcal today to reach your goal.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Text(note, style: serif(16, italic: true, color: Sumi.muted, height: 1.3)),
      const SizedBox(height: 6),
      if (!plan.trained)
        Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Training today?', style: TextStyle(fontSize: 14.5)),
              Text('Adds training-day calories and a workout quest',
                  style: TextStyle(fontSize: 11.5, color: Sumi.muted)),
            ]),
          ),
          Switch(value: plan.planned, onChanged: _setPlanned),
        ])
      else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Workout done today.', style: TextStyle(fontSize: 14.5)),
        ),
    ]);
  }

  Widget _weekStrip() {
    final ws = weekStart(DateTime.now());
    final today = todayKey();
    final maxXp = _weekXp.values.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('This week', style: serif(26)),
        const Spacer(),
        Text('tap a day', style: const TextStyle(fontSize: 11, color: Sumi.muted)),
      ]),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final day = DateTime(ws.year, ws.month, ws.day + i);
            final key = dayKey(day);
            final future = key.compareTo(today) > 0;
            final xp = _weekXp[key] ?? 0;
            final fill = xp == 0 ? 0.0 : 0.35 + 0.65 * (xp / maxXp);
            final trained = _trainedDays.contains(key);
            return GestureDetector(
              onTap: future ? null : () => _showDay(key),
              child: Column(children: [
                SumiLabel(weekdayShort[i].substring(0, 1), color: key == today ? Sumi.ink : Sumi.muted),
                const SizedBox(height: 8),
                Enso(
                  value: trained ? 1.0 : fill,
                  size: 36,
                  stroke: trained ? 4.5 : 3.0,
                  seed: i,
                  child: Text('${day.day}',
                      style: TextStyle(fontSize: 11, color: future ? Sumi.faint : Sumi.ink, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 4),
                Text(xp > 0 ? '$xp' : '', style: const TextStyle(fontSize: 9.5, color: Sumi.muted)),
              ]),
            );
          }),
      ]),
    ]);
  }

  Widget _questsCard(GameState g) {
    final done = g.quests.where((q) => q.done).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Daily practice', style: serif(26)),
        const Spacer(),
        Text('$done of ${g.quests.length}', style: const TextStyle(fontSize: 11.5, color: Sumi.muted)),
      ]),
      const SizedBox(height: 4),
      Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Sumi.rule))),
        child: Column(children: [for (final q in g.quests) _questRow(q)]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: Text(
            g.allQuestsDone ? 'All done. Bonus earned.' : 'Finish all three for a bonus.',
            style: serif(16, italic: true, color: Sumi.muted),
          ),
        ),
        XpPill(XpRules.allQuestsBonus, done: g.allQuestsDone),
      ]),
    ]);
  }

  Widget _questRow(QuestStatus q) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Sumi.rule))),
      child: Row(children: [
        Enso(
          value: q.done ? 1.0 : q.progress,
          size: 38,
          stroke: 3.6,
          seed: q.def.title.length,
          child: q.done ? const Icon(Icons.check, size: 15, color: Sumi.ink) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(q.def.title, style: serif(18, color: q.done ? Sumi.muted : Sumi.ink)),
            const SizedBox(height: 2),
            Text(q.detail, style: const TextStyle(fontSize: 11, color: Sumi.muted)),
          ]),
        ),
        const SizedBox(width: 10),
        XpPill(q.def.xp, done: q.done),
      ]),
    );
  }

  Widget _levelCard(GameState g) {
    return InkWell(
      onTap: _openMe,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Text('Level ${g.level} · ${g.title}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(24)),
          ),
          if (g.todayXp > 0)
            Text('+${g.todayXp} today', style: const TextStyle(fontSize: 11.5, color: Sumi.muted)),
        ]),
        const SizedBox(height: 10),
        AnimatedBar(value: g.levelProgress, color: Sumi.ink, height: 4),
        const SizedBox(height: 8),
        Text('${fmtInt(g.xpToNext)} xp to level ${g.level + 1}  ·  ${fmtInt(g.weekXp)} xp this week',
            style: const TextStyle(fontSize: 11.5, color: Sumi.muted)),
      ]),
    );
  }

  Widget _actions() {
    final w = _latestWeight;
    return Row(children: [
      Expanded(
        flex: 5,
        child: FilledButton(onPressed: () => widget.onNavigate(1), child: const Text('Train')),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 5,
        child: OutlinedButton(onPressed: () => widget.onNavigate(2), child: const Text('Log food')),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 5,
        child: OutlinedButton(
          onPressed: _logWeight,
          child: Text(w == null || w.date != todayKey() ? 'Weigh in' : '${fmtW(w.value)} kg'),
        ),
      ),
    ]);
  }

  Widget _reportTeaser(WeeklyReport r) {
    return SumiCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen(report: r))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Enso(value: r.score / 100, size: 70, stroke: 6, seed: 5, child: Text('${r.score}', style: serif(24))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SumiLabel('Your week'),
              const SizedBox(height: 4),
              Text(r.verdict, style: serif(24)),
              const SizedBox(height: 2),
              Text(r.headline, style: const TextStyle(fontSize: 13, color: Sumi.ink2)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        for (final c in r.cards.take(3))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 6), child: BrushLine(width: 12, thickness: 1.8)),
              const SizedBox(width: 10),
              Expanded(child: Text(c.title, style: const TextStyle(fontSize: 13.5))),
            ]),
          ),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerRight,
          child: Text('Read the full report  →', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}
