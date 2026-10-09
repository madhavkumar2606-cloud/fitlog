import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Free food database: https://world.openfoodfacts.org
class FoodApi {
  static Future<List<Food>> search(String query) async {
    final uri = Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {
      'search_terms': query,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '25',
      'fields': 'product_name,brands,nutriments,serving_quantity',
    });
    final res = await http
        .get(uri, headers: {'User-Agent': 'FitLog/1.0 (personal Android app)'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final products = (data['products'] as List?) ?? const [];

    final out = <Food>[];
    for (final raw in products) {
      if (raw is! Map) continue;
      final n = (raw['nutriments'] is Map) ? (raw['nutriments'] as Map) : const {};
      final kj = _num(n['energy_100g']);
      final kcal = _num(n['energy-kcal_100g']) ?? (kj != null ? kj / 4.184 : null);
      final name = (raw['product_name'] as String?)?.trim() ?? '';
      if (name.isEmpty || kcal == null) continue;
      final brand = (raw['brands'] as String?)?.split(',').first.trim() ?? '';
      final serving = _num(raw['serving_quantity']);
      out.add(Food(
        name: brand.isEmpty ? name : '$name ($brand)',
        kcal: kcal,
        protein: _num(n['proteins_100g']) ?? 0,
        carbs: _num(n['carbohydrates_100g']) ?? 0,
        fat: _num(n['fat_100g']) ?? 0,
        servingG: (serving != null && serving > 0) ? serving : 100,
        source: 'openfoodfacts',
      ));
    }
    return out;
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
