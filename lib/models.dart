double toD(Object? v) => (v as num?)?.toDouble() ?? 0;

class DayValue {
  final String date;
  final double value;
  const DayValue(this.date, this.value);
}

class Macros {
  final double kcal, protein, carbs, fat;
  const Macros(this.kcal, this.protein, this.carbs, this.fat);
  static const zero = Macros(0, 0, 0, 0);
  Macros operator +(Macros o) => Macros(kcal + o.kcal, protein + o.protein, carbs + o.carbs, fat + o.fat);
}

class DayMacros {
  final String date;
  final Macros macros;
  const DayMacros(this.date, this.macros);
}

class Profile {
  String sex; // 'male' | 'female'
  int age;
  double heightCm;
  double weightKg;
  double activity; // TDEE multiplier
  String goal; // 'cut' | 'maintain' | 'bulk'
  double rate; // kg per week

  Profile({
    required this.sex,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activity,
    required this.goal,
    required this.rate,
  });

  Map<String, Object?> toMap() => {
        'id': 1,
        'sex': sex,
        'age': age,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'activity': activity,
        'goal': goal,
        'rate': rate,
      };

  factory Profile.fromMap(Map<String, Object?> m) => Profile(
        sex: m['sex'] as String,
        age: (m['age'] as num).toInt(),
        heightCm: toD(m['height_cm']),
        weightKg: toD(m['weight_kg']),
        activity: toD(m['activity']),
        goal: m['goal'] as String,
        rate: toD(m['rate']),
      );
}

/// Nutrition values are per 100 g.
class Food {
  final int? id;
  final String name;
  final double kcal, protein, carbs, fat;
  final double servingG;
  final String source;

  const Food({
    this.id,
    required this.name,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.servingG = 100,
    this.source = 'custom',
  });

  Food copyWith({int? id}) => Food(
        id: id ?? this.id,
        name: name,
        kcal: kcal,
        protein: protein,
        carbs: carbs,
        fat: fat,
        servingG: servingG,
        source: source,
      );

  Macros forGrams(double g) {
    final k = g / 100;
    return Macros(kcal * k, protein * k, carbs * k, fat * k);
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'serving_g': servingG,
        'source': source,
      };

  factory Food.fromMap(Map<String, Object?> m) => Food(
        id: m['id'] as int?,
        name: m['name'] as String,
        kcal: toD(m['kcal']),
        protein: toD(m['protein']),
        carbs: toD(m['carbs']),
        fat: toD(m['fat']),
        servingG: toD(m['serving_g']),
        source: (m['source'] as String?) ?? 'custom',
      );
}

class FoodEntry {
  final int id;
  final String date, meal, name;
  final double grams;
  final Macros macros;

  const FoodEntry({
    required this.id,
    required this.date,
    required this.meal,
    required this.name,
    required this.grams,
    required this.macros,
  });

  factory FoodEntry.fromMap(Map<String, Object?> m) => FoodEntry(
        id: m['id'] as int,
        date: m['date'] as String,
        meal: m['meal'] as String,
        name: m['name'] as String,
        grams: toD(m['grams']),
        macros: Macros(toD(m['kcal']), toD(m['protein']), toD(m['carbs']), toD(m['fat'])),
      );
}

class Exercise {
  final int id;
  final String name;
  final String muscle;
  const Exercise({required this.id, required this.name, required this.muscle});

  factory Exercise.fromMap(Map<String, Object?> m) =>
      Exercise(id: m['id'] as int, name: m['name'] as String, muscle: m['muscle'] as String);
}

class RoutineItem {
  final int exerciseId;
  final String exerciseName;
  final String muscle;
  int sets, repMin, repMax;

  RoutineItem({
    required this.exerciseId,
    required this.exerciseName,
    required this.muscle,
    this.sets = 3,
    this.repMin = 8,
    this.repMax = 12,
  });
}

class Routine {
  final int? id;
  String name;
  final List<RoutineItem> items;
  Routine({this.id, required this.name, List<RoutineItem>? items}) : items = items ?? [];
}

class SetEntry {
  final double weight;
  final int reps;
  const SetEntry(this.weight, this.reps);
}

class LoggedExercise {
  final int exerciseId;
  final List<SetEntry> sets;
  const LoggedExercise(this.exerciseId, this.sets);
}

class SessionSummary {
  final int id;
  final String date, routineName;
  final int durationMin, sets;
  final double kcalBurned, volume;

  const SessionSummary({
    required this.id,
    required this.date,
    required this.routineName,
    required this.durationMin,
    required this.sets,
    required this.kcalBurned,
    required this.volume,
  });
}
