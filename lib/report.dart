import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'calc.dart';
import 'db.dart';
import 'models.dart';
import 'planner.dart';
import 'util.dart';

enum ReportKind { good, warn, info }

class ReportCard {
  final ReportKind kind;
  final IconData icon;
  final String title;
  final String message;
  final String why;
  final String? tip;
  final String? stat;
  const ReportCard({
    required this.kind,
    required this.icon,
    required this.title,
    required this.message,
    required this.why,
    this.tip,
    this.stat,
  });
}

class WeekCompare {
  final String label;
  final double thisWeek, lastWeek;
  const WeekCompare(this.label, this.thisWeek, this.lastWeek);
}

class ScorePart {
  final String label;
  final double value, max;
  const ScorePart(this.label, this.value, this.max);
}

class WeeklyReport {
  final int score;
  final String verdict;
  final String headline;
  final List<ScorePart> parts;
  final List<ReportCard> cards;
  final List<WeekCompare> compare;
  const WeeklyReport({
    required this.score,
    required this.verdict,
    required this.headline,
    required this.parts,
    required this.cards,
    required this.compare,
  });
}

class _Lift {
  final String name;
  final double from, to;
  const _Lift(this.name, this.from, this.to);
  double get pct => from <= 0 ? 0 : (to - from) / from * 100;
}

/// Picks everyday foods that would roughly close a protein gap.
String _proteinIdea(double gap) {
  const options = <(String, double)>[
    ('200 g curd', 7.0),
    ('2 eggs', 13.0),
    ('100 g paneer', 18.0),
    ('a scoop of whey', 24.0),
    ('50 g soya chunks', 26.0),
    ('150 g chicken breast', 46.0),
  ];
  for (final o in options) {
    if (o.$2 >= gap) return '${o.$1} (about ${o.$2.round()} g)';
  }
  return 'a scoop of whey plus 150 g chicken breast (about 70 g)';
}

String _times(int n) => n == 1 ? 'once' : '$n times';

Future<WeeklyReport> buildReport(PlanSnapshot plan, {int streak = 0}) async {
  final db = AppDb.instance;
  final p = plan.profile;
  final name = firstName(p.name);
  final hey = name.isEmpty ? '' : ', $name';
  final t = plan.target;
  final today = todayKey();

  // Training: the last 7 days including today vs. the 7 before.
  final w = await db.sessionCountBetween(daysAgoKey(6), today);
  final wPrev = await db.sessionCountBetween(daysAgoKey(13), daysAgoKey(7));
  final vol = await db.volumeBetween(daysAgoKey(6), today);
  final volPrev = await db.volumeBetween(daysAgoKey(13), daysAgoKey(7));
  final trainTarget = math.max(3, math.min(5, plan.sessionsPerWeek.round()));

  // Nutrition: the last 7 complete days (today is still in progress).
  final totals = await db.dailyTotals(days: 15);
  List<DayMacros> window(int fromAgo, int toAgo) => totals
      .where((d) => d.date.compareTo(daysAgoKey(fromAgo)) >= 0 && d.date.compareTo(daysAgoKey(toAgo)) <= 0)
      .where((d) => d.macros.kcal >= 800)
      .toList();
  final logged = window(7, 1);
  final loggedPrev = window(14, 8);
  bool proteinHit(DayMacros d) => d.macros.protein >= t.protein * 0.95;
  bool calHit(DayMacros d) => (d.macros.kcal - t.baseKcal).abs() <= t.baseKcal * 0.1;
  final proteinDays = logged.where(proteinHit).length;
  final calDays = logged.where(calHit).length;
  final avgKcal = logged.isEmpty ? 0.0 : logged.fold<double>(0, (a, d) => a + d.macros.kcal) / logged.length;
  final avgP = logged.isEmpty ? 0.0 : logged.fold<double>(0, (a, d) => a + d.macros.protein) / logged.length;

  // Score out of 100.
  final trainScore = math.min(1.0, w / trainTarget) * 40;
  final nutritionScore = (proteinDays / 7) * 20 + (calDays / 7) * 20;
  final logScore = (logged.length / 7) * 20;
  final score = (trainScore + nutritionScore + logScore).round().clamp(0, 100).toInt();
  final verdict = score >= 85
      ? 'Excellent'
      : score >= 70
          ? 'Strong'
          : score >= 45
              ? 'Decent'
              : 'Getting started';

  // Strength trends over 6 weeks.
  final from42 = daysAgoKey(42);
  final lifts = <_Lift>[];
  for (final ex in await db.exercisesWithHistory()) {
    final hist = (await db.e1rmHistory(ex.id)).where((e) => e.date.compareTo(from42) >= 0 && e.value > 0).toList();
    if (hist.length < 3) continue;
    final a = hist.length >= 4 ? (hist[0].value + hist[1].value) / 2 : hist.first.value;
    final b = hist.length >= 4 ? (hist[hist.length - 1].value + hist[hist.length - 2].value) / 2 : hist.last.value;
    lifts.add(_Lift(ex.name, a, b));
  }
  lifts.sort((x, y) => y.pct.compareTo(x.pct));
  final topLift = lifts.isNotEmpty && lifts.first.pct >= 2 ? lifts.first : null;
  final weakLift = lifts.isNotEmpty && lifts.last.pct <= -3 ? lifts.last : null;

  // Headline.
  String headline;
  if (w == 0 && wPrev == 0 && logged.isEmpty) {
    headline = 'Welcome$hey! Log a few meals and a workout and your weekly report fills in here.';
  } else if (score >= 85) {
    headline = 'Outstanding week$hey. You trained, ate and logged like a pro.';
  } else if (w > wPrev && w > 0) {
    headline = 'Strong week$hey. You trained ${_times(w)}, ${w - wPrev} more than last week.';
  } else if (topLift != null) {
    headline = 'Your ${topLift.name} is climbing$hey: up ${fmtW(topLift.to - topLift.from)} kg in 6 weeks.';
  } else if (w < wPrev) {
    headline = 'A lighter week$hey. You trained ${_times(w)} compared with ${_times(wPrev)} the week before.';
  } else {
    headline = 'Steady week$hey. Here is what stood out.';
  }

  final cards = <ReportCard>[];

  // Training.
  if (w == 0 && wPrev == 0) {
    cards.add(const ReportCard(
      kind: ReportKind.info,
      icon: Icons.fitness_center,
      title: 'No workouts logged yet',
      message: 'Start a routine from the Train tab. Even two sessions a week builds strength.',
      why: 'Your strength charts, personal records and most XP come from logged workouts.',
      tip: 'Start with the Push routine and keep it to 45 minutes.',
    ));
  } else if (w == 0) {
    cards.add(ReportCard(
      kind: ReportKind.warn,
      icon: Icons.fitness_center,
      title: 'No workouts in the last 7 days',
      message: 'You trained ${_times(wPrev)} the week before. A short session today gets you back on track.',
      why: 'Strength fades slowly, but motivation fades fast. Short sessions keep the habit alive.',
      tip: 'Pick your shortest routine and aim for just 30 minutes.',
      stat: '0 / $trainTarget sessions',
    ));
  } else {
    final diff = w - wPrev;
    final cmp = diff > 0
        ? '$diff more than'
        : diff < 0
            ? '${-diff} fewer than'
            : 'the same as';
    final volPct = volPrev > 0 ? ' (${signed((vol - volPrev) / volPrev * 100)}%)' : '';
    cards.add(ReportCard(
      kind: w >= trainTarget ? ReportKind.good : ReportKind.info,
      icon: Icons.fitness_center,
      title: 'You trained ${_times(w)}',
      message: 'That is $cmp last week. You lifted ${fmtInt(vol)} kg in total$volPct.',
      why: 'Training each muscle about twice a week (3 to 5 sessions) is the sweet spot for growth.',
      tip: w < trainTarget ? 'One more session this week would hit your usual target of $trainTarget.' : null,
      stat: '$w / $trainTarget sessions',
    ));
  }

  // Protein.
  if (logged.length >= 2) {
    final gap = t.protein - avgP;
    if (gap > 10) {
      cards.add(ReportCard(
        kind: ReportKind.warn,
        icon: Icons.egg_outlined,
        title: 'Protein is about ${gap.round()} g short',
        message: 'You averaged ${avgP.round()} g a day against your ${t.protein.round()} g target, '
            'and hit it on $proteinDays of ${logged.length} days.',
        why: 'Protein is what your muscles rebuild from after training. Falling short slows progress, '
            'especially when you are trying to lose fat.',
        tip: 'Adding ${_proteinIdea(gap)} each day would close that gap.',
        stat: '$proteinDays / ${logged.length} days',
      ));
    } else {
      cards.add(ReportCard(
        kind: ReportKind.good,
        icon: Icons.egg_outlined,
        title: 'Protein is on point',
        message: 'You averaged ${avgP.round()} g a day and hit your target on $proteinDays of ${logged.length} days.',
        why: 'Enough protein means every workout turns into muscle instead of going to waste.',
        stat: '$proteinDays / ${logged.length} days',
      ));
    }
  }

  // Calories, judged against the goal.
  if (logged.length >= 2) {
    final d = avgKcal - t.baseKcal;
    final base = 'You averaged ${fmtInt(avgKcal)} kcal a day against a target of ${fmtInt(t.baseKcal)}.';
    ReportCard card;
    if (p.goal == 'cut' && d < -400) {
      card = ReportCard(
        kind: ReportKind.warn,
        icon: Icons.local_dining,
        title: 'You are eating well under your plan',
        message: '$base That is about ${fmtInt(-d)} kcal less than planned.',
        why: 'Very big deficits tend to cost strength and muscle, and they are hard to stick to.',
        tip: 'A banana with 30 g of peanut butter adds about 280 kcal of easy fuel.',
        stat: '$calDays / ${logged.length} days on target',
      );
    } else if (p.goal == 'cut' && d > 200) {
      card = ReportCard(
        kind: ReportKind.warn,
        icon: Icons.local_dining,
        title: 'A little above your fat-loss target',
        message: '$base About ${fmtInt(d)} kcal over, so fat loss will be slower than planned.',
        why: 'Fat loss comes down to a steady deficit over weeks, not perfect days.',
        tip: 'Oil, ghee and snacks are the usual hidden calories. Measure them for a few days.',
        stat: '$calDays / ${logged.length} days on target',
      );
    } else if (p.goal == 'bulk' && d < -150) {
      card = ReportCard(
        kind: ReportKind.warn,
        icon: Icons.local_dining,
        title: 'Not enough food to grow',
        message: '$base That is about ${fmtInt(-d)} kcal short.',
        why: 'Muscle needs a small surplus. Without it, gains come very slowly.',
        tip: 'Add a glass of milk and a handful of peanuts (about 400 kcal) to your day.',
        stat: '$calDays / ${logged.length} days on target',
      );
    } else if (p.goal == 'bulk' && d > 400) {
      card = ReportCard(
        kind: ReportKind.info,
        icon: Icons.local_dining,
        title: 'Your surplus is bigger than needed',
        message: '$base About ${fmtInt(d)} kcal over.',
        why: 'Beyond a 300 to 500 kcal surplus, extra food mostly becomes fat, not muscle.',
        stat: '$calDays / ${logged.length} days on target',
      );
    } else if (p.goal == 'maintain' && d.abs() > 250) {
      card = ReportCard(
        kind: ReportKind.info,
        icon: Icons.local_dining,
        title: d > 0 ? 'Eating a bit above maintenance' : 'Eating a bit below maintenance',
        message: base,
        why: 'Small, steady differences add up to about 1 kg a month either way.',
        stat: '$calDays / ${logged.length} days on target',
      );
    } else {
      card = ReportCard(
        kind: ReportKind.good,
        icon: Icons.local_dining,
        title: 'Calories are on plan',
        message: base,
        why: 'Consistent eating is what makes your weight move the way you want.',
        stat: '$calDays / ${logged.length} days on target',
      );
    }
    cards.add(card);
  }

  // Body weight trend.
  final weights = await db.weights(days: 30);
  final recent = weights.where((e) => e.date.compareTo(daysAgoKey(7)) >= 0).toList();
  if (weights.length >= 3 && recent.length >= 2) {
    final trend = emaTrend(weights);
    final idx = weights.indexWhere((e) => e.date.compareTo(daysAgoKey(7)) >= 0);
    final start = idx > 0 ? trend[idx - 1] : trend.first;
    final change = trend.last - start;
    final dir = change < 0 ? 'down' : 'up';
    final what = 'Your trend weight is $dir ${change.abs().toStringAsFixed(1)} kg this week';
    ReportKind kind = ReportKind.info;
    String msg;
    if (p.goal == 'cut') {
      if (change <= -p.rate * 0.5 && change >= -p.rate * 1.5) {
        kind = ReportKind.good;
        msg = '$what, right on pace for losing ${p.rate} kg a week.';
      } else if (change > -p.rate * 0.5) {
        msg = '$what, slower than your goal of ${p.rate} kg a week. If that holds for two weeks, '
            'FitLog lowers your target automatically.';
      } else {
        kind = ReportKind.warn;
        msg = '$what, faster than planned. Losing too fast can cost muscle.';
      }
    } else if (p.goal == 'bulk') {
      if (change >= p.rate * 0.5 && change <= p.rate * 1.5) {
        kind = ReportKind.good;
        msg = '$what, right on pace for gaining ${p.rate} kg a week.';
      } else if (change < p.rate * 0.5) {
        msg = '$what, slower than your goal of ${p.rate} kg a week. FitLog will raise your target if this continues.';
      } else {
        kind = ReportKind.warn;
        msg = '$what, faster than planned. Some of that is likely fat.';
      }
    } else {
      kind = change.abs() <= 0.3 ? ReportKind.good : ReportKind.info;
      msg = change.abs() <= 0.3 ? '$what. Nicely stable.' : '$what.';
    }
    cards.add(ReportCard(
      kind: kind,
      icon: Icons.monitor_weight_outlined,
      title: 'Weight trend',
      message: msg,
      why: 'Daily weight jumps around with water and salt. The trend line smooths that out, '
          'so trust it more than any single weigh-in.',
    ));
  } else {
    cards.add(ReportCard(
      kind: ReportKind.info,
      icon: Icons.monitor_weight_outlined,
      title: 'Weigh in more often',
      message: 'You weighed in ${recent.length} ${recent.length == 1 ? 'time' : 'times'} this week.',
      why: 'Weighing most mornings lets FitLog learn how many calories you really burn.',
      tip: 'Weigh yourself right after waking up, before eating or drinking.',
    ));
  }

  // Strength.
  if (topLift != null) {
    cards.add(ReportCard(
      kind: ReportKind.good,
      icon: Icons.trending_up,
      title: '${topLift.name} is up ${fmtW(topLift.to - topLift.from)} kg',
      message: 'Your estimated max went from ${fmtW(topLift.from)} to ${fmtW(topLift.to)} kg over 6 weeks '
          '(${signed(topLift.pct, digits: 1)}%).',
      why: 'A rising estimated max means your training and eating are working together.',
    ));
  }
  if (weakLift != null) {
    final deficit = logged.isNotEmpty && plan.tdee.value - avgKcal > 500;
    cards.add(ReportCard(
      kind: ReportKind.warn,
      icon: Icons.trending_down,
      title: '${weakLift.name} is slipping',
      message: 'Your estimated max dropped ${(-weakLift.pct).toStringAsFixed(1)}% over 6 weeks.',
      why: deficit
          ? 'You are also eating well below maintenance, which makes it hard to hold strength.'
          : 'This is usually tiredness: poor sleep, stress or too many hard sessions in a row.',
      tip: deficit
          ? 'Try eating at maintenance for 3 or 4 days and see if it bounces back.'
          : 'Take a lighter week (same exercises, about 60% of your usual weight), then push again.',
    ));
  }

  if (streak >= 3) {
    cards.add(ReportCard(
      kind: ReportKind.good,
      icon: Icons.local_fire_department,
      title: '$streak-day streak',
      message: 'You have logged something every day for $streak days. Keep the chain going.',
      why: 'Logging daily is the single best predictor of reaching a fitness goal.',
    ));
  }

  cards.add(ReportCard(
    kind: ReportKind.info,
    icon: Icons.calculate_outlined,
    title: 'How your calorie target is set',
    message: 'Maintenance is about ${fmtInt(plan.tdee.value)} kcal a day. Your goal makes your base target '
        '${fmtInt(t.baseKcal)} kcal, with protein at ${t.protein.round()} g.',
    why: plan.tdee.note,
  ));

  return WeeklyReport(
    score: score,
    verdict: verdict,
    headline: headline,
    parts: [
      ScorePart('Training', trainScore, 40),
      ScorePart('Nutrition', nutritionScore, 40),
      ScorePart('Logging', logScore, 20),
    ],
    cards: cards,
    compare: [
      WeekCompare('Workouts', w.toDouble(), wPrev.toDouble()),
      WeekCompare('Protein days', proteinDays.toDouble(), loggedPrev.where(proteinHit).length.toDouble()),
      WeekCompare('On-target days', calDays.toDouble(), loggedPrev.where(calHit).length.toDouble()),
      WeekCompare('Logged days', logged.length.toDouble(), loggedPrev.length.toDouble()),
    ],
  );
}
