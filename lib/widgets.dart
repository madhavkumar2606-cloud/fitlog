import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'util.dart';
import 'visuals.dart';

// ---------- Palette (Sumi: black ink on paper) ----------

const proteinColor = Sumi.ink;
const carbsColor = Color(0xFFA39D92);
const fatColor = Color(0xFF6D675E);
const goodColor = Sumi.ink;
const warnColor = Sumi.ink2;
const infoColor = Sumi.muted;
const xpColor = Sumi.ink;
const fireColor = Sumi.ink;

const avatarColors = <Color>[
  Sumi.ink,
  Color(0xFF3A3836),
  Color(0xFF5E5952),
  Color(0xFF827C72),
  Color(0xFFA59E92),
  Color(0xFFC9C2B6),
  Color(0xFF2B2A28),
  Color(0xFF6D675E),
];

const muscleColors = <String, Color>{
  'Chest': Sumi.ink,
  'Back': Sumi.ink,
  'Shoulders': Sumi.ink,
  'Biceps': Sumi.ink,
  'Triceps': Sumi.ink,
  'Quads': Sumi.ink,
  'Hamstrings': Sumi.ink,
  'Glutes': Sumi.ink,
  'Calves': Sumi.ink,
  'Core': Sumi.ink,
};

Color muscleColor(String m) => muscleColors[m] ?? Sumi.ink2;

Color avatarColor(int i) => avatarColors[i.abs() % avatarColors.length];

/// Text colour that reads on top of [c].
Color inkOn(Color c) => c.computeLuminance() > 0.35 ? const Color(0xFF151413) : const Color(0xFFECE6DA);

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

// ---------- Avatar ----------

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.color, this.size = 40, this.level});
  final String name;
  final int color;
  final double size;
  final int? level;

  @override
  Widget build(BuildContext context) {
    final c = avatarColor(color);
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Sumi.ink, width: 1)),
      child: Text(initials(name), style: serif(size * 0.44, color: inkOn(c), height: 1)),
    );
    if (level == null) return circle;
    return Stack(clipBehavior: Clip.none, children: [
      circle,
      Positioned(
        right: -5,
        bottom: -4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Sumi.porcelain,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Sumi.ink, width: 1),
          ),
          child: Text('$level', style: const TextStyle(color: Sumi.ink, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }
}

// ---------- Ensō rings ----------

/// A progress ring, drawn as a brushed ensō.
class AnimatedRing extends StatelessWidget {
  const AnimatedRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 120,
    this.stroke = 12,
    this.child,
  });

  final double value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Enso(value: value, color: color, size: size, stroke: stroke * 0.85, seed: size.round(), child: child);
  }
}

/// Small ensō with a label underneath, used for macros.
class MacroRing extends StatelessWidget {
  const MacroRing({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });
  final String label;
  final double value, target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = target <= 0 ? 0.0 : value / target;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Enso(
        value: pct,
        size: 62,
        stroke: 5.5,
        seed: label.length,
        child: Text('${value.round()}', style: serif(19)),
      ),
      const SizedBox(height: 6),
      SumiLabel(label),
      const SizedBox(height: 2),
      Text('of ${target.round()} g', style: const TextStyle(fontSize: 11, color: Sumi.muted)),
    ]);
  }
}

// ---------- Bars ----------

class MacroBar extends StatelessWidget {
  const MacroBar({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
    this.unit = 'g',
  });

  final String label;
  final double value;
  final double target;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final pct = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0).toDouble();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SumiLabel(label),
            const Spacer(),
            Text('${value.round()} / ${target.round()} $unit', style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 4),
          AnimatedBar(value: pct, color: color),
        ],
      ),
    );
  }
}

class AnimatedBar extends StatelessWidget {
  const AnimatedBar({super.key, required this.value, required this.color, this.height = 8});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: LinearProgressIndicator(
          value: v,
          minHeight: math.min(height, 5),
          color: color,
          backgroundColor: Sumi.rule,
        ),
      ),
    );
  }
}

class XpPill extends StatelessWidget {
  const XpPill(this.xp, {super.key, this.done = false});
  final int xp;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: done ? Sumi.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: done ? Sumi.ink : Sumi.edge),
      ),
      child: Text(
        '+$xp xp',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: done ? Sumi.porcelain : Sumi.muted),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.icon, this.color});
  final String value;
  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Sumi.porcelain.withAlpha(200),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sumi.rule),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: serif(26), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 9.5, letterSpacing: 1.6, color: Sumi.muted), maxLines: 2),
      ]),
    );
  }
}

// ---------- Activity heatmap ----------

/// GitHub-style grid: one column per week, one row per weekday, colour = XP earned that day.
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({super.key, required this.xpByDay, this.weeks = 16, this.onTap});
  final Map<String, int> xpByDay;
  final int weeks;
  final void Function(String date, int xp)? onTap;

  Color _cell(BuildContext context, int xp, bool future) {
    const base = Sumi.ink;
    if (future) return Colors.transparent;
    if (xp <= 0) return Sumi.wash;
    if (xp < 30) return base.withAlpha(70);
    if (xp < 80) return base.withAlpha(130);
    if (xp < 150) return base.withAlpha(190);
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final ws = weekStart(DateTime.now());
    final start = DateTime(ws.year, ws.month, ws.day - 7 * (weeks - 1));
    final today = dateOnly(DateTime.now());
    final label = Theme.of(context).textTheme.labelSmall;
    return LayoutBuilder(builder: (context, c) {
      const labelW = 22.0;
      const gap = 3.0;
      final cell = math.min(18.0, (c.maxWidth - labelW - gap * (weeks - 1)) / weeks);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: labelW,
          child: Column(children: [
            for (var r = 0; r < 7; r++)
              SizedBox(
                height: cell + (r < 6 ? gap : 0),
                child: Text(r.isEven ? weekdayShort[r].substring(0, 1) : '', style: label),
              ),
          ]),
        ),
        for (var w = 0; w < weeks; w++)
          Padding(
            padding: EdgeInsets.only(right: w < weeks - 1 ? gap : 0),
            child: Column(children: [
              for (var r = 0; r < 7; r++)
                Builder(builder: (context) {
                  final day = DateTime(start.year, start.month, start.day + w * 7 + r);
                  final key = dayKey(day);
                  final future = day.isAfter(today);
                  final xp = xpByDay[key] ?? 0;
                  return GestureDetector(
                    onTap: future || onTap == null ? null : () => onTap!(key, xp),
                    child: Container(
                      width: cell,
                      height: cell,
                      margin: EdgeInsets.only(bottom: r < 6 ? gap : 0),
                      decoration: BoxDecoration(
                        color: _cell(context, xp, future),
                        borderRadius: BorderRadius.circular(3),
                        border: day == today
                            ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 1.2)
                            : null,
                      ),
                    ),
                  );
                }),
            ]),
          ),
      ]);
    });
  }
}

// ---------- Misc ----------

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Row(children: [
        Text(title, style: serif(26)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class Counter extends StatelessWidget {
  const Counter({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 50,
  });

  final String label;
  final int value;
  final int min, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(width: 24, child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ]),
    ]);
  }
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

Future<double?> askNumber(BuildContext context, {required String title, String? initial, String suffix = ''}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(suffixText: suffix),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(ctrl.text)), child: const Text('Save')),
      ],
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, String title, String body, String action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Celebration dialog for newly unlocked badges.
Future<void> showBadgeUnlocked(BuildContext context, String name, String description, IconData icon) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.3, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.elasticOut,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: InkSeal(name.split(' ').take(2).join('\n'), size: 72),
      ),
      title: Text('Seal earned: $name', textAlign: TextAlign.center),
      content: Text(description, textAlign: TextAlign.center),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nice'))],
    ),
  );
}
