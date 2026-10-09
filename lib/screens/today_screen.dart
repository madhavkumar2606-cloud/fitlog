import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import '../models.dart';
import '../planner.dart';
import '../util.dart';
import '../widgets.dart';
import 'profile_screen.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  PlanSnapshot? _plan;
  Macros _eaten = Macros.zero;
  List<Insight> _insights = [];
  DayValue? _latestWeight;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = todayKey();
    final plan = await loadPlan(today);
    final eaten = await AppDb.instance.totalsFor(today);
    final insights = await loadInsights(plan);
    final latest = await AppDb.instance.latestWeight();
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _eaten = eaten;
      _insights = insights;
      _latestWeight = latest;
    });
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

  Future<void> _openProfile() async {
    final changed =
        await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(icon: const Icon(Icons.person_outline), tooltip: 'Profile and goals', onPressed: _openProfile),
        ],
      ),
      body: plan == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _calorieCard(plan),
                  const SizedBox(height: 12),
                  _dayTypeCard(plan),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => widget.onNavigate(1),
                        icon: const Icon(Icons.fitness_center),
                        label: const Text('Start workout'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onNavigate(2),
                        icon: const Icon(Icons.restaurant),
                        label: const Text('Log food'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _weightCard(),
                  const SizedBox(height: 12),
                  _tdeeCard(plan),
                  if (_insights.isNotEmpty) ...[
                    const SectionHeader(title: 'Insights'),
                    for (final i in _insights) _insightCard(i),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _calorieCard(PlanSnapshot plan) {
    final t = plan.target;
    final theme = Theme.of(context);
    final remaining = t.kcal - _eaten.kcal;
    final pct = t.kcal <= 0 ? 0.0 : (_eaten.kcal / t.kcal).clamp(0.0, 1.0).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${remaining.abs().round()}',
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: remaining >= 0 ? theme.colorScheme.primary : theme.colorScheme.error,
                height: 1,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(remaining >= 0 ? 'kcal left' : 'kcal over', style: theme.textTheme.titleMedium),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${_eaten.kcal.round()} eaten of ${t.kcal.round()} kcal', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: pct, minHeight: 12),
          ),
          const SizedBox(height: 12),
          MacroBar(label: 'Protein', value: _eaten.protein, target: t.protein, color: proteinColor),
          MacroBar(label: 'Carbs', value: _eaten.carbs, target: t.carbs, color: carbsColor),
          MacroBar(label: 'Fat', value: _eaten.fat, target: t.fat, color: fatColor),
        ]),
      ),
    );
  }

  Widget _dayTypeCard(PlanSnapshot plan) {
    final t = plan.target;
    final restDelta = (t.baseKcal - dailyTarget(plan.profile, plan.tdee.value,
                trainingDay: false, sessionsPerWeek: plan.sessionsPerWeek)
            .kcal)
        .round();
    if (plan.trained) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.check_circle),
          title: const Text('Training day: workout logged'),
          subtitle: Text(t.cycling
              ? 'Your target includes +${trainingDayBonus.round()} kcal to fuel and recover from training.'
              : 'Calorie cycling starts once you average one or more workouts a week.'),
        ),
      );
    }
    return Card(
      child: SwitchListTile(
        value: plan.planned,
        onChanged: _setPlanned,
        title: const Text('Training today?'),
        subtitle: Text(!t.cycling
            ? 'Calorie cycling starts once you average one or more workouts a week.'
            : plan.planned
                ? 'Training-day target: +${trainingDayBonus.round()} kcal, mostly from carbs.'
                : 'Rest-day target: $restDelta kcal lower, so your weekly total stays on plan.'),
      ),
    );
  }

  Widget _weightCard() {
    final w = _latestWeight;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.monitor_weight_outlined),
        title: Text(w == null ? 'No weigh-ins yet' : '${fmtW(w.value)} kg'),
        subtitle: Text(w == null ? 'Weigh in each morning for accurate targets' : 'Last weighed ${_when(w.date)}'),
        trailing: FilledButton.tonal(onPressed: _logWeight, child: const Text('Log weight')),
      ),
    );
  }

  String _when(String date) {
    final p = prettyDay(date);
    return (p == 'Today' || p == 'Yesterday') ? p.toLowerCase() : 'on $p';
  }

  Widget _tdeeCard(PlanSnapshot plan) {
    final theme = Theme.of(context);
    final p = plan.profile;
    final goal = switch (p.goal) {
      'cut' => 'Losing ${p.rate} kg a week',
      'bulk' => 'Gaining ${p.rate} kg a week',
      _ => 'Maintaining weight',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Maintenance', style: theme.textTheme.titleMedium),
            const Spacer(),
            Chip(
              label: Text(plan.tdee.adaptive ? 'Learned from your data' : 'Formula estimate'),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          Text('${plan.tdee.value.round()} kcal a day', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(plan.tdee.note, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Text('$goal: base target ${plan.target.baseKcal.round()} kcal', style: theme.textTheme.bodyMedium),
        ]),
      ),
    );
  }

  Widget _insightCard(Insight i) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (i.kind) {
      InsightKind.good => (Icons.trending_up, const Color(0xFF7BC67E)),
      InsightKind.warn => (Icons.warning_amber_rounded, scheme.primary),
      InsightKind.info => (Icons.info_outline, scheme.secondary),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(i.title),
        subtitle: Text(i.body),
      ),
    );
  }
}
