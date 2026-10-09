import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import '../models.dart';
import '../planner.dart';
import '../util.dart';
import '../widgets.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<DayValue> _weights = [];
  List<DayMacros> _days = [];
  double? _target;
  List<Exercise> _lifts = [];
  int? _liftId;
  List<DayValue> _liftHist = [];
  int _sessions28 = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final w = await db.weights(days: 180);
    final d = await db.dailyTotals(days: 30);
    final plan = await loadPlan(todayKey());
    final lifts = await db.exercisesWithHistory();
    final s = await db.sessionCountSince(daysAgoKey(28));
    final current = _liftId;
    final sel = (current != null && lifts.any((e) => e.id == current)) ? current : (lifts.isEmpty ? null : lifts.first.id);
    final hist = sel == null ? <DayValue>[] : await db.e1rmHistory(sel);
    if (!mounted) return;
    setState(() {
      _weights = w;
      _days = d.where((x) => x.date != todayKey()).toList();
      _target = plan.target.baseKcal;
      _lifts = lifts;
      _liftId = sel;
      _liftHist = hist;
      _sessions28 = s;
      _loading = false;
    });
  }

  Future<void> _selectLift(int id) async {
    final h = await AppDb.instance.e1rmHistory(id);
    if (!mounted) return;
    setState(() {
      _liftId = id;
      _liftHist = h;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _statsRow(),
                  const SizedBox(height: 12),
                  _chartCard('Strength', 'Best estimated 1-rep max per workout', _liftChart()),
                  _chartCard('Body weight', 'Dots are weigh-ins, the line is your trend', _weightChart()),
                  _chartCard('Calories', 'Last 30 days. Dashed line is your base target', _calorieChart()),
                ],
              ),
            ),
    );
  }

  Widget _statsRow() {
    final logged = _days.where((d) => d.macros.kcal >= 800).toList();
    final recent = logged.length > 7 ? logged.sublist(logged.length - 7) : logged;
    final avg = recent.isEmpty ? null : recent.fold<double>(0, (a, d) => a + d.macros.kcal) / recent.length;
    String change = '-';
    if (_weights.length >= 2) {
      final trend = emaTrend(_weights);
      final cutoff = daysAgoKey(30);
      final idx = _weights.indexWhere((w) => w.date.compareTo(cutoff) >= 0);
      if (idx >= 0 && idx < _weights.length - 1) {
        final delta = trend.last - trend[idx];
        change = '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg';
      }
    }
    return Row(children: [
      _stat('$_sessions28', 'workouts in 4 weeks'),
      _stat(avg == null ? '-' : '${avg.round()}', 'avg kcal, last 7 days'),
      _stat(change, 'weight trend, 30 days'),
    ]);
  }

  Widget _stat(String value, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }

  Widget _chartCard(String title, String subtitle, Widget child) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: theme.textTheme.titleMedium),
          Text(subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }

  FlTitlesData _titles({
    required String Function(double) left,
    required String Function(double) bottom,
    double? bottomInterval,
  }) {
    final style = Theme.of(context).textTheme.labelSmall;
    return FlTitlesData(
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (v, meta) => Text(left(v), style: style),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: bottomInterval,
          getTitlesWidget: (v, meta) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(bottom(v), style: style),
          ),
        ),
      ),
    );
  }

  String _dm(DateTime d) => '${d.day}/${d.month}';

  Widget _weightChart() {
    if (_weights.length < 2) return const EmptyNote('Log your weight on a few days to see your trend.');
    final scheme = Theme.of(context).colorScheme;
    final base = parseDay(_weights.first.date);
    final raw = [for (final w in _weights) FlSpot(daysBetween(base, parseDay(w.date)).toDouble(), w.value)];
    final trend = emaTrend(_weights);
    final trendSpots = [for (var i = 0; i < raw.length; i++) FlSpot(raw[i].x, trend[i])];
    final values = _weights.map((w) => w.value);
    final minY = (minOf(values) - 1).floorToDouble();
    final maxY = (maxOf(values) + 1).ceilToDouble();
    final maxX = math.max(1.0, raw.last.x);
    return SizedBox(
      height: 220,
      child: LineChart(LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titles(
          left: (v) => v.toStringAsFixed(0),
          bottom: (v) => _dm(DateTime(base.year, base.month, base.day + v.round())),
          bottomInterval: math.max(1.0, (maxX / 4).ceilToDouble()),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: raw,
            color: Colors.transparent,
            barWidth: 1,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(radius: 3, color: scheme.secondary.withAlpha(170), strokeWidth: 0),
            ),
          ),
          LineChartBarData(
            spots: trendSpots,
            color: scheme.primary,
            barWidth: 3,
            isCurved: true,
            preventCurveOverShooting: true,
            dotData: FlDotData(show: false),
          ),
        ],
      )),
    );
  }

  Widget _calorieChart() {
    if (_days.isEmpty) return const EmptyNote('Log some food to see your daily calories.');
    final scheme = Theme.of(context).colorScheme;
    final target = _target;
    final top = math.max(maxOf(_days.map((d) => d.macros.kcal)), target ?? 0.0) * 1.15;
    final every = math.max(1, (_days.length / 6).ceil());
    return SizedBox(
      height: 200,
      child: BarChart(BarChartData(
        minY: 0,
        maxY: top,
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titles(
          left: (v) => v.round().toString(),
          bottom: (v) {
            final i = v.round();
            if (i < 0 || i >= _days.length || i % every != 0) return '';
            return _dm(parseDay(_days[i].date));
          },
        ),
        extraLinesData: ExtraLinesData(horizontalLines: [
          if (target != null)
            HorizontalLine(y: target, color: scheme.tertiary, strokeWidth: 1.5, dashArray: [6, 4]),
        ]),
        barGroups: [
          for (var i = 0; i < _days.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: _days[i].macros.kcal,
                width: 7,
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ]),
        ],
      )),
    );
  }

  Widget _liftChart() {
    if (_lifts.isEmpty) return const EmptyNote('Finish a workout to start tracking your strength.');
    final scheme = Theme.of(context).colorScheme;
    final hist = _liftHist.where((h) => h.value > 0).toList();

    Widget chart;
    if (hist.length < 2) {
      chart = const EmptyNote('Log this exercise with weight in at least 2 workouts to see a trend.');
    } else {
      final values = hist.map((h) => h.value);
      final minY = (minOf(values) * 0.9).floorToDouble();
      final maxY = (maxOf(values) * 1.05).ceilToDouble();
      chart = SizedBox(
        height: 200,
        child: LineChart(LineChartData(
          minX: 0,
          maxX: (hist.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            left: (v) => v.toStringAsFixed(0),
            bottom: (v) {
              final i = v.round();
              if (i < 0 || i >= hist.length) return '';
              return _dm(parseDay(hist[i].date));
            },
            bottomInterval: math.max(1.0, ((hist.length - 1) / 4).ceilToDouble()),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < hist.length; i++) FlSpot(i.toDouble(), hist[i].value)],
              color: scheme.primary,
              barWidth: 3,
              dotData: FlDotData(show: true),
            ),
          ],
        )),
      );
    }

    final best = hist.isEmpty ? null : maxOf(hist.map((h) => h.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButton<int>(
        value: _liftId,
        isExpanded: true,
        items: [for (final e in _lifts) DropdownMenuItem(value: e.id, child: Text(e.name))],
        onChanged: (id) {
          if (id != null) _selectLift(id);
        },
      ),
      if (best != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Best: ${fmtW(best)} kg estimated 1RM', style: Theme.of(context).textTheme.bodyMedium),
        ),
      chart,
    ]);
  }
}
