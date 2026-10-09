import 'package:sqflite/sqflite.dart';

const seedExercises = <(String, String)>[
  ('Bench Press', 'Chest'),
  ('Incline Dumbbell Press', 'Chest'),
  ('Chest Press Machine', 'Chest'),
  ('Cable Fly', 'Chest'),
  ('Dips', 'Triceps'),
  ('Overhead Press', 'Shoulders'),
  ('Lateral Raise', 'Shoulders'),
  ('Face Pull', 'Shoulders'),
  ('Triceps Pushdown', 'Triceps'),
  ('Skull Crusher', 'Triceps'),
  ('Pull-up', 'Back'),
  ('Lat Pulldown', 'Back'),
  ('Barbell Row', 'Back'),
  ('Seated Cable Row', 'Back'),
  ('Shrugs', 'Back'),
  ('Biceps Curl', 'Biceps'),
  ('Hammer Curl', 'Biceps'),
  ('Squat', 'Quads'),
  ('Leg Press', 'Quads'),
  ('Leg Extension', 'Quads'),
  ('Lunges', 'Quads'),
  ('Deadlift', 'Hamstrings'),
  ('Romanian Deadlift', 'Hamstrings'),
  ('Leg Curl', 'Hamstrings'),
  ('Hip Thrust', 'Glutes'),
  ('Calf Raise', 'Calves'),
  ('Plank', 'Core'),
  ('Hanging Leg Raise', 'Core'),
];

/// (name, kcal, protein, carbs, fat) per 100 g, plus a typical serving in grams.
const seedFoods = <(String, double, double, double, double, double)>[
  ('Chicken breast, cooked', 165.0, 31.0, 0.0, 3.6, 150.0),
  ('Egg, whole', 143.0, 12.6, 0.7, 9.5, 50.0),
  ('Egg white', 52.0, 10.9, 0.7, 0.2, 33.0),
  ('Paneer', 265.0, 18.3, 1.2, 20.8, 100.0),
  ('Curd / dahi (whole milk)', 61.0, 3.5, 4.7, 3.3, 150.0),
  ('Milk, toned', 58.0, 3.2, 4.7, 3.0, 250.0),
  ('Whey protein powder', 400.0, 80.0, 8.0, 6.0, 30.0),
  ('Soya chunks, dry', 345.0, 52.0, 33.0, 0.5, 50.0),
  ('Tuna, canned in water', 116.0, 25.5, 0.0, 0.8, 100.0),
  ('Dal (cooked lentils)', 116.0, 9.0, 20.0, 0.4, 150.0),
  ('Rajma, cooked', 127.0, 8.7, 22.8, 0.5, 150.0),
  ('Chana (chickpeas), boiled', 164.0, 8.9, 27.4, 2.6, 150.0),
  ('Sambar', 65.0, 3.0, 9.0, 2.0, 150.0),
  ('White rice, cooked', 130.0, 2.7, 28.0, 0.3, 150.0),
  ('Brown rice, cooked', 112.0, 2.3, 23.5, 0.8, 150.0),
  ('Roti / chapati', 297.0, 11.0, 46.0, 7.5, 40.0),
  ('Idli', 146.0, 4.5, 30.0, 0.4, 40.0),
  ('Dosa, plain', 168.0, 3.9, 29.0, 3.7, 80.0),
  ('Poha, cooked', 170.0, 3.0, 28.0, 5.0, 150.0),
  ('Oats, dry', 389.0, 16.9, 66.3, 6.9, 40.0),
  ('Bread, whole wheat', 247.0, 13.0, 41.0, 3.4, 30.0),
  ('Potato, boiled', 87.0, 1.9, 20.0, 0.1, 150.0),
  ('Sweet potato, boiled', 76.0, 1.4, 17.7, 0.1, 150.0),
  ('Banana', 89.0, 1.1, 22.8, 0.3, 118.0),
  ('Apple', 52.0, 0.3, 13.8, 0.2, 180.0),
  ('Peanuts', 567.0, 25.8, 16.1, 49.2, 30.0),
  ('Peanut butter', 588.0, 25.0, 20.0, 50.0, 32.0),
  ('Almonds', 579.0, 21.2, 21.6, 49.9, 28.0),
  ('Ghee', 900.0, 0.0, 0.0, 100.0, 5.0),
  ('Cooking oil', 884.0, 0.0, 0.0, 100.0, 10.0),
];

/// Starter push / pull / legs split: (exercise, sets, rep min, rep max).
const seedRoutines = <(String, List<(String, int, int, int)>)>[
  ('Push', [
    ('Bench Press', 3, 6, 10),
    ('Overhead Press', 3, 8, 12),
    ('Incline Dumbbell Press', 3, 8, 12),
    ('Lateral Raise', 3, 12, 20),
    ('Triceps Pushdown', 3, 10, 15),
  ]),
  ('Pull', [
    ('Pull-up', 3, 6, 10),
    ('Barbell Row', 3, 8, 12),
    ('Lat Pulldown', 3, 10, 12),
    ('Face Pull', 3, 12, 20),
    ('Biceps Curl', 3, 10, 15),
  ]),
  ('Legs', [
    ('Squat', 3, 5, 8),
    ('Romanian Deadlift', 3, 8, 12),
    ('Leg Press', 3, 10, 15),
    ('Leg Curl', 3, 10, 15),
    ('Calf Raise', 4, 10, 15),
  ]),
];

Future<void> seedDatabase(Database db) async {
  final ids = <String, int>{};
  for (final (name, muscle) in seedExercises) {
    ids[name] = await db.insert('exercise', {'name': name, 'muscle': muscle});
  }
  for (final f in seedFoods) {
    await db.insert('food', {
      'name': f.$1,
      'kcal': f.$2,
      'protein': f.$3,
      'carbs': f.$4,
      'fat': f.$5,
      'serving_g': f.$6,
      'source': 'builtin',
    });
  }
  for (final (name, items) in seedRoutines) {
    final rid = await db.insert('routine', {'name': name});
    var pos = 0;
    for (final (ex, sets, lo, hi) in items) {
      await db.insert('routine_exercise', {
        'routine_id': rid,
        'exercise_id': ids[ex]!,
        'position': pos++,
        'sets': sets,
        'rep_min': lo,
        'rep_max': hi,
      });
    }
  }
}
