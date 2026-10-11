import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import '../food_api.dart';
import '../models.dart';
import '../planner.dart';
import '../util.dart';
import '../visuals.dart';
import '../widgets.dart';

const meals = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'];

class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key});

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  String _date = todayKey();
  List<FoodEntry> _entries = [];
  List<Food> _recent = [];
  DailyTarget? _target;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final date = _date;
    final entries = await AppDb.instance.entriesFor(date);
    final plan = await loadPlan(date);
    final recent = await AppDb.instance.recentFoods();
    if (!mounted || date != _date) return;
    setState(() {
      _entries = entries;
      _target = plan.target;
      _recent = recent.take(8).toList();
      _loading = false;
    });
  }

  void _shift(int d) {
    setState(() {
      _date = shiftDay(_date, d);
      _loading = true;
    });
    _load();
  }

  Future<void> _add(String meal) async {
    final added = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => FoodSearchScreen(date: _date, meal: meal)));
    if (added == true) await _load();
  }

  String _mealForNow() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Breakfast';
    if (h < 16) return 'Lunch';
    if (h < 18) return 'Snacks';
    return 'Dinner';
  }

  Future<void> _quickAdd(Food f) async {
    final meal = _mealForNow();
    final grams = f.servingG > 0 ? f.servingG : 100.0;
    await AppDb.instance.addFoodEntry(date: _date, meal: meal, food: f, grams: grams);
    if (!mounted) return;
    showSnack(context, 'Added ${fmtW(grams)} g ${f.name} to $meal');
    await _load();
  }

  Future<void> _editGrams(FoodEntry e) async {
    final g = await askNumber(context, title: e.name, initial: fmtW(e.grams), suffix: 'g');
    if (g == null || g <= 0) return;
    await AppDb.instance.updateEntryGrams(e, g);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final totals = _entries.fold<Macros>(Macros.zero, (a, e) => a + e.macros);
    final t = _target;
    final isToday = _date == todayKey();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Food'),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous day', onPressed: () => _shift(-1)),
          Center(child: Text(prettyDay(_date), style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next day',
            onPressed: isToday ? null : () => _shift(1),
          ),
        ],
      ),
      body: _loading || t == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _hero(totals, t),
                  if (_recent.isNotEmpty && isToday) ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      Text('Quick add', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Text('one tap, adds to ${_mealForNow()}', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recent.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, i) => _quickChip(_recent[i]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  for (final meal in meals) _mealCard(meal, t),
                ],
              ),
            ),
    );
  }

  Widget _hero(Macros totals, DailyTarget t) {
    final theme = Theme.of(context);
    final left = t.kcal - totals.kcal;
    final over = left < 0;
    final pct = t.kcal <= 0 ? 0.0 : totals.kcal / t.kcal;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A3A4F), Color(0xFF1F2833)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(children: [
        Row(children: [
          AnimatedRing(
            value: pct,
            color: over ? theme.colorScheme.error : theme.colorScheme.primary,
            size: 140,
            stroke: 14,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(fmtInt(left.abs()), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
              Text(over ? 'kcal over' : 'kcal left', style: theme.textTheme.labelSmall),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _heroLine('🎯', 'Target', '${fmtInt(t.kcal)} kcal'),
              _heroLine('🍽️', 'Eaten', '${fmtInt(totals.kcal)} kcal'),
              if (t.trainingDay) _heroLine('🏋️', 'Gym day', 'extra fuel'),
              const SizedBox(height: 6),
              Text(
                over
                    ? 'A bit over today. No stress, tomorrow is a fresh start.'
                    : pct < 0.25
                        ? 'Plenty of room. Start with a protein-rich meal.'
                        : pct < 0.85
                            ? 'On track. Keep the protein coming.'
                            : 'Almost there. A light snack fits.',
                style: theme.textTheme.bodySmall,
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          MacroRing(label: 'Protein', value: totals.protein, target: t.protein, color: proteinColor),
          MacroRing(label: 'Carbs', value: totals.carbs, target: t.carbs, color: carbsColor),
          MacroRing(label: 'Fat', value: totals.fat, target: t.fat, color: fatColor),
        ]),
      ]),
    );
  }

  Widget _heroLine(String emoji, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _quickChip(Food f) {
    return Material(
      color: Colors.white.withAlpha(14),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _quickAdd(f),
        child: SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(foodEmoji(f.name), style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 4),
              Text(f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text('${(f.kcal * (f.servingG > 0 ? f.servingG : 100) / 100).round()} kcal',
                  style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        ),
      ),
    );
  }

  static const _mealShare = {'Breakfast': 0.25, 'Lunch': 0.35, 'Dinner': 0.30, 'Snacks': 0.10};
  static const _mealColors = {
    'Breakfast': Color(0xFFF2C94C),
    'Lunch': Color(0xFFF4A259),
    'Dinner': Color(0xFF7FB2F0),
    'Snacks': Color(0xFF6FCF97),
  };

  Widget _mealCard(String meal, DailyTarget t) {
    final theme = Theme.of(context);
    final items = _entries.where((e) => e.meal == meal).toList();
    final sub = items.fold<double>(0, (a, e) => a + e.macros.kcal);
    final goal = t.kcal * (_mealShare[meal] ?? 0.25);
    final c = _mealColors[meal] ?? theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFF1F2833),
        border: Border.all(color: c.withAlpha(50)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => _add(meal),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.withAlpha(45), borderRadius: BorderRadius.circular(16)),
                child: Text(mealEmoji[meal] ?? '🍽️', style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(meal, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text(sub > 0 ? '${sub.round()} kcal' : 'about ${goal.round()} kcal',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: sub > 0 ? FontWeight.w700 : null)),
                  ]),
                  const SizedBox(height: 6),
                  AnimatedBar(value: goal <= 0 ? 0 : (sub / goal).clamp(0.0, 1.0).toDouble(), color: c, height: 7),
                ]),
              ),
              const SizedBox(width: 4),
              Icon(Icons.add_circle, color: c, size: 30),
            ]),
          ),
        ),
        for (final e in items)
          Dismissible(
            key: ValueKey(e.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: theme.colorScheme.errorContainer,
              child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
            ),
            onDismissed: (_) {
              setState(() => _entries.removeWhere((x) => x.id == e.id));
              AppDb.instance.deleteEntry(e.id);
            },
            child: InkWell(
              onTap: () => _editGrams(e),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withAlpha(12), shape: BoxShape.circle),
                    child: Text(foodEmoji(e.name), style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text('${fmtW(e.grams)} g', style: theme.textTheme.bodySmall),
                        const SizedBox(width: 8),
                        _macroDot(proteinColor, 'P', e.macros.protein),
                        _macroDot(carbsColor, 'C', e.macros.carbs),
                        _macroDot(fatColor, 'F', e.macros.fat),
                      ]),
                    ]),
                  ),
                  Text('${e.macros.kcal.round()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  Text(' kcal', style: theme.textTheme.bodySmall),
                ]),
              ),
            ),
          ),
        if (items.isNotEmpty) const SizedBox(height: 6),
      ]),
    );
  }

  Widget _macroDot(Color c, String l, double v) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 3),
          Text('$l ${v.round()}', style: const TextStyle(fontSize: 11)),
        ]),
      );
}

class FoodSearchScreen extends StatefulWidget {
  const FoodSearchScreen({super.key, required this.date, required this.meal});
  final String date;
  final String meal;

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final _ctrl = TextEditingController();
  List<Food> _local = [];
  List<Food> _online = [];
  bool _searchingOnline = false;
  bool _showingRecent = true;
  String? _onlineMsg;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _searchLocal('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _searchLocal(String raw) async {
    final q = raw.trim();
    final token = ++_seq;
    var list = q.isEmpty ? await AppDb.instance.recentFoods() : await AppDb.instance.searchFoods(q);
    if (q.isEmpty && list.isEmpty) list = await AppDb.instance.searchFoods('');
    if (!mounted || token != _seq) return;
    setState(() {
      _local = list;
      _showingRecent = q.isEmpty;
      _online = [];
      _onlineMsg = null;
    });
  }

  Future<void> _searchOnline() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searchingOnline = true;
      _onlineMsg = null;
    });
    try {
      final r = await FoodApi.search(q);
      if (!mounted) return;
      setState(() {
        _online = r;
        if (r.isEmpty) _onlineMsg = 'No online results for "$q". Try a simpler name, or create a custom food.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _onlineMsg = 'Online search failed. Check your internet connection and try again.');
    } finally {
      if (mounted) setState(() => _searchingOnline = false);
    }
  }

  Future<void> _pick(Food food) async {
    final grams = await showDialog<double>(context: context, builder: (_) => _GramsDialog(food: food));
    if (grams == null || grams <= 0) return;
    var f = food;
    if (f.id == null) {
      final id = await AppDb.instance.insertFood(f);
      f = f.copyWith(id: id);
    }
    await AppDb.instance.addFoodEntry(date: widget.date, meal: widget.meal, food: f, grams: grams);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _createCustom() async {
    final food = await Navigator.push<Food>(
        context, MaterialPageRoute(builder: (_) => CustomFoodScreen(initialName: _ctrl.text.trim())));
    if (food != null) await _pick(food);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _ctrl.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text('Add to ${widget.meal}'),
        actions: [
          TextButton.icon(onPressed: _createCustom, icon: const Icon(Icons.add), label: const Text('Custom food')),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search foods, e.g. paneer or oats',
            ),
            onChanged: _searchLocal,
            onSubmitted: (_) => _searchOnline(),
          ),
        ),
        Expanded(
          child: ListView(children: [
            if (_local.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(_showingRecent ? 'Recent and saved foods' : 'Your foods', style: theme.textTheme.labelLarge),
              ),
            for (final f in _local) _foodTile(f),
            if (q.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: _searchingOnline
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton.icon(
                        onPressed: _searchOnline,
                        icon: const Icon(Icons.public),
                        label: Text('Search Open Food Facts for "$q"'),
                      ),
              ),
            if (_onlineMsg != null) EmptyNote(_onlineMsg!),
            for (final f in _online) _foodTile(f, online: true),
          ]),
        ),
      ]),
    );
  }

  Widget _foodTile(Food f, {bool online = false}) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.white.withAlpha(14),
        child: online ? const Icon(Icons.public, size: 20) : Text(foodEmoji(f.name), style: const TextStyle(fontSize: 20)),
      ),
      title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('Per 100 g: ${f.kcal.round()} kcal   P ${f.protein.toStringAsFixed(1)}   '
          'C ${f.carbs.toStringAsFixed(1)}   F ${f.fat.toStringAsFixed(1)}'),
      onTap: () => _pick(f),
    );
  }
}

class _GramsDialog extends StatefulWidget {
  const _GramsDialog({required this.food});
  final Food food;

  @override
  State<_GramsDialog> createState() => _GramsDialogState();
}

class _GramsDialogState extends State<_GramsDialog> {
  late final TextEditingController _c = TextEditingController(text: fmtW(widget.food.servingG));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _set(double g) => setState(() => _c.text = fmtW(g));

  @override
  Widget build(BuildContext context) {
    final g = parseNum(_c.text) ?? 0;
    final m = widget.food.forGrams(g);
    return AlertDialog(
      title: Text(widget.food.name),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount', suffixText: 'g'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ActionChip(
            label: Text('1 serving (${fmtW(widget.food.servingG)} g)'),
            onPressed: () => _set(widget.food.servingG),
          ),
          ActionChip(
            label: Text('2 servings'),
            onPressed: () => _set(widget.food.servingG * 2),
          ),
          ActionChip(label: const Text('100 g'), onPressed: () => _set(100)),
        ]),
        const SizedBox(height: 12),
        Text('${m.kcal.round()} kcal', style: Theme.of(context).textTheme.titleLarge),
        Text('Protein ${m.protein.toStringAsFixed(1)} g, carbs ${m.carbs.toStringAsFixed(1)} g, '
            'fat ${m.fat.toStringAsFixed(1)} g'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: g > 0 ? () => Navigator.pop(context, g) : null, child: const Text('Add')),
      ],
    );
  }
}

class CustomFoodScreen extends StatefulWidget {
  const CustomFoodScreen({super.key, this.initialName = ''});
  final String initialName;

  @override
  State<CustomFoodScreen> createState() => _CustomFoodScreenState();
}

class _CustomFoodScreenState extends State<CustomFoodScreen> {
  late final _name = TextEditingController(text: widget.initialName);
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _serving = TextEditingController(text: '100');

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat, _serving]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final kcal = parseNum(_kcal.text);
    final p = parseNum(_protein.text) ?? 0;
    final c = parseNum(_carbs.text) ?? 0;
    final f = parseNum(_fat.text) ?? 0;
    final s = parseNum(_serving.text) ?? 100;
    if (name.isEmpty || kcal == null || kcal < 0 || s <= 0) {
      showSnack(context, 'Add a name and calories per 100 g.');
      return;
    }
    final food = Food(name: name, kcal: kcal, protein: p, carbs: c, fat: f, servingG: s);
    final id = await AppDb.instance.insertFood(food);
    if (!mounted) return;
    Navigator.pop(context, food.copyWith(id: id));
  }

  Widget _numField(TextEditingController c, String label, String suffix) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom food'), actions: [TextButton(onPressed: _save, child: const Text('Save'))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 16),
        Text('Nutrition per 100 g (check the label on the pack)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Row(children: [_numField(_kcal, 'Calories', 'kcal'), const SizedBox(width: 12), _numField(_protein, 'Protein', 'g')]),
        const SizedBox(height: 12),
        Row(children: [_numField(_carbs, 'Carbs', 'g'), const SizedBox(width: 12), _numField(_fat, 'Fat', 'g')]),
        const SizedBox(height: 12),
        Row(children: [_numField(_serving, 'Usual serving', 'g'), const Expanded(child: SizedBox())]),
      ]),
    );
  }
}
