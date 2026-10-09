import 'dart:math' as math;

import 'models.dart';
import 'util.dart';

const kcalPerKg = 7700.0;
const trainingDayBonus = 200.0;

/// Mifflin-St Jeor basal metabolic rate.
double bmr(Profile p) {
  final base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age;
  return p.sex == 'female' ? base - 161 : base + 5;
}

double formulaTdee(Profile p) => bmr(p) * p.activity;

/// Epley estimated one-rep max.
double epley(double weight, int reps) => reps <= 1 ? weight : weight * (1 + reps / 30);

/// Rough energy cost of a lifting session (MET ~5).
double strengthKcal(double bodyKg, int minutes) => 5.0 * bodyKg * minutes / 60;

/// Exponential moving average used for the smoothed body-weight trend line.
List<double> emaTrend(List<DayValue> pts, {double alpha = 0.1}) {
  final out = <double>[];
  double? t;
  for (final p in pts) {
    t = t == null ? p.value : t + alpha * (p.value - t);
    out.add(t);
  }
  return out;
}

double linearSlope(List<double> x, List<double> y) {
  final n = x.length;
  if (n < 2) return 0;
  final mx = x.reduce((a, b) => a + b) / n;
  final my = y.reduce((a, b) => a + b) / n;
  double sxy = 0, sxx = 0;
  for (var i = 0; i < n; i++) {
    sxy += (x[i] - mx) * (y[i] - my);
    sxx += (x[i] - mx) * (x[i] - mx);
  }
  return sxx == 0 ? 0 : sxy / sxx;
}

class TdeeEstimate {
  final double value;
  final double formula;
  final bool adaptive;
  final int foodDays;
  final int weighIns;
  final String note;

  const TdeeEstimate({
    required this.value,
    required this.formula,
    required this.adaptive,
    required this.foodDays,
    required this.weighIns,
    required this.note,
  });
}

/// Maintenance calories. Starts from the formula, then learns your real number
/// from 4 weeks of intake vs. how your weight actually moved.
TdeeEstimate estimateTdee(Profile p, List<DayValue> weights, List<DayValue> intake) {
  final formula = formulaTdee(p);
  final startKey = daysAgoKey(28);
  final start = parseDay(startKey);
  final today = todayKey();
  final w = weights.where((e) => e.date.compareTo(startKey) >= 0).toList();
  // Skip today (still in progress) and days under 800 kcal (probably not fully logged).
  final food = intake
      .where((e) => e.date.compareTo(startKey) >= 0 && e.date.compareTo(today) < 0 && e.value >= 800)
      .toList();

  if (w.length < 6 || food.length < 10) {
    return TdeeEstimate(
      value: formula,
      formula: formula,
      adaptive: false,
      foodDays: food.length,
      weighIns: w.length,
      note: 'Based on the Mifflin-St Jeor formula. Weigh in most mornings and log full days of food '
          'for about 2 weeks, and this switches to an estimate learned from your own data '
          '(${w.length}/6 weigh-ins, ${food.length}/10 food days so far).',
    );
  }

  final xs = [for (final e in w) daysBetween(start, parseDay(e.date)).toDouble()];
  final ys = [for (final e in w) e.value];
  final slope = linearSlope(xs, ys); // kg per day
  final avgIntake = food.fold<double>(0, (a, e) => a + e.value) / food.length;
  final observed = avgIntake - slope * kcalPerKg;
  final confidence = math.min(1.0, food.length / 21);
  final value = (confidence * observed + (1 - confidence) * formula).clamp(1200.0, 5000.0).toDouble();
  final weekly = slope * 7;
  return TdeeEstimate(
    value: value,
    formula: formula,
    adaptive: true,
    foodDays: food.length,
    weighIns: w.length,
    note: 'Learned from your data: you averaged ${avgIntake.round()} kcal/day while your weight moved '
        '${weekly >= 0 ? '+' : ''}${weekly.toStringAsFixed(2)} kg/week over the last 4 weeks.',
  );
}

class DailyTarget {
  final double kcal, protein, carbs, fat;
  final double baseKcal;
  final bool trainingDay;
  final bool cycling;

  const DailyTarget({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.baseKcal,
    required this.trainingDay,
    required this.cycling,
  });
}

/// Goal-adjusted target. If you train at least once a week, training days get
/// +200 kcal and rest days get slightly less, so the weekly total stays the same.
DailyTarget dailyTarget(Profile p, double tdee, {required bool trainingDay, required double sessionsPerWeek}) {
  double adj = 0;
  if (p.goal == 'cut') adj = -p.rate * kcalPerKg / 7;
  if (p.goal == 'bulk') adj = p.rate * kcalPerKg / 7;
  final base = tdee + adj;

  final t = sessionsPerWeek.clamp(0.0, 6.0).toDouble();
  final cycling = t >= 1;
  var kcal = base;
  if (cycling) {
    kcal = trainingDay ? base + trainingDayBonus : base - trainingDayBonus * t / (7 - t);
  }
  final floor = p.sex == 'female' ? 1200.0 : 1500.0;
  kcal = math.max(kcal, floor);

  final protein = (p.goal == 'cut' ? 2.0 : 1.8) * p.weightKg;
  final fat = kcal * 0.25 / 9;
  final carbs = math.max(0.0, (kcal - protein * 4 - fat * 9) / 4);
  return DailyTarget(
    kcal: kcal,
    protein: protein,
    carbs: carbs,
    fat: fat,
    baseKcal: base,
    trainingDay: trainingDay,
    cycling: cycling,
  );
}

double incrementFor(String muscle) =>
    const {'Quads', 'Hamstrings', 'Glutes'}.contains(muscle) ? 5.0 : 2.5;

class Suggestion {
  final double? weight;
  final String text;
  const Suggestion(this.weight, this.text);
}

/// Double progression: hit the top of the rep range on every set, then add weight.
Suggestion suggestNext(List<SetEntry> last, int repMin, int repMax, {double increment = 2.5}) {
  if (last.isEmpty) {
    return Suggestion(null, 'First time: pick a weight you can lift for $repMin-$repMax reps with 1-2 reps to spare.');
  }
  final top = last.map((s) => s.weight).fold<double>(0, (a, b) => a > b ? a : b);
  if (top <= 0) {
    final best = last.map((s) => s.reps).fold<int>(0, (a, b) => a > b ? a : b);
    return Suggestion(null, 'Bodyweight: best set last time was $best reps. Try to beat it.');
  }
  final working = last.where((s) => s.weight == top).toList();
  if (working.every((s) => s.reps >= repMax)) {
    final next = top + increment;
    return Suggestion(next, 'You hit $repMax+ reps on every set last time. Go up to ${fmtW(next)} kg.');
  }
  if (working.any((s) => s.reps < repMin)) {
    return Suggestion(top, 'Some sets fell below $repMin reps last time. Stay at ${fmtW(top)} kg.');
  }
  return Suggestion(top, 'Stay at ${fmtW(top)} kg and try to add a rep to each set.');
}

class LiftTrend {
  final String name;
  final double changePct;
  const LiftTrend(this.name, this.changePct);
}

enum InsightKind { good, warn, info }

class Insight {
  final InsightKind kind;
  final String title;
  final String body;
  const Insight(this.kind, this.title, this.body);
}

/// The part where food and training talk to each other.
List<Insight> buildInsights({
  required DailyTarget target,
  required double tdee,
  required String goal,
  required List<DayMacros> last7,
  required int sessions14,
  required List<LiftTrend> lifts,
}) {
  final out = <Insight>[];
  final logged = last7.where((d) => d.macros.kcal >= 800).toList();

  double? avgKcal;
  if (logged.length < 4) {
    out.add(Insight(InsightKind.info, 'Log a few more days of food',
        'You logged ${logged.length} full days in the past week. Insights get reliable at 4 or more.'));
  }
  if (logged.isNotEmpty) {
    avgKcal = logged.fold<double>(0, (a, d) => a + d.macros.kcal) / logged.length;
    final avgP = logged.fold<double>(0, (a, d) => a + d.macros.protein) / logged.length;
    if (avgP < target.protein * 0.8) {
      out.add(Insight(InsightKind.warn, 'Protein is running low',
          'You averaged ${avgP.round()} g a day against a target of ${target.protein.round()} g. '
              'Low protein slows muscle gain and makes it harder to keep muscle while cutting.'));
    } else if (avgP >= target.protein * 0.95) {
      out.add(Insight(InsightKind.good, 'Protein is on target',
          'You averaged ${avgP.round()} g a day this week.'));
    }
    final gap = tdee - avgKcal;
    if (gap > 1000) {
      out.add(Insight(InsightKind.warn, 'Your deficit is very large',
          'You ate about ${gap.round()} kcal a day below maintenance. Deficits this big usually cost '
              'strength and muscle. Eating closer to your target will help your lifts.'));
    }
    if (goal == 'bulk' && avgKcal < tdee) {
      out.add(Insight(InsightKind.warn, 'You are not in a surplus',
          'You averaged ${avgKcal.round()} kcal against a maintenance of about ${tdee.round()}. '
              'To gain, you need to eat above maintenance most days.'));
    }
  }

  final inDeficit = avgKcal != null && tdee - avgKcal > 500;
  for (final l in lifts.where((l) => l.changePct <= -3).take(3)) {
    out.add(Insight(
      InsightKind.warn,
      '${l.name} is going down',
      'Estimated 1RM dropped ${(-l.changePct).toStringAsFixed(1)}% over the last 6 weeks. ' +
          (inDeficit
              ? 'You are also eating well below maintenance. Try a smaller deficit or a few days at maintenance.'
              : 'Check your sleep and recovery, or take a lighter deload week.'),
    ));
  }
  for (final l in lifts.reversed.where((l) => l.changePct >= 3).take(3)) {
    out.add(Insight(InsightKind.good, '${l.name} is going up',
        'Estimated 1RM rose ${l.changePct.toStringAsFixed(1)}% over the last 6 weeks.'));
  }
  if (sessions14 == 0) {
    out.add(const Insight(InsightKind.info, 'No workouts in the last 2 weeks',
        'Start a routine from the Workouts tab and your strength trends will appear here.'));
  }
  return out;
}
