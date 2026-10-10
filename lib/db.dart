import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'seed.dart';
import 'util.dart';

const _dbVersion = 2;
const guestDbFile = 'fitlog.db';

const _schemaV1 = [
  '''CREATE TABLE profile(id INTEGER PRIMARY KEY, sex TEXT NOT NULL, age INTEGER NOT NULL,
     height_cm REAL NOT NULL, weight_kg REAL NOT NULL, activity REAL NOT NULL,
     goal TEXT NOT NULL, rate REAL NOT NULL)''',
  'CREATE TABLE weight_log(date TEXT PRIMARY KEY, kg REAL NOT NULL)',
  'CREATE TABLE day_plan(date TEXT PRIMARY KEY, training INTEGER NOT NULL)',
  '''CREATE TABLE food(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
     kcal REAL NOT NULL, protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL,
     serving_g REAL NOT NULL DEFAULT 100, source TEXT NOT NULL DEFAULT 'custom')''',
  '''CREATE TABLE food_log(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL,
     meal TEXT NOT NULL, food_id INTEGER, name TEXT NOT NULL, grams REAL NOT NULL,
     kcal REAL NOT NULL, protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL)''',
  'CREATE INDEX idx_food_log_date ON food_log(date)',
  '''CREATE TABLE exercise(id INTEGER PRIMARY KEY AUTOINCREMENT,
     name TEXT NOT NULL UNIQUE COLLATE NOCASE, muscle TEXT NOT NULL)''',
  'CREATE TABLE routine(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)',
  '''CREATE TABLE routine_exercise(id INTEGER PRIMARY KEY AUTOINCREMENT,
     routine_id INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
     exercise_id INTEGER NOT NULL REFERENCES exercise(id),
     position INTEGER NOT NULL, sets INTEGER NOT NULL, rep_min INTEGER NOT NULL, rep_max INTEGER NOT NULL)''',
  '''CREATE TABLE session(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL,
     routine_id INTEGER, routine_name TEXT NOT NULL, started_at TEXT NOT NULL,
     duration_min INTEGER NOT NULL, kcal_burned REAL NOT NULL)''',
  '''CREATE TABLE set_log(id INTEGER PRIMARY KEY AUTOINCREMENT,
     session_id INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
     exercise_id INTEGER NOT NULL REFERENCES exercise(id),
     set_no INTEGER NOT NULL, weight REAL NOT NULL, reps INTEGER NOT NULL)''',
  'CREATE INDEX idx_set_log_ex ON set_log(exercise_id)',
];

/// Added in version 2: display name, XP events, badges and a small key-value store.
const _schemaV2 = [
  "ALTER TABLE profile ADD COLUMN name TEXT NOT NULL DEFAULT ''",
  '''CREATE TABLE xp_event(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL,
     kind TEXT NOT NULL, ref TEXT NOT NULL, xp INTEGER NOT NULL, label TEXT NOT NULL,
     UNIQUE(kind, ref))''',
  'CREATE INDEX idx_xp_date ON xp_event(date)',
  'CREATE TABLE badge(id TEXT PRIMARY KEY, earned_at TEXT NOT NULL)',
  'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];

class XpEvent {
  final String date, kind, ref, label;
  final int xp;
  const XpEvent(this.date, this.kind, this.ref, this.xp, this.label);
}

class SessionSetRow {
  final int exerciseId;
  final String exerciseName;
  final double weight;
  final int reps;
  const SessionSetRow(this.exerciseId, this.exerciseName, this.weight, this.reps);
}

class SessionRef {
  final int id;
  final String date, startedAt;
  const SessionRef(this.id, this.date, this.startedAt);
}

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Future<Database>? _future;
  String? _file;

  String? get currentFile => _file;

  Future<Database> get db {
    final f = _future;
    if (f == null) throw StateError('Database not opened yet');
    return f;
  }

  /// Opens the data file for one person. Each account on the phone gets its own file.
  /// With [claimGuest], the first account to sign in takes over any offline (guest) data.
  Future<void> openFor(String fileName, {bool claimGuest = false}) async {
    if (_file == fileName && _future != null) return;
    await close();
    final dir = await getDatabasesPath();
    final target = p.join(dir, fileName);
    if (claimGuest && fileName != guestDbFile && !File(target).existsSync()) {
      final guest = p.join(dir, guestDbFile);
      if (File(guest).existsSync()) {
        for (final suffix in ['', '-wal', '-shm', '-journal']) {
          final f = File('$guest$suffix');
          if (f.existsSync()) f.renameSync('$target$suffix');
        }
      }
    }
    _file = fileName;
    _future = openDatabase(
      target,
      version: _dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final stmt in [..._schemaV1, ..._schemaV2]) {
          await db.execute(stmt);
        }
        await seedDatabase(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          for (final stmt in _schemaV2) {
            await db.execute(stmt);
          }
        }
      },
    );
    await _future;
  }

  Future<void> close() async {
    final f = _future;
    _future = null;
    _file = null;
    if (f != null) {
      try {
        await (await f).close();
      } catch (_) {}
    }
  }

  // ---------- Meta ----------

  Future<String?> getMeta(String key) async {
    final rows = await (await db).query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) async {
    await (await db).insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- Profile & body weight ----------

  Future<Profile?> getProfile() async {
    final rows = await (await db).query('profile', where: 'id = 1');
    return rows.isEmpty ? null : Profile.fromMap(rows.first);
  }

  Future<void> saveProfile(Profile profile) async {
    await (await db).insert('profile', profile.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> logWeight(String date, double kg) async {
    final d = await db;
    await d.insert('weight_log', {'date': date, 'kg': kg}, conflictAlgorithm: ConflictAlgorithm.replace);
    await d.rawUpdate(
        'UPDATE profile SET weight_kg = (SELECT kg FROM weight_log ORDER BY date DESC LIMIT 1) WHERE id = 1');
  }

  Future<List<DayValue>> weights({int days = 120}) async {
    final rows = await (await db)
        .query('weight_log', where: 'date >= ?', whereArgs: [daysAgoKey(days)], orderBy: 'date');
    return [for (final r in rows) DayValue(r['date'] as String, toD(r['kg']))];
  }

  Future<List<String>> weightDates() async {
    final rows = await (await db).query('weight_log', columns: ['date'], orderBy: 'date');
    return [for (final r in rows) r['date'] as String];
  }

  Future<DayValue?> latestWeight() async {
    final rows = await (await db).query('weight_log', orderBy: 'date DESC', limit: 1);
    return rows.isEmpty ? null : DayValue(rows.first['date'] as String, toD(rows.first['kg']));
  }

  Future<bool> isPlannedTraining(String date) async {
    final rows = await (await db).query('day_plan', where: 'date = ?', whereArgs: [date]);
    return rows.isNotEmpty && rows.first['training'] == 1;
  }

  Future<void> setPlannedTraining(String date, bool training) async {
    await (await db).insert('day_plan', {'date': date, 'training': training ? 1 : 0},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- Food ----------

  Future<List<Food>> searchFoods(String q) async {
    final d = await db;
    final rows = q.isEmpty
        ? await d.query('food', orderBy: 'name', limit: 100)
        : await d.query('food', where: 'name LIKE ?', whereArgs: ['%$q%'], orderBy: 'name', limit: 50);
    return rows.map(Food.fromMap).toList();
  }

  Future<List<Food>> recentFoods() async {
    final rows = await (await db).rawQuery('''
      SELECT f.* FROM food f
      JOIN (SELECT food_id, MAX(id) AS last_id FROM food_log WHERE food_id IS NOT NULL GROUP BY food_id) r
        ON r.food_id = f.id
      ORDER BY r.last_id DESC LIMIT 20''');
    return rows.map(Food.fromMap).toList();
  }

  Future<int> insertFood(Food f) async => (await db).insert('food', f.toMap());

  Future<void> addFoodEntry({
    required String date,
    required String meal,
    required Food food,
    required double grams,
  }) async {
    final m = food.forGrams(grams);
    await (await db).insert('food_log', {
      'date': date,
      'meal': meal,
      'food_id': food.id,
      'name': food.name,
      'grams': grams,
      'kcal': m.kcal,
      'protein': m.protein,
      'carbs': m.carbs,
      'fat': m.fat,
    });
  }

  Future<void> updateEntryGrams(FoodEntry e, double grams) async {
    final k = e.grams <= 0 ? 0.0 : grams / e.grams;
    await (await db).update(
      'food_log',
      {
        'grams': grams,
        'kcal': e.macros.kcal * k,
        'protein': e.macros.protein * k,
        'carbs': e.macros.carbs * k,
        'fat': e.macros.fat * k,
      },
      where: 'id = ?',
      whereArgs: [e.id],
    );
  }

  Future<List<FoodEntry>> entriesFor(String date) async {
    final rows = await (await db).query('food_log', where: 'date = ?', whereArgs: [date], orderBy: 'id');
    return rows.map(FoodEntry.fromMap).toList();
  }

  Future<void> deleteEntry(int id) async {
    await (await db).delete('food_log', where: 'id = ?', whereArgs: [id]);
  }

  Future<Macros> totalsFor(String date) async {
    final rows = await (await db).rawQuery('''
      SELECT COALESCE(SUM(kcal),0) AS kcal, COALESCE(SUM(protein),0) AS protein,
             COALESCE(SUM(carbs),0) AS carbs, COALESCE(SUM(fat),0) AS fat
      FROM food_log WHERE date = ?''', [date]);
    final r = rows.first;
    return Macros(toD(r['kcal']), toD(r['protein']), toD(r['carbs']), toD(r['fat']));
  }

  Future<List<DayMacros>> dailyTotals({int days = 30}) async {
    final rows = await (await db).rawQuery('''
      SELECT date, SUM(kcal) AS kcal, SUM(protein) AS protein, SUM(carbs) AS carbs, SUM(fat) AS fat
      FROM food_log WHERE date >= ? GROUP BY date ORDER BY date''', [daysAgoKey(days)]);
    return [
      for (final r in rows)
        DayMacros(r['date'] as String, Macros(toD(r['kcal']), toD(r['protein']), toD(r['carbs']), toD(r['fat'])))
    ];
  }

  /// Number of food entries per day since [from].
  Future<Map<String, int>> entryCountsSince(String from) async {
    final rows = await (await db)
        .rawQuery('SELECT date, COUNT(*) AS c FROM food_log WHERE date >= ? GROUP BY date', [from]);
    return {for (final r in rows) r['date'] as String: r['c'] as int};
  }

  Future<Set<String>> mealsLogged(String date) async {
    final rows = await (await db).rawQuery('SELECT DISTINCT meal FROM food_log WHERE date = ?', [date]);
    return {for (final r in rows) r['meal'] as String};
  }

  Future<double> mealProtein(String date, String meal) async {
    final rows = await (await db).rawQuery(
        'SELECT COALESCE(SUM(protein),0) AS p FROM food_log WHERE date = ? AND meal = ?', [date, meal]);
    return toD(rows.first['p']);
  }

  // ---------- Exercises & routines ----------

  Future<List<Exercise>> exercises() async {
    final rows = await (await db).query('exercise', orderBy: 'name COLLATE NOCASE');
    return rows.map(Exercise.fromMap).toList();
  }

  Future<Exercise> addExercise(String name, String muscle) async {
    final d = await db;
    final clean = name.trim();
    final existing = await d.query('exercise', where: 'name = ?', whereArgs: [clean]);
    if (existing.isNotEmpty) return Exercise.fromMap(existing.first);
    final id = await d.insert('exercise', {'name': clean, 'muscle': muscle});
    return Exercise(id: id, name: clean, muscle: muscle);
  }

  Future<List<Routine>> routines() async {
    final d = await db;
    final rs = await d.query('routine', orderBy: 'id');
    final out = <Routine>[];
    for (final r in rs) {
      final items = await d.rawQuery('''
        SELECT re.sets, re.rep_min, re.rep_max, e.id AS eid, e.name AS ename, e.muscle AS emuscle
        FROM routine_exercise re JOIN exercise e ON e.id = re.exercise_id
        WHERE re.routine_id = ? ORDER BY re.position''', [r['id']]);
      out.add(Routine(
        id: r['id'] as int,
        name: r['name'] as String,
        items: [
          for (final i in items)
            RoutineItem(
              exerciseId: i['eid'] as int,
              exerciseName: i['ename'] as String,
              muscle: i['emuscle'] as String,
              sets: i['sets'] as int,
              repMin: i['rep_min'] as int,
              repMax: i['rep_max'] as int,
            )
        ],
      ));
    }
    return out;
  }

  Future<void> saveRoutine(Routine r) async {
    final d = await db;
    await d.transaction((txn) async {
      int id;
      if (r.id == null) {
        id = await txn.insert('routine', {'name': r.name});
      } else {
        id = r.id!;
        await txn.update('routine', {'name': r.name}, where: 'id = ?', whereArgs: [id]);
        await txn.delete('routine_exercise', where: 'routine_id = ?', whereArgs: [id]);
      }
      for (var i = 0; i < r.items.length; i++) {
        final it = r.items[i];
        await txn.insert('routine_exercise', {
          'routine_id': id,
          'exercise_id': it.exerciseId,
          'position': i,
          'sets': it.sets,
          'rep_min': it.repMin,
          'rep_max': it.repMax,
        });
      }
    });
  }

  Future<void> deleteRoutine(int id) async {
    await (await db).delete('routine', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Sessions ----------

  /// Saves a finished workout and returns its id.
  Future<int> saveSession({
    required String date,
    int? routineId,
    required String routineName,
    required DateTime startedAt,
    required int durationMin,
    required double kcalBurned,
    required List<LoggedExercise> exercises,
  }) async {
    final d = await db;
    return d.transaction<int>((txn) async {
      final sid = await txn.insert('session', {
        'date': date,
        'routine_id': routineId,
        'routine_name': routineName,
        'started_at': startedAt.toIso8601String(),
        'duration_min': durationMin,
        'kcal_burned': kcalBurned,
      });
      for (final ex in exercises) {
        for (var i = 0; i < ex.sets.length; i++) {
          await txn.insert('set_log', {
            'session_id': sid,
            'exercise_id': ex.exerciseId,
            'set_no': i + 1,
            'weight': ex.sets[i].weight,
            'reps': ex.sets[i].reps,
          });
        }
      }
      return sid;
    });
  }

  /// Sets from the most recent session that included this exercise.
  Future<List<SetEntry>> lastSetsFor(int exerciseId) async {
    final d = await db;
    final s = await d.rawQuery(
        'SELECT session_id FROM set_log WHERE exercise_id = ? ORDER BY session_id DESC LIMIT 1', [exerciseId]);
    if (s.isEmpty) return [];
    final rows = await d.query('set_log',
        where: 'session_id = ? AND exercise_id = ?', whereArgs: [s.first['session_id'], exerciseId], orderBy: 'id');
    return [for (final r in rows) SetEntry(toD(r['weight']), r['reps'] as int)];
  }

  Future<List<SessionSummary>> recentSessions({int limit = 30}) async {
    final rows = await (await db).rawQuery('''
      SELECT s.id, s.date, s.routine_name, s.duration_min, s.kcal_burned,
             COUNT(l.id) AS sets, COALESCE(SUM(l.weight * l.reps), 0) AS volume
      FROM session s LEFT JOIN set_log l ON l.session_id = s.id
      GROUP BY s.id ORDER BY s.started_at DESC LIMIT ?''', [limit]);
    return [
      for (final r in rows)
        SessionSummary(
          id: r['id'] as int,
          date: r['date'] as String,
          routineName: r['routine_name'] as String,
          durationMin: r['duration_min'] as int,
          sets: r['sets'] as int,
          kcalBurned: toD(r['kcal_burned']),
          volume: toD(r['volume']),
        )
    ];
  }

  Future<SessionSummary?> sessionSummary(int id) async {
    final rows = await (await db).rawQuery('''
      SELECT s.id, s.date, s.routine_name, s.duration_min, s.kcal_burned,
             COUNT(l.id) AS sets, COALESCE(SUM(l.weight * l.reps), 0) AS volume
      FROM session s LEFT JOIN set_log l ON l.session_id = s.id
      WHERE s.id = ? GROUP BY s.id''', [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SessionSummary(
      id: r['id'] as int,
      date: r['date'] as String,
      routineName: r['routine_name'] as String,
      durationMin: r['duration_min'] as int,
      sets: r['sets'] as int,
      kcalBurned: toD(r['kcal_burned']),
      volume: toD(r['volume']),
    );
  }

  Future<List<SessionRef>> allSessionRefs() async {
    final rows = await (await db).query('session', columns: ['id', 'date', 'started_at'], orderBy: 'started_at');
    return [for (final r in rows) SessionRef(r['id'] as int, r['date'] as String, r['started_at'] as String)];
  }

  Future<SessionRef?> sessionRef(int id) async {
    final rows =
        await (await db).query('session', columns: ['id', 'date', 'started_at'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SessionRef(r['id'] as int, r['date'] as String, r['started_at'] as String);
  }

  Future<List<SessionSetRow>> sessionSets(int sessionId) async {
    final rows = await (await db).rawQuery('''
      SELECT l.exercise_id, e.name AS ename, l.weight, l.reps FROM set_log l
      JOIN exercise e ON e.id = l.exercise_id WHERE l.session_id = ? ORDER BY l.id''', [sessionId]);
    return [
      for (final r in rows)
        SessionSetRow(r['exercise_id'] as int, r['ename'] as String, toD(r['weight']), r['reps'] as int)
    ];
  }

  /// Best estimated 1RM for an exercise from sessions that started before [startedAt].
  Future<double> bestE1rmBefore(int exerciseId, String startedAt) async {
    final rows = await (await db).rawQuery('''
      SELECT MAX(CASE WHEN l.reps <= 1 THEN l.weight ELSE l.weight * (1 + l.reps / 30.0) END) AS best
      FROM set_log l JOIN session s ON s.id = l.session_id
      WHERE l.exercise_id = ? AND s.started_at < ? AND l.reps > 0 AND l.weight > 0''', [exerciseId, startedAt]);
    return toD(rows.first['best']);
  }

  Future<List<Map<String, Object?>>> sessionDetail(int id) async {
    return (await db).rawQuery('''
      SELECT l.weight, l.reps, e.name AS ename FROM set_log l
      JOIN exercise e ON e.id = l.exercise_id WHERE l.session_id = ? ORDER BY l.id''', [id]);
  }

  Future<void> deleteSession(int id) async {
    final d = await db;
    await d.delete('session', where: 'id = ?', whereArgs: [id]);
    await d.delete('xp_event',
        where: "kind IN ('workout', 'pr') AND (ref = ? OR ref LIKE ?)", whereArgs: ['S$id', 'S$id:%']);
  }

  Future<bool> trainedOn(String date) async {
    final rows = await (await db).rawQuery('SELECT COUNT(*) AS c FROM session WHERE date = ?', [date]);
    return (Sqflite.firstIntValue(rows) ?? 0) > 0;
  }

  Future<int> sessionCountSince(String from) async {
    final rows = await (await db).rawQuery('SELECT COUNT(*) AS c FROM session WHERE date >= ?', [from]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> sessionCountBetween(String from, String to) async {
    final rows = await (await db)
        .rawQuery('SELECT COUNT(*) AS c FROM session WHERE date >= ? AND date <= ?', [from, to]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<double> volumeBetween(String from, String to) async {
    final rows = await (await db).rawQuery('''
      SELECT COALESCE(SUM(l.weight * l.reps), 0) AS v FROM set_log l
      JOIN session s ON s.id = l.session_id WHERE s.date >= ? AND s.date <= ?''', [from, to]);
    return toD(rows.first['v']);
  }

  Future<int> setsOn(String date) async {
    final rows = await (await db).rawQuery('''
      SELECT COUNT(*) AS c FROM set_log l JOIN session s ON s.id = l.session_id WHERE s.date = ?''', [date]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<String>> sessionDatesSince(String from) async {
    final rows =
        await (await db).rawQuery('SELECT DISTINCT date FROM session WHERE date >= ? ORDER BY date', [from]);
    return [for (final r in rows) r['date'] as String];
  }

  /// Lifetime totals: (workouts, sets, volume in kg).
  Future<(int, int, double)> lifetimeTraining() async {
    final d = await db;
    final s = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM session')) ?? 0;
    final r = await d.rawQuery('SELECT COUNT(*) AS c, COALESCE(SUM(weight * reps), 0) AS v FROM set_log');
    return (s, r.first['c'] as int, toD(r.first['v']));
  }

  /// Completed sets per muscle group since [from].
  Future<Map<String, int>> setsPerMuscle(String from) async {
    final rows = await (await db).rawQuery('''
      SELECT e.muscle AS muscle, COUNT(*) AS c FROM set_log l
      JOIN session s ON s.id = l.session_id JOIN exercise e ON e.id = l.exercise_id
      WHERE s.date >= ? GROUP BY e.muscle ORDER BY c DESC''', [from]);
    return {for (final r in rows) r['muscle'] as String: r['c'] as int};
  }

  /// Total volume per week (keyed by Monday) since [from].
  Future<Map<String, double>> weeklyVolume(String from) async {
    final rows = await (await db).rawQuery('''
      SELECT s.date AS date, SUM(l.weight * l.reps) AS v FROM set_log l
      JOIN session s ON s.id = l.session_id WHERE s.date >= ? GROUP BY s.date''', [from]);
    final out = <String, double>{};
    for (final r in rows) {
      final wk = weekStartKey(parseDay(r['date'] as String));
      out[wk] = (out[wk] ?? 0) + toD(r['v']);
    }
    return out;
  }

  Future<List<Exercise>> exercisesWithHistory() async {
    final rows = await (await db).rawQuery('''
      SELECT DISTINCT e.id, e.name, e.muscle FROM exercise e
      JOIN set_log l ON l.exercise_id = e.id ORDER BY e.name COLLATE NOCASE''');
    return rows.map(Exercise.fromMap).toList();
  }

  /// Best estimated 1RM (Epley) per session for one exercise, oldest first.
  Future<List<DayValue>> e1rmHistory(int exerciseId) async {
    final rows = await (await db).rawQuery('''
      SELECT s.date AS date,
             MAX(CASE WHEN l.reps <= 1 THEN l.weight ELSE l.weight * (1 + l.reps / 30.0) END) AS e1rm
      FROM set_log l JOIN session s ON s.id = l.session_id
      WHERE l.exercise_id = ? AND l.reps > 0
      GROUP BY s.id ORDER BY s.started_at''', [exerciseId]);
    return [for (final r in rows) DayValue(r['date'] as String, toD(r['e1rm']))];
  }

  /// Days with any activity (food, workout or weigh-in) since [from].
  Future<Set<String>> activeDays(String from) async {
    final rows = await (await db).rawQuery('''
      SELECT date FROM food_log WHERE date >= ?
      UNION SELECT date FROM session WHERE date >= ?
      UNION SELECT date FROM weight_log WHERE date >= ?''', [from, from, from]);
    return {for (final r in rows) r['date'] as String};
  }

  // ---------- XP & badges ----------

  /// Returns true if the event was new (each kind+ref can only be awarded once).
  Future<bool> awardXp(XpEvent e) async {
    final id = await (await db).insert(
      'xp_event',
      {'date': e.date, 'kind': e.kind, 'ref': e.ref, 'xp': e.xp, 'label': e.label},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id > 0;
  }

  Future<int> totalXp() async {
    final rows = await (await db).rawQuery('SELECT COALESCE(SUM(xp), 0) AS x FROM xp_event');
    return (rows.first['x'] as num).toInt();
  }

  Future<int> xpBetween(String from, String to) async {
    final rows = await (await db)
        .rawQuery('SELECT COALESCE(SUM(xp), 0) AS x FROM xp_event WHERE date >= ? AND date <= ?', [from, to]);
    return (rows.first['x'] as num).toInt();
  }

  Future<Map<String, int>> xpByDay(String from) async {
    final rows = await (await db)
        .rawQuery('SELECT date, SUM(xp) AS x FROM xp_event WHERE date >= ? GROUP BY date', [from]);
    return {for (final r in rows) r['date'] as String: (r['x'] as num).toInt()};
  }

  Future<List<XpEvent>> xpEventsFor(String date) async {
    final rows = await (await db).query('xp_event', where: 'date = ?', whereArgs: [date], orderBy: 'id');
    return [
      for (final r in rows)
        XpEvent(r['date'] as String, r['kind'] as String, r['ref'] as String, r['xp'] as int, r['label'] as String)
    ];
  }

  Future<int> countXp(String kind, {String? refSuffix}) async {
    final rows = refSuffix == null
        ? await (await db).rawQuery('SELECT COUNT(*) FROM xp_event WHERE kind = ?', [kind])
        : await (await db)
            .rawQuery('SELECT COUNT(*) FROM xp_event WHERE kind = ? AND ref LIKE ?', [kind, '%$refSuffix']);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<Map<String, String>> earnedBadges() async {
    final rows = await (await db).query('badge');
    return {for (final r in rows) r['id'] as String: r['earned_at'] as String};
  }

  Future<void> addBadge(String id, String date) async {
    await (await db).insert('badge', {'id': id, 'earned_at': date}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
