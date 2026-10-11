import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import '../models.dart';
import '../planner.dart';
import '../util.dart';
import '../widgets.dart';

const _muscleColors = <Color>[
  Color(0xFFF4A259),
  Color(0xFF7FB2F0),
  Color(0xFF6FCF97),
  Color(0xFFB794F6),
  Color(0xFFF2777A),
  Color(0xFFE8C547),
  Color(0xFF4FD1C5),
  Color(0xFFF687B3),
];

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int _range = 90;
  bool _loading = true;
  List<DayValue> _weights = [];
  List<DayMacros> _days = [];
  PlanSnapshot? _plan;
  List<Exercise> _lifts = [];
  int? _liftId;
  List<DayValue> _liftHist = [];
  Map<String, int> _muscles = {};
  Map<String, double> _weeklyVol = {};
  Map<String, int> _xpByDay = {};
  int _touchedMuscle = -1;
  int _touchedMacro = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final from = daysAgoKey(_range);
    final weights = await db.weights(days: _range);
    final days = await db.dailyTotals(days: _range);
    final plan = await loadPlan(todayKey());
    final lifts = await db.exercisesWithHistory();
    final current = _liftId;
    final sel = (current != null && lifts.any((e) => e.id == current)) ? current : (lifts.isEmpty ? null : lifts.first.id);
    final hist = sel == null ? <DayValue>[] : await db.e1rmHistory(sel);
    final muscles = await db.setsPerMuscle(from);
    final vol = await db.weeklyVolume(daysAgoKey(math.min(_range, 84)));
    final xp = await db.xpByDay(daysAgoKey(16 * 7));
    if (!mounted) return;
    setState(() {
      _weights = weights;
      _days = days.where((x) => x.date != todayKey() && x.macros.kcal >= 300).toList();
      _plan = plan;
      _lifts = lifts;
      _liftId = sel;
      _liftHist = hist;
      _muscles = muscles;
      _weeklyVol = vol;
      _xpByDay = xp;
      _loading = false;
      _touchedMuscle = -1;
      _touchedMacro = -1;
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Progress')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 30, label: Text('1M')),
                      ButtonSegment(value: 90, label: Text('3M')),
                      ButtonSegment(value: 180, label: Text('6M')),
                      ButtonSegment(value: 3650, label: Text('All')),
                    ],
                    selected: {_range},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      setState(() => _range = s.first);
                      _load();
                    },
                  ),
                  const SizedBox(height: 12),
                  _card('Activity', 'Each square is a day. Brighter means more XP. Tap one.', _heatmap()),
                  _card('Strength', 'Best estimated 1-rep max per workout. Touch the line for details.', _liftChart()),
                  _card('Weekly volume', 'Total kg lifted each week (weight x reps).', _volumeChart()),
                  _card('Muscle balance', 'Sets per muscle group. Tap a slice.', _muscleChart()),
                  _card('Body weight', 'Dots are weigh-ins, the line is your trend.', _weightChart()),
                  _card('Calories', 'Green is on target, orange is over, blue is under.', _calorieChart()),
                  _card('Where your calories come from', 'Average split of your logged days. Tap a slice.', _macroChart()),
                ],
              ),
            ),
    );
  }

  Widget _card(String title, String subtitle, Widget child) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: theme.textTheme.titleMedium),
          Text(subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }

  TextStyle get _tipStyle => TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      );

  Color get _tipBg => Theme.of(context).colorScheme.surfaceContainerHighest;

  FlTitlesData _titles({
    required String Function(double) left,
    required String Function(double) bottom,
    double? bottomInterval,
    double leftReserved = 40,
  }) {
    final style = Theme.of(context).textTheme.labelSmall;
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: leftReserved,
          getTitlesWidget: (v, meta) {
            if (v == meta.max || v == meta.min) return const SizedBox.shrink();
            return Text(left(v), style: style);
          },
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

  Widget _heatmap() {
    final total = _xpByDay.values.fold<int>(0, (a, b) => a + b);
    final activeDays = _xpByDay.values.where((v) => v > 0).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ActivityHeatmap(
        xpByDay: _xpByDay,
        onTap: (date, xp) => showSnack(context, '${prettyDay(date)}: ${xp > 0 ? '$xp XP earned' : 'no activity'}'),
      ),
      const SizedBox(height: 10),
      Text('$activeDays active days and ${fmtInt(total)} XP in the last 16 weeks.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _liftChart() {
    if (_lifts.isEmpty) return const EmptyNote('Finish a workout to start tracking your strength.');
    final scheme = Theme.of(context).colorScheme;
    final from = daysAgoKey(_range);
    final hist = _liftHist.where((h) => h.value > 0 && h.date.compareTo(from) >= 0).toList();

    Widget chart;
    if (hist.length < 2) {
      chart = const EmptyNote('Log this exercise with weight in at least 2 workouts in this period to see a trend.');
    } else {
      final values = hist.map((h) => h.value);
      final minY = (minOf(values) * 0.92).floorToDouble();
      final maxY = (maxOf(values) * 1.05).ceilToDouble();
      // Mark the points where a new best was set.
      final prIdx = <int>{};
      var runBest = 0.0;
      for (var i = 0; i < hist.length; i++) {
        if (hist[i].value > runBest + 0.01) {
          if (i > 0) prIdx.add(i);
          runBest = hist[i].value;
        }
      }
      chart = SizedBox(
        height: 210,
        child: LineChart(LineChartData(
          minX: 0,
          maxX: (hist.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => _tipBg,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${shortDate(hist[s.spotIndex].date)}\n${fmtW(s.y)} kg${prIdx.contains(s.spotIndex) ? '  New best' : ''}',
                    _tipStyle,
                  ),
              ],
            ),
          ),
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
              isCurved: true,
              preventCurveOverShooting: true,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [scheme.primary.withAlpha(90), scheme.primary.withAlpha(0)],
                ),
              ),
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: prIdx.contains(index) ? 5 : 3,
                  color: prIdx.contains(index) ? warnColor : scheme.primary,
                  strokeWidth: 0,
                ),
              ),
            ),
          ],
        )),
      );
    }

    final best = hist.isEmpty ? null : maxOf(hist.map((h) => h.value));
    final change = hist.length >= 2 ? hist.last.value - hist.first.value : null;
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
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            Chip(
              avatar: const Icon(Icons.emoji_events, size: 16, color: warnColor),
              label: Text('Best ${fmtW(best)} kg'),
              visualDensity: VisualDensity.compact,
            ),
            if (change != null)
              Chip(
                avatar: Icon(change >= 0 ? Icons.trending_up : Icons.trending_down,
                    size: 16, color: change >= 0 ? goodColor : fireColor),
                label: Text('${signed(change, digits: 1)} kg in this period'),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ),
      chart,
    ]);
  }

  Widget _volumeChart() {
    if (_weeklyVol.isEmpty) return const EmptyNote('No workouts in this period yet.');
    final scheme = Theme.of(context).colorScheme;
    final weeks = _weeklyVol.keys.toList()..sort();
    final shown = weeks.length > 12 ? weeks.sublist(weeks.length - 12) : weeks;
    final values = [for (final w in shown) _weeklyVol[w]!];
    final top = maxOf(values) * 1.15;
    return SizedBox(
      height: 180,
      child: BarChart(BarChartData(
        maxY: top <= 0 ? 1 : top,
        minY: 0,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _tipBg,
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              'Week of ${shortDate(shown[group.x])}\n${fmtInt(rod.toY)} kg',
              _tipStyle,
            ),
          ),
        ),
        titlesData: _titles(
          left: (v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
          bottom: (v) {
            final i = v.toInt();
            if (i < 0 || i >= shown.length) return '';
            if (shown.length > 6 && i % 2 == 1) return '';
            return _dm(parseDay(shown[i]));
          },
          leftReserved: 34,
        ),
        barGroups: [
          for (var i = 0; i < shown.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i],
                width: 16,
                color: i == shown.length - 1 ? scheme.primary : scheme.primary.withAlpha(150),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      )),
    );
  }

  Widget _donut({
    required List<(String, double, Color)> parts,
    required int touched,
    required ValueChanged<int> onTouch,
    required String centerTop,
    required String centerBottom,
    required String Function(int i) detail,
  }) {
    final theme = Theme.of(context);
    final total = parts.fold<double>(0, (a, p) => a + p.$2);
    return Column(children: [
      SizedBox(
        height: 200,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(PieChartData(
            centerSpaceRadius: 58,
            sectionsSpace: 2,
            startDegreeOffset: -90,
            pieTouchData: PieTouchData(
              touchCallback: (event, resp) {
                if (!event.isInterestedForInteractions || resp == null || resp.touchedSection == null) return;
                onTouch(resp.touchedSection!.touchedSectionIndex);
              },
            ),
            sections: [
              for (var i = 0; i < parts.length; i++)
                PieChartSectionData(
                  value: parts[i].$2,
                  color: parts[i].$3.withAlpha(touched == -1 || touched == i ? 255 : 90),
                  radius: touched == i ? 34 : 26,
                  showTitle: false,
                ),
            ],
          )),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Column(
              key: ValueKey(touched),
              mainAxisSize: MainAxisSize.min,
              children: touched >= 0 && touched < parts.length
                  ? [
                      Text(parts[touched].$1, style: theme.textTheme.titleSmall),
                      Text('${(parts[touched].$2 / total * 100).round()}%',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(detail(touched), style: theme.textTheme.bodySmall),
                    ]
                  : [
                      Text(centerTop, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(centerBottom, style: theme.textTheme.bodySmall),
                    ],
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 6, children: [
        for (var i = 0; i < parts.length; i++)
          GestureDetector(
            onTap: () => onTouch(touched == i ? -1 : i),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: parts[i].$3, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(parts[i].$1, style: theme.textTheme.bodySmall),
            ]),
          ),
      ]),
    ]);
  }

  Widget _muscleChart() {
    if (_muscles.isEmpty) return const EmptyNote('No sets logged in this period yet.');
    final entries = _muscles.entries.toList();
    final top = entries.take(7).toList();
    final otherSets = entries.skip(7).fold<int>(0, (a, e) => a + e.value);
    final parts = <(String, double, Color)>[
      for (var i = 0; i < top.length; i++) (top[i].key, top[i].value.toDouble(), _muscleColors[i]),
      if (otherSets > 0) ('Other', otherSets.toDouble(), Colors.grey),
    ];
    final total = parts.fold<double>(0, (a, p) => a + p.$2);
    final weeks = _range / 7;
    return _donut(
      parts: parts,
      touched: _touchedMuscle,
      onTouch: (i) => setState(() => _touchedMuscle = i),
      centerTop: fmtInt(total),
      centerBottom: 'sets',
      detail: (i) => _range >= 3650
          ? '${parts[i].$2.round()} sets'
          : '${parts[i].$2.round()} sets, ${(parts[i].$2 / weeks).toStringAsFixed(1)} a week',
    );
  }

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
    final change = trend.last - trend.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Trend ${fmtW(double.parse(trend.last.toStringAsFixed(1)))} kg, '
        '${signed(change, digits: 1)} kg over this period',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 210,
        child: LineChart(LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => _tipBg,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    s.barIndex == 0
                        ? '${shortDate(dayKey(DateTime(base.year, base.month, base.day + s.x.round())))}\n'
                            'Weighed ${fmtW(double.parse(s.y.toStringAsFixed(1)))} kg'
                        : 'Trend ${s.y.toStringAsFixed(1)} kg',
                    _tipStyle,
                  ),
              ],
            ),
          ),
          titlesData: _titles(
            left: (v) => v.toStringAsFixed(0),
            bottom: (v) => _dm(DateTime(base.year, base.month, base.day + v.round())),
            bottomInterval: math.max(1.0, (maxX / 4).ceilToDouble()),
            leftReserved: 32,
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
              dotData: const FlDotData(show: false),
            ),
          ],
        )),
      ),
    ]);
  }

  Widget _calorieChart() {
    if (_days.isEmpty) return const EmptyNote('Log some food to see your daily calories.');
    final scheme = Theme.of(context).colorScheme;
    final target = _plan?.target.baseKcal ?? 0;
    final shown = _days.length > 45 ? _days.sublist(_days.length - 45) : _days;
    final top = math.max(maxOf(shown.map((d) => d.macros.kcal)), target) * 1.15;
    final every = math.max(1, (shown.length / 6).ceil());
    final onTarget = shown.where((d) => (d.macros.kcal - target).abs() <= target * 0.1).length;
    Color colorFor(double kcal) {
      if (target <= 0) return scheme.primary;
      if ((kcal - target).abs() <= target * 0.1) return goodColor;
      return kcal > target ? fireColor : infoColor;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$onTarget of ${shown.length} logged days within 10% of ${fmtInt(target)} kcal',
          style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 10),
      SizedBox(
        height: 200,
        child: BarChart(BarChartData(
          minY: 0,
          maxY: top,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => _tipBg,
              getTooltipItem: (group, gi, rod, ri) {
                final d = shown[group.x];
                return BarTooltipItem(
                  '${shortDate(d.date)}\n${fmtInt(d.macros.kcal)} kcal\nP ${d.macros.protein.round()} g',
                  _tipStyle,
                );
              },
            ),
          ),
          titlesData: _titles(
            left: (v) => v.round().toString(),
            bottom: (v) {
              final i = v.round();
              if (i < 0 || i >= shown.length || i % every != 0) return '';
              return _dm(parseDay(shown[i].date));
            },
          ),
          extraLinesData: ExtraLinesData(horizontalLines: [
            if (target > 0) HorizontalLine(y: target, color: scheme.onSurfaceVariant, strokeWidth: 1.5, dashArray: [6, 4]),
          ]),
          barGroups: [
            for (var i = 0; i < shown.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: shown[i].macros.kcal,
                  width: shown.length > 30 ? 4 : 8,
                  color: colorFor(shown[i].macros.kcal),
                  borderRadius: BorderRadius.circular(2),
                ),
              ]),
          ],
        )),
      ),
    ]);
  }

  Widget _macroChart() {
    if (_days.isEmpty) return const EmptyNote('Log some food to see your macro split.');
    final n = _days.length;
    final p = _days.fold<double>(0, (a, d) => a + d.macros.protein) / n * 4;
    final c = _days.fold<double>(0, (a, d) => a + d.macros.carbs) / n * 4;
    final f = _days.fold<double>(0, (a, d) => a + d.macros.fat) / n * 9;
    final total = p + c + f;
    if (total <= 0) return const EmptyNote('Log some food to see your macro split.');
    final t = _plan?.target;
    final targetTotal = t == null ? 0.0 : t.protein * 4 + t.carbs * 4 + t.fat * 9;
    String targetPct(double v) => targetTotal <= 0 ? '' : ', target ${(v / targetTotal * 100).round()}%';
    final parts = <(String, double, Color)>[
      ('Protein', p, proteinColor),
      ('Carbs', c, carbsColor),
      ('Fat', f, fatColor),
    ];
    final targets = [
      t == null ? 0.0 : t.protein * 4,
      t == null ? 0.0 : t.carbs * 4,
      t == null ? 0.0 : t.fat * 9,
    ];
    return _donut(
      parts: parts,
      touched: _touchedMacro,
      onTouch: (i) => setState(() => _touchedMacro = i),
      centerTop: fmtInt(total),
      centerBottom: 'avg kcal / day',
      detail: (i) => '${fmtInt(parts[i].$2)} kcal${targetPct(targets[i])}',
    );
  }
}
