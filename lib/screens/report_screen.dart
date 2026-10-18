import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../report.dart';
import '../util.dart';
import '../widgets.dart';

Color kindColor(ReportKind k) => switch (k) {
      ReportKind.good => goodColor,
      ReportKind.warn => warnColor,
      ReportKind.info => infoColor,
    };

Color scoreColor(int score) {
  if (score >= 85) return goodColor;
  if (score >= 70) return goodColor;
  if (score >= 45) return warnColor;
  return fireColor;
}

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.report});
  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = report;
    final color = scoreColor(r.score);
    return Scaffold(
      appBar: AppBar(title: const Text('Your weekly report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: AnimatedRing(
              value: r.score / 100,
              color: color,
              size: 150,
              stroke: 14,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: r.score.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  builder: (context, v, _) => Text('${v.round()}',
                      style: theme.textTheme.displaySmall),
                ),
                Text('out of 100', style: theme.textTheme.bodySmall),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(r.verdict, textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(color: color)),
          const SizedBox(height: 6),
          Text(r.headline, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Where your score comes from', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final p in r.parts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(p.label),
                        const Spacer(),
                        Text('${p.value.round()} / ${p.max.round()}', style: theme.textTheme.bodySmall),
                      ]),
                      const SizedBox(height: 4),
                      AnimatedBar(value: p.max <= 0 ? 0 : p.value / p.max, color: color),
                    ]),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Training counts sessions against your usual target. Nutrition counts days you hit protein '
                  'and calories. Logging counts days you tracked your food.',
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          _CompareCard(compare: r.compare),
          const SectionHeader(title: 'What stood out'),
          for (final c in r.cards) _ReportTile(card: c),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.card});
  final ReportCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = kindColor(card.kind);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: CircleAvatar(backgroundColor: color.withAlpha(45), child: Icon(card.icon, color: color)),
          title: Text(card.title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(card.message),
              if (card.stat != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(8)),
                  child: Text(card.stat!, style: theme.textTheme.labelMedium?.copyWith(color: color)),
                ),
              ],
            ]),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why it matters', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(card.why, style: theme.textTheme.bodyMedium),
            if (card.tip != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(card.tip!, style: theme.textTheme.bodyMedium)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.compare});
  final List<WeekCompare> compare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lastColor = scheme.onSurfaceVariant.withAlpha(110);
    final top = compare.fold<double>(1, (a, c) => [a, c.thisWeek, c.lastWeek].reduce((x, y) => x > y ? x : y));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('This week vs last week', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(children: [
              _legend(scheme.primary, 'Last 7 days'),
              const SizedBox(width: 16),
              _legend(lastColor, 'The 7 before'),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: BarChart(BarChartData(
              maxY: top + 1,
              minY: 0,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => scheme.surfaceContainerHighest,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    '${rodIndex == 0 ? 'Last 7 days' : 'The 7 before'}\n${fmtW(rod.toY)}',
                    TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: top > 6 ? (top / 4).ceilToDouble() : 1,
                    getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: theme.textTheme.labelSmall),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= compare.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(compare[i].label, style: theme.textTheme.labelSmall),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < compare.length; i++)
                  BarChartGroupData(x: i, barsSpace: 4, barRods: [
                    BarChartRodData(
                      toY: compare[i].thisWeek,
                      width: 14,
                      color: scheme.primary,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    BarChartRodData(
                      toY: compare[i].lastWeek,
                      width: 14,
                      color: lastColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ]),
              ],
            )),
          ),
        ]),
      ),
    );
  }

  Widget _legend(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ]);
}
