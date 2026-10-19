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
        backgroundColor: Colors.transparent,
        title: const Text('Food'),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous day', onPressed: () => _shift(-1)),
          Center(child: Text(prettyDay(_date), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500))),
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
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 120),
                children: [
                  _hero(totals, t),
                  if (_recent.isNotEmpty && isToday) ...[
                    const SizedBox(height: 22),
                    Row(children: [
                      const SumiLabel('Quick add'),
                      const SizedBox(width: 8),
                      Text('one tap, adds to ${_mealForNow()}',
                          style: const TextStyle(fontSize: 11, color: Sumi.muted)),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 58,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recent.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => _quickChip(_recent[i]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  for (final meal in meals) _mealCard(meal, t),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: () => _add(_mealForNow()),
                    child: Text('Add food to ${_mealForNow()}'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _hero(Macros totals, DailyTarget t) {
    final left = t.kcal - totals.kcal;
    final over = left < 0;
    final pct = t.kcal <= 0 ? 0.0 : totals.kcal / t.kcal;
    Widget macro(String label, double v, double target) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SumiLabel(label, size: 9.5),
              const Spacer(),
              Text('${v.round()} / ${target.round()} g', style: const TextStyle(fontSize: 11, color: Sumi.muted)),
            ]),
            const SizedBox(height: 5),
            AnimatedBar(value: target <= 0 ? 0.0 : v / target, color: Sumi.ink, height: 3),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Enso(
          value: pct,
          size: 136,
          stroke: 10,
          seed: 3,
          color: over ? Sumi.error : Sumi.ink,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(fmtInt(totals.kcal), style: serif(28, height: 1)),
            const SizedBox(height: 3),
            SumiLabel('of ${fmtInt(t.kcal)}', size: 8),
          ]),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(children: [
            macro('Protein', totals.protein, t.protein),
            macro('Carbs', totals.carbs, t.carbs),
            macro('Fat', totals.fat, t.fat),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      Text(
        over
            ? '${fmtInt(left.abs())} kcal over today. Tomorrow is a fresh page.'
            : '${fmtInt(left)} kcal left${t.trainingDay ? ', training day included' : ''}.',
        style: serif(17, italic: true, color: Sumi.muted, height: 1.3),
      ),
    ]);
  }

  Widget _quickChip(Food f) {
    final kcal = (f.kcal * (f.servingG > 0 ? f.servingG : 100) / 100).round();
    return Material(
      color: Sumi.porcelain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF3A3733)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _quickAdd(f),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(17)),
            ),
            const SizedBox(height: 2),
            Text('$kcal kcal', style: const TextStyle(fontSize: 10.5, color: Sumi.muted)),
          ]),
        ),
      ),
    );
  }

  static const _mealShare = {'Breakfast': 0.25, 'Lunch': 0.35, 'Dinner': 0.30, 'Snacks': 0.10};

  Widget _mealCard(String meal, DailyTarget t) {
    final theme = Theme.of(context);
    final items = _entries.where((e) => e.meal == meal).toList();
    final sub = items.fold<double>(0, (a, e) => a + e.macros.kcal);
    final goal = t.kcal * (_mealShare[meal] ?? 0.25);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => _add(meal),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(meal, style: serif(24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sub > 0 ? '${sub.round()} kcal' : 'about ${goal.round()} kcal',
                  style: const TextStyle(fontSize: 11.5, color: Sumi.muted),
                ),
              ),
              const Text('+ add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 6),
            child: Text('Nothing yet', style: TextStyle(fontSize: 12, color: Sumi.faint)),
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(
                        '${fmtW(e.grams)} g  ·  P ${e.macros.protein.round()}  ·  C ${e.macros.carbs.round()}  ·  F ${e.macros.fat.round()}',
                        style: const TextStyle(fontSize: 11, color: Sumi.muted),
                      ),
                    ]),
                  ),
                  Text('${e.macros.kcal.round()}', style: serif(20)),
                  const Text(' kcal', style: TextStyle(fontSize: 11, color: Sumi.muted)),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 6),
        const BrushLine(thickness: 1.5),
      ]),
    );
  }
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
      leading: online ? const Icon(Icons.public, size: 20) : null,
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
