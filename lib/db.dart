import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'seed.dart';
import 'util.dart';

const _schema = [
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

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Future<Database>? _future;
  Future<Database> get db => _future ??= _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'fitlog.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final stmt in _schema) {
          await db.execute(stmt);
        }
        await seedDatabase(db);
      },
    );
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

  Future<void> saveSession({
    required String date,
    int? routineId,
    required String routineName,
    required DateTime startedAt,
    required int durationMin,
    required double kcalBurned,
    required List<LoggedExercise> exercises,
  }) async {
    final d = await db;
    await d.transaction((txn) async {
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

  Future<List<Map<String, Object?>>> sessionDetail(int id) async {
    return (await db).rawQuery('''
      SELECT l.weight, l.reps, e.name AS ename FROM set_log l
      JOIN exercise e ON e.id = l.exercise_id WHERE l.session_id = ? ORDER BY l.id''', [id]);
  }

  Future<void> deleteSession(int id) async {
    await (await db).delete('session', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> trainedOn(String date) async {
    final rows = await (await db).rawQuery('SELECT COUNT(*) AS c FROM session WHERE date = ?', [date]);
    return (Sqflite.firstIntValue(rows) ?? 0) > 0;
  }

  Future<int> sessionCountSince(String from) async {
    final rows = await (await db).rawQuery('SELECT COUNT(*) AS c FROM session WHERE date >= ?', [from]);
    return Sqflite.firstIntValue(rows) ?? 0;
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
}
