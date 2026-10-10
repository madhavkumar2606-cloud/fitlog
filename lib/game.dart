import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'calc.dart';
import 'db.dart';
import 'planner.dart';
import 'util.dart';

// ---------------- XP rules ----------------

class XpRules {
  static const workoutBase = 40;
  static const perSet = 2;
  static const maxSetsCounted = 30;
  static const pr = 15;
  static const maxPrsPerSession = 5;
  static const weighIn = 5;
  static const foodDay = 10; // 3+ foods logged in a day
  static const allQuestsBonus = 25;
  static const streakWeek = 50; // every 7 days in a row
}

/// Level 1 starts at 0 XP, level 2 at 100, level 3 at 300, level 4 at 600...
int xpForLevel(int level) => 50 * level * (level - 1);

int levelFor(int xp) => math.max(1, ((1 + math.sqrt(1 + 4 * math.max(0, xp) / 50)) / 2).floor());

String levelTitle(int level) {
  if (level <= 2) return 'Rookie';
  if (level <= 4) return 'Regular';
  if (level <= 7) return 'Grinder';
  if (level <= 11) return 'Athlete';
  if (level <= 15) return 'Beast';
  if (level <= 20) return 'Titan';
  return 'Legend';
}

// ---------------- Daily quests ----------------

class QuestDef {
  final String id;
  final String title;
  final int xp;
  final IconData icon;
  const QuestDef(this.id, this.title, this.xp, this.icon);
}

const questDefs = <String, QuestDef>{
  'protein': QuestDef('protein', 'Hit your protein target', 20, Icons.egg_outlined),
  'calories': QuestDef('calories', 'Land within 10% of your calorie target', 15, Icons.local_dining),
  'meals3': QuestDef('meals3', 'Log breakfast, lunch and dinner', 10, Icons.restaurant_menu),
  'weigh': QuestDef('weigh', 'Weigh yourself', 10, Icons.monitor_weight_outlined),
  'workout': QuestDef('workout', 'Finish a workout', 30, Icons.fitness_center),
  'sets15': QuestDef('sets15', 'Complete 15 sets', 20, Icons.format_list_numbered),
  'breakfast_protein': QuestDef('breakfast_protein', 'Eat 25 g protein at breakfast', 10, Icons.free_breakfast_outlined),
  'pr': QuestDef('pr', 'Beat a personal record', 30, Icons.emoji_events_outlined),
};

class QuestStatus {
  final QuestDef def;
  final double progress; // 0..1
  final String detail;
  final bool done;
  const QuestStatus(this.def, this.progress, this.detail, this.done);
}

int _stableHash(String s) {
  var h = 17;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

String _pick(math.Random r, List<String> options) => options[r.nextInt(options.length)];

/// Three quests per day: one nutrition quest, one that suits a training or rest day, and one extra.
List<String> questIdsFor(String date, {required bool trainingDay, required String seed}) {
  final r = math.Random(_stableHash('$seed|$date'));
  final first = r.nextBool() ? 'protein' : 'calories';
  final second = trainingDay
      ? _pick(r, const ['workout', 'workout', 'workout', 'sets15', 'sets15', 'pr'])
      : _pick(r, const ['weigh', 'meals3']);
  final rest = ['protein', 'calories', 'meals3', 'weigh', 'breakfast_protein']
    ..remove(first)
    ..remove(second);
  final third = _pick(r, rest);
  return [first, second, third];
}

// ---------------- Badges ----------------

class LifetimeStats {
  final int workouts, sets, prs, proteinDays, weighIns, questsDone, perfectDays, streak, bestStreak, level;
  final double volume;
  const LifetimeStats({
    required this.workouts,
    required this.sets,
    required this.volume,
    required this.prs,
    required this.proteinDays,
    required this.weighIns,
    required this.questsDone,
    required this.perfectDays,
    required this.streak,
    required this.bestStreak,
    required this.level,
  });
}

class BadgeDef {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final int target;
  final num Function(LifetimeStats s) value;
  const BadgeDef(this.id, this.name, this.description, this.icon, this.target, this.value);

  double progress(LifetimeStats s) => (value(s) / target).clamp(0.0, 1.0).toDouble();
}

final badgeDefs = <BadgeDef>[
  BadgeDef('first_rep', 'First rep', 'Finish your first workout', Icons.fitness_center, 1, (s) => s.workouts),
  BadgeDef('regular', 'Regular', 'Finish 10 workouts', Icons.event_repeat, 10, (s) => s.workouts),
  BadgeDef('gym_rat', 'Gym rat', 'Finish 50 workouts', Icons.sports_martial_arts, 50, (s) => s.workouts),
  BadgeDef('pr_breaker', 'PR breaker', 'Beat a personal record', Icons.trending_up, 1, (s) => s.prs),
  BadgeDef('record_setter', 'Record setter', 'Beat 25 personal records', Icons.emoji_events, 25, (s) => s.prs),
  BadgeDef('on_fire', 'On fire', 'Stay active 7 days in a row', Icons.local_fire_department, 7, (s) => s.bestStreak),
  BadgeDef('unstoppable', 'Unstoppable', 'Stay active 30 days in a row', Icons.whatshot, 30, (s) => s.bestStreak),
  BadgeDef('protein_pro', 'Protein pro', 'Hit your protein target on 10 days', Icons.egg, 10, (s) => s.proteinDays),
  BadgeDef('tonne_10', '10 tonne club', 'Lift 10,000 kg in total', Icons.terrain, 10000, (s) => s.volume),
  BadgeDef('tonne_100', '100 tonne club', 'Lift 100,000 kg in total', Icons.landscape, 100000, (s) => s.volume),
  BadgeDef('data_nerd', 'Data nerd', 'Weigh in on 14 days', Icons.monitor_weight, 14, (s) => s.weighIns),
  BadgeDef('perfect_day', 'Perfect day', 'Complete all 3 daily quests', Icons.auto_awesome, 1, (s) => s.perfectDays),
  BadgeDef('quest_master', 'Quest master', 'Complete 50 daily quests', Icons.task_alt, 50, (s) => s.questsDone),
  BadgeDef('double_digits', 'Double digits', 'Reach level 10', Icons.stars, 10, (s) => s.level),
];

BadgeDef? badgeById(String id) {
  for (final b in badgeDefs) {
    if (b.id == id) return b;
  }
  return null;
}

// ---------------- State ----------------

class GameState {
  final int totalXp;
  final int level;
  final int todayXp;
  final int weekXp;
  final int workoutsThisWeek;
  final int streak;
  final List<QuestStatus> quests;
  final LifetimeStats stats;
  final Map<String, String> earned; // badge id -> date earned
  final List<BadgeDef> newBadges;
  final List<XpEvent> todayEvents;

  const GameState({
    required this.totalXp,
    required this.level,
    required this.todayXp,
    required this.weekXp,
    required this.workoutsThisWeek,
    required this.streak,
    required this.quests,
    required this.stats,
    required this.earned,
    required this.newBadges,
    required this.todayEvents,
  });

  String get title => levelTitle(level);
  int get levelFloor => xpForLevel(level);
  int get levelCeil => xpForLevel(level + 1);
  int get xpToNext => levelCeil - totalXp;
  double get levelProgress => ((totalXp - levelFloor) / (levelCeil - levelFloor)).clamp(0.0, 1.0).toDouble();
  bool get allQuestsDone => quests.isNotEmpty && quests.every((q) => q.done);
}

class SessionReward {
  final int xp;
  final List<String> prs;
  final int levelBefore;
  final GameState state;
  const SessionReward(this.xp, this.prs, this.levelBefore, this.state);

  bool get leveledUp => state.level > levelBefore;
}

class Game {
  static AppDb get _db => AppDb.instance;

  static Future<String> _seed() async => _db.currentFile ?? 'fitlog';

  /// Awards XP for a workout that was just saved, then refreshes everything else.
  static Future<SessionReward> rewardSession(int sessionId) async {
    await _backfill();
    final before = levelFor(await _db.totalXp());
    final (xp, prs) = await _awardSession(sessionId);
    final state = await refresh();
    return SessionReward(xp, prs, before, state);
  }

  static Future<(int, List<String>)> _awardSession(int id) async {
    final ref = await _db.sessionRef(id);
    if (ref == null) return (0, <String>[]);
    final sets = await _db.sessionSets(id);
    if (sets.isEmpty) return (0, <String>[]);

    final int workoutXp = XpRules.workoutBase + XpRules.perSet * math.min<int>(sets.length, XpRules.maxSetsCounted);
    await _db.awardXp(XpEvent(ref.date, 'workout', 'S$id', workoutXp, 'Finished a workout'));

    // Best estimated 1RM per exercise in this session.
    final best = <int, double>{};
    final names = <int, String>{};
    for (final s in sets) {
      if (s.weight <= 0 || s.reps <= 0) continue;
      final e = epley(s.weight, s.reps);
      names[s.exerciseId] = s.exerciseName;
      if (e > (best[s.exerciseId] ?? 0)) best[s.exerciseId] = e;
    }
    final prs = <String>[];
    for (final entry in best.entries) {
      if (prs.length >= XpRules.maxPrsPerSession) break;
      final previous = await _db.bestE1rmBefore(entry.key, ref.startedAt);
      if (previous > 0 && entry.value > previous + 0.01) {
        final name = names[entry.key]!;
        prs.add(name);
        await _db.awardXp(XpEvent(ref.date, 'pr', 'S$id:E${entry.key}', XpRules.pr, '$name personal record'));
      }
    }
    return (workoutXp + prs.length * XpRules.pr, prs);
  }

  /// First run after updating: give XP for everything already logged.
  static Future<void> _backfill() async {
    if (await _db.getMeta('xp_backfill_v1') == '1') return;
    for (final s in await _db.allSessionRefs()) {
      await _awardSession(s.id);
    }
    for (final d in await _db.weightDates()) {
      await _db.awardXp(XpEvent(d, 'weigh', d, XpRules.weighIn, 'Weighed in'));
    }
    final counts = await _db.entryCountsSince('0000-01-01');
    for (final e in counts.entries) {
      if (e.value >= 3) {
        await _db.awardXp(XpEvent(e.key, 'food_day', e.key, XpRules.foodDay, 'Logged your food'));
      }
    }
    await _db.setMeta('xp_backfill_v1', '1');
  }

  static Future<QuestStatus> _evalQuest(String id, String date, PlanSnapshot plan, Set<String> doneIds) async {
    final def = questDefs[id]!;
    final t = plan.target;
    double progress;
    String detail;
    bool done;
    switch (id) {
      case 'protein':
        final pm = await _db.totalsFor(date);
        progress = t.protein <= 0 ? 0 : pm.protein / t.protein;
        detail = '${pm.protein.round()} / ${t.protein.round()} g';
        done = progress >= 0.95;
      case 'calories':
        final m = await _db.totalsFor(date);
        final ratio = t.kcal <= 0 ? 0.0 : m.kcal / t.kcal;
        progress = ratio;
        done = ratio >= 0.9 && ratio <= 1.1;
        detail = ratio > 1.1
            ? '${fmtInt(m.kcal - t.kcal)} kcal over'
            : '${fmtInt(m.kcal)} / ${fmtInt(t.kcal)} kcal';
      case 'meals3':
        final meals = await _db.mealsLogged(date);
        final mealCount = ['Breakfast', 'Lunch', 'Dinner'].where(meals.contains).length;
        progress = mealCount / 3;
        detail = '$mealCount / 3 meals';
        done = mealCount >= 3;
      case 'weigh':
        final dates = await _db.weightDates();
        done = dates.contains(date);
        progress = done ? 1 : 0;
        detail = done ? 'Logged' : 'Not yet';
      case 'workout':
        done = await _db.trainedOn(date);
        progress = done ? 1 : 0;
        detail = done ? 'Done' : 'Not yet';
      case 'sets15':
        final setCount = await _db.setsOn(date);
        progress = setCount / 15;
        detail = '$setCount / 15 sets';
        done = setCount >= 15;
      case 'breakfast_protein':
        final p = await _db.mealProtein(date, 'Breakfast');
        progress = p / 25;
        detail = '${p.round()} / 25 g';
        done = p >= 25;
      case 'pr':
        final events = await _db.xpEventsFor(date);
        done = events.any((e) => e.kind == 'pr');
        progress = done ? 1 : 0;
        detail = done ? 'New record' : 'Not yet';
      default:
        progress = 0;
        detail = '';
        done = false;
    }
    done = done || doneIds.contains(id);
    return QuestStatus(def, progress.clamp(0.0, 1.0).toDouble(), detail, done);
  }

  static Future<List<QuestStatus>> _questsFor(String date, PlanSnapshot plan) async {
    final seed = await _seed();
    final events = await _db.xpEventsFor(date);
    final doneIds = {
      for (final e in events)
        if (e.kind == 'quest') e.ref.split(':').last
    };
    final ids = questIdsFor(date, trainingDay: plan.trainingDay, seed: seed);
    // Quests already completed today stay visible even if the day's plan changed.
    for (final d in doneIds) {
      if (!ids.contains(d) && questDefs.containsKey(d)) ids.add(d);
    }
    final out = <QuestStatus>[];
    for (final id in ids) {
      final q = await _evalQuest(id, date, plan, doneIds);
      if (q.done && !doneIds.contains(id)) {
        await _db.awardXp(XpEvent(date, 'quest', '$date:$id', q.def.xp, 'Quest: ${q.def.title}'));
      }
      out.add(q);
    }
    if (out.isNotEmpty && out.every((q) => q.done)) {
      await _db.awardXp(XpEvent(date, 'bonus', date, XpRules.allQuestsBonus, 'All daily quests done'));
    }
    return out;
  }

  static (int, int) _streaks(Set<String> active) {
    var streak = 0;
    var day = todayKey();
    if (!active.contains(day)) day = shiftDay(day, -1);
    while (active.contains(day)) {
      streak++;
      day = shiftDay(day, -1);
    }
    final sorted = active.toList()..sort();
    var best = 0, run = 0;
    String? prev;
    for (final d in sorted) {
      run = (prev != null && shiftDay(prev, 1) == d) ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    return (streak, math.max(best, streak));
  }

  /// Checks quests, streaks and badges, awards anything new, and returns the full picture.
  static Future<GameState> refresh() async {
    await _backfill();
    final today = todayKey();
    final yesterday = shiftDay(today, -1);

    // Weigh-ins and food days for the last two days.
    final weighDates = (await _db.weightDates()).toSet();
    final counts = await _db.entryCountsSince(yesterday);
    for (final d in [yesterday, today]) {
      if (weighDates.contains(d)) {
        await _db.awardXp(XpEvent(d, 'weigh', d, XpRules.weighIn, 'Weighed in'));
      }
      if ((counts[d] ?? 0) >= 3) {
        await _db.awardXp(XpEvent(d, 'food_day', d, XpRules.foodDay, 'Logged your food'));
      }
    }

    // Quests: finish off yesterday's, then today's.
    await _questsFor(yesterday, await loadPlan(yesterday));
    final plan = await loadPlan(today);
    final quests = await _questsFor(today, plan);

    // Streaks.
    final active = await _db.activeDays(daysAgoKey(400));
    final (streak, bestStreak) = _streaks(active);
    if (active.contains(today) && streak > 0 && streak % 7 == 0) {
      await _db.awardXp(XpEvent(today, 'streak', 'D$today', XpRules.streakWeek, '$streak-day streak'));
    }

    // Totals.
    final totalXp = await _db.totalXp();
    final level = levelFor(totalXp);
    final weekFrom = weekStartKey();
    final weekXp = await _db.xpBetween(weekFrom, today);
    final todayEvents = await _db.xpEventsFor(today);
    final todayXp = todayEvents.fold<int>(0, (a, e) => a + e.xp);
    final workoutsThisWeek = await _db.sessionCountBetween(weekFrom, today);

    // Lifetime stats for badges.
    final (workouts, sets, volume) = await _db.lifetimeTraining();
    final proteinTarget = plan.target.protein;
    final allDays = await _db.dailyTotals(days: 3650);
    final proteinDays = allDays.where((d) => d.macros.protein >= proteinTarget * 0.95).length;
    final stats = LifetimeStats(
      workouts: workouts,
      sets: sets,
      volume: volume,
      prs: await _db.countXp('pr'),
      proteinDays: proteinDays,
      weighIns: weighDates.length,
      questsDone: await _db.countXp('quest'),
      perfectDays: await _db.countXp('bonus'),
      streak: streak,
      bestStreak: bestStreak,
      level: level,
    );

    final earned = await _db.earnedBadges();
    final fresh = <BadgeDef>[];
    for (final b in badgeDefs) {
      if (!earned.containsKey(b.id) && b.value(stats) >= b.target) {
        await _db.addBadge(b.id, today);
        earned[b.id] = today;
        fresh.add(b);
      }
    }

    return GameState(
      totalXp: totalXp,
      level: level,
      todayXp: todayXp,
      weekXp: weekXp,
      workoutsThisWeek: workoutsThisWeek,
      streak: streak,
      quests: quests,
      stats: stats,
      earned: earned,
      newBadges: fresh,
      todayEvents: todayEvents,
    );
  }
}
