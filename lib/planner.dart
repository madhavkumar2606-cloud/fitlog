import 'calc.dart';
import 'db.dart';
import 'models.dart';
import 'util.dart';

class PlanSnapshot {
  final Profile profile;
  final TdeeEstimate tdee;
  final DailyTarget target;
  final bool trained;
  final bool planned;
  final double sessionsPerWeek;

  const PlanSnapshot({
    required this.profile,
    required this.tdee,
    required this.target,
    required this.trained,
    required this.planned,
    required this.sessionsPerWeek,
  });
}

Future<PlanSnapshot> loadPlan(String date) async {
  final db = AppDb.instance;
  final profile = await db.getProfile();
  if (profile == null) throw StateError('Profile not set up');
  final weights = await db.weights(days: 60);
  final totals = await db.dailyTotals(days: 35);
  final tdee = estimateTdee(profile, weights, [for (final d in totals) DayValue(d.date, d.macros.kcal)]);
  final trained = await db.trainedOn(date);
  final planned = await db.isPlannedTraining(date);
  final spw = (await db.sessionCountSince(daysAgoKey(28))) / 4.0;
  final target = dailyTarget(profile, tdee.value, trainingDay: trained || planned, sessionsPerWeek: spw);
  return PlanSnapshot(
    profile: profile,
    tdee: tdee,
    target: target,
    trained: trained,
    planned: planned,
    sessionsPerWeek: spw,
  );
}

Future<List<Insight>> loadInsights(PlanSnapshot plan) async {
  final db = AppDb.instance;
  final today = todayKey();
  final weekAgo = daysAgoKey(7);
  final totals = await db.dailyTotals(days: 8);
  final last7 = totals.where((d) => d.date.compareTo(weekAgo) >= 0 && d.date.compareTo(today) < 0).toList();
  final sessions14 = await db.sessionCountSince(daysAgoKey(14));

  final from42 = daysAgoKey(42);
  final lifts = <LiftTrend>[];
  for (final ex in await db.exercisesWithHistory()) {
    final hist = (await db.e1rmHistory(ex.id)).where((e) => e.date.compareTo(from42) >= 0).toList();
    if (hist.length < 4) continue;
    final first = (hist[0].value + hist[1].value) / 2;
    final last = (hist[hist.length - 1].value + hist[hist.length - 2].value) / 2;
    if (first <= 0) continue;
    lifts.add(LiftTrend(ex.name, (last - first) / first * 100));
  }
  lifts.sort((a, b) => a.changePct.compareTo(b.changePct));

  return buildInsights(
    target: plan.target,
    tdee: plan.tdee.value,
    goal: plan.profile.goal,
    last7: last7,
    sessions14: sessions14,
    lifts: lifts,
  );
}
