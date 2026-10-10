import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'util.dart';

// ---------- Palette ----------

const proteinColor = Color(0xFFF2777A);
const carbsColor = Color(0xFF5CB8E4);
const fatColor = Color(0xFFE8C547);
const goodColor = Color(0xFF6FCF97);
const warnColor = Color(0xFFF2C94C);
const infoColor = Color(0xFF7FB2F0);
const xpColor = Color(0xFFB794F6);
const fireColor = Color(0xFFFF7A45);

const avatarColors = <Color>[
  Color(0xFFF4A259),
  Color(0xFF6FCF97),
  Color(0xFF7FB2F0),
  Color(0xFFB794F6),
  Color(0xFFF2777A),
  Color(0xFFE8C547),
  Color(0xFF4FD1C5),
  Color(0xFFF687B3),
];

Color avatarColor(int i) => avatarColors[i.abs() % avatarColors.length];

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
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      child: Text(
        initials(name),
        style: TextStyle(color: const Color(0xFF1B1F27), fontWeight: FontWeight.w800, fontSize: size * 0.38),
      ),
    );
    if (level == null) return circle;
    return Stack(clipBehavior: Clip.none, children: [
      circle,
      Positioned(
        right: -4,
        bottom: -4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: xpColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
          ),
          child: Text('$level',
              style: const TextStyle(color: Color(0xFF1B1F27), fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }
}

// ---------- Animated ring ----------

class RingPainter extends CustomPainter {
  RingPainter({required this.value, required this.color, required this.track, this.stroke = 12});
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, base);
    final v = value.clamp(0.0, 1.0).toDouble();
    if (v <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v, false, arc);
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: RingPainter(value: v, color: color, track: color.withAlpha(40), stroke: stroke),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Small ring with a label underneath, used for macros.
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
    final theme = Theme.of(context);
    final pct = target <= 0 ? 0.0 : value / target;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedRing(
        value: pct,
        color: pct > 1.1 ? theme.colorScheme.error : color,
        size: 64,
        stroke: 7,
        child: Text('${value.round()}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: 6),
      Text(label, style: theme.textTheme.labelMedium),
      Text('of ${target.round()} g', style: theme.textTheme.bodySmall),
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
            Text(label, style: theme.textTheme.bodyMedium),
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
          minHeight: height,
          color: color,
          backgroundColor: color.withAlpha(40),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: done ? xpColor : xpColor.withAlpha(40),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '+$xp XP',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: done ? const Color(0xFF1B1F27) : xpColor,
        ),
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
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) Icon(icon, size: 18, color: color ?? theme.colorScheme.primary),
          if (icon != null) const SizedBox(height: 6),
          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall, maxLines: 2),
        ]),
      ),
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
    final base = Theme.of(context).colorScheme.primary;
    if (future) return Colors.transparent;
    if (xp <= 0) return Theme.of(context).colorScheme.surfaceContainerHighest;
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
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
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
        child: CircleAvatar(
          radius: 34,
          backgroundColor: xpColor,
          child: Icon(icon, size: 36, color: const Color(0xFF1B1F27)),
        ),
      ),
      title: Text('Badge unlocked: $name'),
      content: Text(description, textAlign: TextAlign.center),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nice'))],
    ),
  );
}
