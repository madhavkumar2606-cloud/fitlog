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
    if (!mounted) return;
    setState(() {
      _gameBest = gameBest;
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _header(plan, game),
                    const SizedBox(height: 14),
                    _levelCard(game),
                    const SizedBox(height: 10),
                    _calorieCard(plan),
                    const SizedBox(height: 10),
                    _weekStrip(),
                    const SizedBox(height: 10),
                    _questsCard(game),
                    const SizedBox(height: 10),
                    _actions(),
                    const SizedBox(height: 10),
                    GymDashCard(best: _gameBest, onPlayed: _load),
                    const SizedBox(height: 10),
                    if (_report != null) _reportTeaser(_report!),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(PlanSnapshot plan, GameState game) {
    final theme = Theme.of(context);
    final me = AppSession.instance.me;
    final name = plan.profile.name.isNotEmpty ? plan.profile.name : (me?.displayName ?? '');
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(greeting(), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(
            firstName(name).isEmpty ? 'Ready to train?' : firstName(name),
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ]),
      ),
      if (game.streak > 0)
        Tooltip(
          message: '${game.streak}-day streak',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(color: fireColor.withAlpha(40), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.local_fire_department, color: fireColor, size: 20),
              const SizedBox(width: 4),
              Text('${game.streak}', style: const TextStyle(color: fireColor, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      GestureDetector(
        onTap: _openMe,
        child: Avatar(name: name.isEmpty ? '?' : name, color: me?.avatarColor ?? 0, size: 46, level: game.level),
      ),
    ]);
  }

  Widget _levelCard(GameState g) {
    const ink = Color(0xFF1B1F27);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: _openMe,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [Color(0xFFB794F6), Color(0xFF7F5AD5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [BoxShadow(color: Color(0x557F5AD5), blurRadius: 22, offset: Offset(0, 8))],
          ),
          child: Row(children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(70),
                border: Border.all(color: Colors.white.withAlpha(140), width: 2),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('LVL', style: TextStyle(color: ink, fontSize: 10, fontWeight: FontWeight.w800)),
                Text('${g.level}', style: const TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w900, height: 1)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(g.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                  if (g.todayXp > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withAlpha(90), borderRadius: BorderRadius.circular(10)),
                      child: Text('+${g.todayXp} today', style: const TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedBar(value: g.levelProgress, color: Colors.white, height: 10),
                ),
                const SizedBox(height: 6),
                Text(
                  '${fmtInt(g.xpToNext)} XP to level ${g.level + 1}  |  ${fmtInt(g.weekXp)} XP this week',
                  style: const TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _calorieCard(PlanSnapshot plan) {
    final t = plan.target;
    final theme = Theme.of(context);
    final remaining = t.kcal - _eaten.kcal;
    final over = remaining < 0;
    final pct = t.kcal <= 0 ? 0.0 : _eaten.kcal / t.kcal;
    final big = _showEaten ? fmtInt(_eaten.kcal) : fmtInt(remaining.abs());
    final small = _showEaten ? 'kcal eaten' : (over ? 'kcal over' : 'kcal left');
    final restDelta = (t.baseKcal - plan.restTarget.kcal).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(children: [
          Row(children: [
            GestureDetector(
              onTap: () => setState(() => _showEaten = !_showEaten),
              child: AnimatedRing(
                value: pct,
                color: over ? theme.colorScheme.error : theme.colorScheme.primary,
                size: 150,
                stroke: 14,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Column(
                    key: ValueKey(_showEaten),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(big,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: over && !_showEaten ? theme.colorScheme.error : null,
                          )),
                      Text(small, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Icon(Icons.touch_app_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Target ${fmtInt(t.kcal)} kcal', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  plan.trainingDay && t.cycling
                      ? 'Training day: +${trainingDayBonus.round()} kcal to fuel your session.'
                      : t.cycling
                          ? 'Rest day: $restDelta kcal lower so your week stays on plan.'
                          : 'Eat about this much to reach your goal.',
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            MacroRing(label: 'Protein', value: _eaten.protein, target: t.protein, color: proteinColor),
            MacroRing(label: 'Carbs', value: _eaten.carbs, target: t.carbs, color: carbsColor),
            MacroRing(label: 'Fat', value: _eaten.fat, target: t.fat, color: fatColor),
          ]),
          if (!plan.trained)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: plan.planned,
              onChanged: _setPlanned,
              title: const Text('Training today?'),
              subtitle: const Text('Adds training-day calories and a workout quest'),
            )
          else
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle, color: goodColor),
              title: Text('Workout done today'),
            ),
        ]),
      ),
    );
  }

  Widget _weekStrip() {
    final theme = Theme.of(context);
    final ws = weekStart(DateTime.now());
    final today = todayKey();
    final maxXp = _weekXp.values.fold<int>(1, (a, b) => b > a ? b : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('This week', style: theme.textTheme.titleMedium),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i < 7; i++)
              Builder(builder: (context) {
                final key = dayKey(DateTime(ws.year, ws.month, ws.day + i));
                final future = key.compareTo(today) > 0;
                final xp = _weekXp[key] ?? 0;
                final fill = xp == 0 ? 0.0 : 0.35 + 0.65 * (xp / maxXp);
                return GestureDetector(
                  onTap: future ? null : () => _showDay(key),
                  child: Column(children: [
                    Text(weekdayShort[i].substring(0, 1), style: theme.textTheme.labelSmall),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: xp > 0
                            ? theme.colorScheme.primary.withAlpha((fill * 255).round())
                            : theme.colorScheme.surfaceContainerHighest.withAlpha(future ? 80 : 255),
                        border: key == today ? Border.all(color: theme.colorScheme.onSurface, width: 2) : null,
                      ),
                      child: _trainedDays.contains(key)
                          ? Icon(Icons.fitness_center, size: 16, color: theme.colorScheme.onPrimary)
                          : Text(
                              '${DateTime(ws.year, ws.month, ws.day + i).day}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: xp > 0 ? theme.colorScheme.onPrimary : null,
                              ),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(xp > 0 ? '$xp' : '', style: theme.textTheme.labelSmall?.copyWith(color: xpColor)),
                  ]),
                );
              }),
          ]),
        ]),
      ),
    );
  }

  Widget _questsCard(GameState g) {
    final theme = Theme.of(context);
    final done = g.quests.where((q) => q.done).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Daily quests', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text('$done / ${g.quests.length} done', style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 8),
          for (final q in g.quests) _questRow(q),
          const SizedBox(height: 4),
          Row(children: [
            Icon(g.allQuestsDone ? Icons.celebration : Icons.card_giftcard, size: 18, color: xpColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                g.allQuestsDone
                    ? 'All done! Bonus earned.'
                    : 'Finish all quests for a bonus.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            XpPill(XpRules.allQuestsBonus, done: g.allQuestsDone),
          ]),
        ]),
      ),
    );
  }

  Widget _questRow(QuestStatus q) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: q.done ? goodColor : theme.colorScheme.surfaceContainerHighest,
          ),
          child: Icon(q.done ? Icons.check : q.def.icon,
              size: 20, color: q.done ? const Color(0xFF1B1F27) : theme.colorScheme.onSurface),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              q.def.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: q.done ? TextDecoration.lineThrough : null,
                color: q.done ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: AnimatedBar(value: q.done ? 1 : q.progress, color: q.done ? goodColor : xpColor, height: 6)),
              const SizedBox(width: 8),
              Text(q.detail, style: theme.textTheme.labelSmall),
            ]),
          ]),
        ),
        const SizedBox(width: 10),
        XpPill(q.def.xp, done: q.done),
      ]),
    );
  }

  Widget _actions() {
    final w = _latestWeight;
    return Row(children: [
      Expanded(
        child: FilledButton.icon(
          onPressed: () => widget.onNavigate(1),
          icon: const Icon(Icons.fitness_center, size: 18),
          label: const Text('Train'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton.tonalIcon(
          onPressed: () => widget.onNavigate(2),
          icon: const Icon(Icons.restaurant, size: 18),
          label: const Text('Log food'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _logWeight,
          icon: const Icon(Icons.monitor_weight_outlined, size: 18),
          label: Text(w == null || w.date != todayKey() ? 'Weigh in' : '${fmtW(w.value)} kg'),
        ),
      ),
    ]);
  }

  Widget _reportTeaser(WeeklyReport r) {
    final theme = Theme.of(context);
    final color = scoreColor(r.score);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen(report: r))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AnimatedRing(
                value: r.score / 100,
                color: color,
                size: 72,
                stroke: 8,
                child: Text('${r.score}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your week: ${r.verdict}', style: theme.textTheme.titleMedium?.copyWith(color: color)),
                  const SizedBox(height: 4),
                  Text(r.headline, style: theme.textTheme.bodyMedium),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            for (final c in r.cards.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(c.icon, size: 18, color: kindColor(c.kind)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.title, style: theme.textTheme.bodyMedium)),
                ]),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text('See full report',
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            ),
          ]),
        ),
      ),
    );
  }
}
