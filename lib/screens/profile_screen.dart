import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../session.dart';
import '../util.dart';
import '../widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.firstRun = false, this.onSaved});
  final bool firstRun;
  final VoidCallback? onSaved;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static final _activities = <double, String>{
    1.2: 'Sedentary: desk job, little walking',
    1.375: 'Light: lifting 2-3 times a week',
    1.55: 'Moderate: lifting 3-5 times a week',
    1.725: 'High: training 6 times a week or a physical job',
  };
  static const _cutRates = [0.25, 0.5, 0.75];
  static const _bulkRates = [0.1, 0.25, 0.5];

  final _name = TextEditingController();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  String _sex = 'male';
  double _activity = 1.55;
  String _goal = 'maintain';
  double _rate = 0.5;
  double? _initialWeight;

  @override
  void initState() {
    super.initState();
    _name.text = AppSession.instance.me?.displayName ?? '';
    _load();
  }

  Future<void> _load() async {
    final p = await AppDb.instance.getProfile();
    if (p == null || !mounted) return;
    setState(() {
      if (p.name.isNotEmpty) _name.text = p.name;
      _sex = p.sex;
      _age.text = '${p.age}';
      _height.text = fmtW(p.heightCm);
      _weight.text = fmtW(p.weightKg);
      _initialWeight = p.weightKg;
      _activity = _activities.containsKey(p.activity) ? p.activity : 1.55;
      _goal = p.goal;
      _rate = p.rate;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  List<double> get _rates => _goal == 'bulk' ? _bulkRates : _cutRates;

  Future<void> _save() async {
    final name = _name.text.trim();
    final age = int.tryParse(_age.text.trim());
    final h = parseNum(_height.text);
    final w = parseNum(_weight.text);
    if (name.isEmpty) {
      showSnack(context, 'Add your name so FitLog knows what to call you.');
      return;
    }
    if (age == null || age < 16 || age > 100 || h == null || h < 120 || h > 230 || w == null || w < 30 || w > 300) {
      showSnack(context, 'Enter age (16-100), height in cm and weight in kg.');
      return;
    }
    final rate = _goal == 'maintain' ? 0.0 : (_rates.contains(_rate) ? _rate : _rates[1]);
    final db = AppDb.instance;
    await db.saveProfile(Profile(
      name: name,
      sex: _sex,
      age: age,
      heightCm: h,
      weightKg: w,
      activity: _activity,
      goal: _goal,
      rate: rate,
    ));
    if (_initialWeight == null || _initialWeight != w) {
      await db.logWeight(todayKey(), w);
    }
    if (!mounted) return;
    if (widget.firstRun) {
      widget.onSaved?.call();
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstRun ? 'Set up FitLog' : 'Profile and goals')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.firstRun)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'These details are used to estimate your maintenance calories. '
                'After a couple of weeks of logging, the app adjusts the estimate from your real data.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name'),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'male', label: Text('Male')),
              ButtonSegment(value: 'female', label: Text('Female')),
            ],
            selected: {_sex},
            onSelectionChanged: (s) => setState(() => _sex = s.first),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _age,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _height,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Height', suffixText: 'cm'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Activity level (include your gym sessions)'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double>(
                value: _activity,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final e in _activities.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _activity = v ?? _activity),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Goal', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cut', label: Text('Lose fat')),
              ButtonSegment(value: 'maintain', label: Text('Maintain')),
              ButtonSegment(value: 'bulk', label: Text('Build muscle')),
            ],
            selected: {_goal},
            onSelectionChanged: (s) => setState(() {
              _goal = s.first;
              if (!_rates.contains(_rate)) _rate = _rates[1];
            }),
          ),
          if (_goal != 'maintain') ...[
            const SizedBox(height: 16),
            Text(_goal == 'cut' ? 'Weekly weight loss' : 'Weekly weight gain', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final r in _rates)
                ChoiceChip(
                  label: Text('${r.toString()} kg'),
                  selected: _rate == r,
                  onSelected: (_) => setState(() => _rate = r),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
              _goal == 'cut'
                  ? 'Slower cuts keep more strength. 0.5 kg a week suits most people.'
                  : 'Slow bulks add less fat. 0.25 kg a week suits most people.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 32),
          FilledButton(onPressed: _save, child: Text(widget.firstRun ? 'Start' : 'Save')),
        ],
      ),
    );
  }
}