import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// Sumi design language: washi paper, black ink, ensō circles, serif numbers.
class Sumi {
  static const ink = Color(0xFF151413);
  static const ink2 = Color(0xFF3A3836);
  static const muted = Color(0xFF6D675E);
  static const faint = Color(0xFF9A948A);
  static const rule = Color(0xFFDDD7CC);
  static const edge = Color(0xFFCFC8BB);
  static const paper = Color(0xFFEEEBE5);
  static const porcelain = Color(0xFFFAF8F4);
  static const sheet = Color(0xFFF3F0EA);
  static const wash = Color(0xFFE3DED4);
  static const error = Color(0xFF8E2F25);
  static const serif = 'InstrumentSerif';
  static const sans = 'InterTight';
}

/// Serif text style for titles and numbers.
TextStyle serif(double size, {Color? color, bool italic = false, double height = 1.05}) => TextStyle(
      fontFamily: Sumi.serif,
      fontSize: size,
      fontWeight: FontWeight.w400,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color ?? Sumi.ink,
      height: height,
      letterSpacing: -0.2,
    );

/// Small, widely spaced uppercase label.
class SumiLabel extends StatelessWidget {
  const SumiLabel(this.text, {super.key, this.color, this.size = 10});
  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: Sumi.sans,
          fontSize: size,
          letterSpacing: 2.2,
          fontWeight: FontWeight.w500,
          color: color ?? Sumi.muted,
        ),
      );
}

// ---------- Paper ----------

/// Washi paper: warm off-white with a faint fibre dot texture.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.dark = false});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PaperPainter(dark),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  _PaperPainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? const Color(0xFF121110) : Sumi.paper);
    final a = <Offset>[];
    for (double y = 4; y < size.height; y += 9) {
      for (double x = 3; x < size.width; x += 7) {
        a.add(Offset(x, y));
      }
    }
    canvas.drawPoints(
      PointMode.points,
      a,
      Paint()
        ..color = dark ? const Color(0x10FFFFFF) : const Color(0x40CFC8BB)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.dark != dark;
}

// ---------- Ensō ----------

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Brush width along the stroke: pressed in at the start, tapering and drying at the end.
double _brushWidth(double t) {
  final start = 0.62 + 0.38 * _smooth(t / 0.08);
  final tail = 1 - 0.5 * math.pow(math.max(0.0, (t - 0.5) / 0.5), 1.2).toDouble();
  return start * tail;
}

/// Paints an ensō: a single brushed circle that closes as [value] goes from 0 to 1.
class EnsoPainter extends CustomPainter {
  EnsoPainter({
    required this.value,
    this.color = Sumi.ink,
    this.stroke = 12,
    this.seed = 0,
    this.ghost = true,
    this.gapColor = Sumi.paper,
  });
  final double value;
  final Color color;
  final double stroke;
  final int seed;
  final bool ghost;
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - stroke * 0.75;
    if (r <= 0) return;
    if (ghost) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.45
          ..color = color.withAlpha(20),
      );
    }
    final v = value.clamp(0.0, 1.0).toDouble();
    if (v <= 0.005) return;
    final sweep = 2 * math.pi * math.min(v, 0.965);
    const start = -math.pi / 2 - 0.17;
    final s = seed.toDouble();
    double radius(double t) => r * (1 + 0.012 * math.sin(t * 9 + s) + 0.006 * math.sin(t * 23 + s * 2));
    final n = math.max(16, (sweep * 40).round());
    final outer = <Offset>[];
    final inner = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final a = start + sweep * t;
      final rr = radius(t);
      final w = _brushWidth(t) * stroke;
      final dir = Offset(math.cos(a), math.sin(a));
      outer.add(c + dir * (rr + w / 2));
      inner.add(c + dir * (rr - w / 2));
    }
    final path = Path()..moveTo(outer.first.dx, outer.first.dy);
    for (final p in outer.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in inner.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    final fill = Paint()..color = color;
    canvas.drawPath(path, fill);
    canvas.drawCircle(c + Offset(math.cos(start), math.sin(start)) * radius(0), _brushWidth(0) * stroke / 2, fill);
    // Dry-brush streaks in the tail.
    if (stroke >= 5) {
      final streak = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, stroke * 0.07)
        ..color = gapColor.withAlpha(150);
      for (var k = 0; k < 3; k++) {
        final off = (k - 1) * 0.22;
        final p2 = Path();
        var started = false;
        for (var i = (n * 0.55).round(); i <= n; i++) {
          final t = i / n;
          final a = start + sweep * t;
          final rr = radius(t) + off * _brushWidth(t) * stroke;
          final p = c + Offset(math.cos(a), math.sin(a)) * rr;
          if (!started) {
            p2.moveTo(p.dx, p.dy);
            started = true;
          } else {
            p2.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(p2, streak);
      }
    }
  }

  @override
  bool shouldRepaint(EnsoPainter old) =>
      old.value != value || old.color != color || old.stroke != stroke || old.seed != seed || old.ghost != ghost;
}

/// An animated ensō with content in the middle.
class Enso extends StatelessWidget {
  const Enso({
    super.key,
    required this.value,
    this.size = 120,
    this.stroke = 10,
    this.color = Sumi.ink,
    this.seed = 0,
    this.ghost = true,
    this.gapColor = Sumi.paper,
    this.child,
  });
  final double value;
  final double size;
  final double stroke;
  final Color color;
  final int seed;
  final bool ghost;
  final Color gapColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: EnsoPainter(value: v, color: color, stroke: stroke, seed: seed, ghost: ghost, gapColor: gapColor),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Three ensō nested inside each other, each with its own brush weight.
class TripleEnso extends StatelessWidget {
  const TripleEnso({super.key, required this.values, this.size = 260, this.color = Sumi.ink, this.child});
  final List<double> values;
  final double size;
  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    const strokes = [13.0, 9.0, 6.0];
    final insets = [0.0, size * 0.125, size * 0.225];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        for (var i = 0; i < 3 && i < values.length; i++)
          Enso(
            value: values[i],
            size: size - insets[i] * 2,
            stroke: strokes[i],
            color: color,
            seed: i * 3 + 1,
          ),
        if (child != null) child!,
      ]),
    );
  }
}

// ---------- Brush line ----------

/// A single tapered brush stroke, used as a divider or a legend swatch.
class BrushLine extends StatelessWidget {
  const BrushLine({super.key, this.width, this.thickness = 2.4, this.color = Sumi.ink});
  final double? width;
  final double thickness;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      height: thickness + 6,
      child: CustomPaint(painter: _BrushLinePainter(thickness, color)),
    );
  }
}

class _BrushLinePainter extends CustomPainter {
  _BrushLinePainter(this.thickness, this.color);
  final double thickness;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final mid = size.height / 2;
    const n = 40;
    final top = <Offset>[];
    final bottom = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final x = 1 + (w - 2) * t;
      final y = mid + math.sin(t * math.pi * 1.6) * thickness * 0.35;
      final h = thickness * (0.55 + 0.45 * _smooth(t / 0.1)) * (1 - 0.6 * _smooth((t - 0.6) / 0.4)) / 2;
      top.add(Offset(x, y - h));
      bottom.add(Offset(x, y + h));
    }
    final p = Path()..moveTo(top.first.dx, top.first.dy);
    for (final o in top.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    for (final o in bottom.reversed) {
      p.lineTo(o.dx, o.dy);
    }
    p.close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BrushLinePainter old) => old.thickness != thickness || old.color != color;
}

// ---------- Seal ----------

/// A square ink seal (hanko) used for achievements and records.
class InkSeal extends StatelessWidget {
  const InkSeal(this.text, {super.key, this.size = 46, this.faded = false, this.angle = -0.09});
  final String text;
  final double size;
  final bool faded;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final c = faded ? Sumi.ink.withAlpha(45) : Sumi.ink;
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: c, width: size > 50 ? 2.6 : 2.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, textAlign: TextAlign.center, style: serif(size * 0.3, color: c, height: 1.0)),
          ),
        ),
      ),
    );
  }
}

// ---------- Containers ----------

/// A quiet sheet of paper with a hairline edge.
class SumiCard extends StatelessWidget {
  const SumiCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Sumi.porcelain.withAlpha(200),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Sumi.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// A row with a label on the left, a value on the right and a hairline underneath.
class SumiRow extends StatelessWidget {
  const SumiRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.serifTitle = true,
    this.divider = true,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool serifTitle;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: divider ? const Border(bottom: BorderSide(color: Sumi.rule)) : null),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: serifTitle ? serif(20) : const TextStyle(fontSize: 14.5, color: Sumi.ink)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: const TextStyle(fontSize: 11.5, color: Sumi.muted)),
                ),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

/// Bottom tab bar: text labels with a short brush stroke under the active one.
class SumiTabBar extends StatelessWidget {
  const SumiTabBar({super.key, required this.index, required this.onTap, required this.labels});
  final int index;
  final ValueChanged<int> onTap;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2EEEBE5),
        border: Border(top: BorderSide(color: Sumi.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.3,
                        fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                        color: i == index ? Sumi.ink : Sumi.faint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: i == index ? 1.0 : 0.0,
                      child: const BrushLine(width: 22, thickness: 2.6),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
