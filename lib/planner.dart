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

  bool get trainingDay => trained || planned;

  /// Target for a rest day with the same settings (used to explain calorie cycling).
  DailyTarget get restTarget =>
      dailyTarget(profile, tdee.value, trainingDay: false, sessionsPerWeek: sessionsPerWeek);
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
