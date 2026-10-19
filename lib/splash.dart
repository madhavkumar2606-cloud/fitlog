import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'visuals.dart';

/// Launch animation: an enso brushes itself in, a dumbbell is painted inside it,
/// the red seal stamps on, the name rises, and the whole mark fades into the app.
/// Plays on every launch. Tap to skip. Skipped entirely when the phone asks for reduced motion.

const kSplashBg = Color(0xFF141312);
const _ink = Color(0xFFECE6DA);
const _sealRed = Color(0xFFB5402F);
const _sealText = Color(0xFFF6EFE4);

/// Total length of the intro, in seconds.
const double _total = 2.6;

class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _finish();
      } else {
        _c.forward();
      }
    });
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  void _skip() {
    const fadeStart = 2.22 / _total;
    if (_c.value < fadeStart) _c.value = fadeStart;
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: kSplashBg,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * _total;
            final out = _easeOut(_seg(t, 2.22, _total));
            return Opacity(
              opacity: 1 - out,
              child: _LaunchFrame(t: t, extraScale: 0.06 * out),
            );
          },
        ),
        ),
      ),
    );
  }
}

/// The finished mark, standing still. Shown while the app is still loading after the intro.
class LaunchMark extends StatelessWidget {
  const LaunchMark({super.key});

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: _LaunchFrame(t: 2.1, extraScale: 0),
    );
  }
}

class _LaunchFrame extends StatelessWidget {
  const _LaunchFrame({required this.t, required this.extraScale});

  final double t;
  final double extraScale;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kSplashBg,
      child: LayoutBuilder(builder: (context, box) {
        final logo = math.min(box.maxWidth * 0.56, 240.0);
        final cy = box.maxHeight * 0.45;
        final text = _easeOut(_seg(t, 1.50, 1.95));
        return Transform.scale(
          scale: 1 + extraScale,
          origin: Offset(0, cy - box.maxHeight / 2),
          child: Stack(children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.12),
                    radius: 0.7,
                    colors: [Color(0x12ECE6DA), Color(0x00ECE6DA)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: (box.maxWidth - logo) / 2,
              top: cy - logo / 2,
              width: logo,
              height: logo,
              child: CustomPaint(painter: _LogoPainter(t)),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: cy + logo * 0.6 + 12 * (1 - text),
              child: Opacity(
                opacity: text,
                child: Text(
                  'FitLog',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: Sumi.serif, fontSize: logo * 0.2, color: _ink, letterSpacing: 0.5, fontWeight: FontWeight.w400, decoration: TextDecoration.none),
                ),
              ),
            ),
          ]),
        );
      }),
    );
  }
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();
double _easeOut(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _backOut(double x) {
  const s = 2.2;
  final y = x - 1;
  return y * y * ((s + 1) * y + s) + 1;
}

/// Small deterministic random generator so the bristle pattern is identical on every launch.
class _Lcg {
  _Lcg(this.s);
  int s;
  double next() {
    s = (s * 1103515245 + 12345) % 2147483648;
    return s / 2147483648;
  }

  double uni(double a, double b) => a + (b - a) * next();
}

class _Bristle {
  const _Bristle(this.u, this.width, this.segs);
  final double u;
  final double width;
  final List<List<double>> segs;
}

/// One brush stroke along a centre line, drawn up to a given progress.
class _Stroke {
  _Stroke(Offset Function(double t) fn, this.w, this.seed, this.minW, this.dry, {int bristles = 12})
      : end = dry ? 0.62 : 1.0 {
    pts = List<Offset>.generate(n + 1, (i) => fn(i / n));
    nrm = List<Offset>.generate(n + 1, (i) {
      final d = pts[math.min(n, i + 1)] - pts[math.max(0, i - 1)];
      final l = d.distance == 0 ? 1.0 : d.distance;
      return Offset(-d.dy / l, d.dx / l);
    });
    if (dry) {
      final r = _Lcg(seed);
      for (var k = 0; k < bristles; k++) {
        final u = -0.5 + (k + 0.5) / bristles;
        final centre = 1 - u.abs() * 2;
        final t0 = end - 0.12;
        final t1 = math.min(0.995, end + (1 - end) * (0.45 + 0.55 * centre) + r.uni(-0.05, 0.03));
        final segs = <List<double>>[];
        var t = t0;
        while (t < t1) {
          final e = math.min(t1, t + r.uni(0.03, 0.12));
          segs.add([t, e]);
          t = e + (t > end ? r.uni(0.008, 0.035) : 0.0);
        }
        _bristles.add(_Bristle(u, math.max(1.2, w / bristles * 0.82 * (0.7 + 0.3 * centre)), segs));
      }
    }
  }

  static const int n = 240;
  final double w;
  final int seed;
  final double minW;
  final bool dry;
  final double end;
  late final List<Offset> pts;
  late final List<Offset> nrm;
  final List<_Bristle> _bristles = [];

  double width(double t) {
    var v = w * (1 - (1 - minW) * math.pow(t, 1.5).toDouble()) * (0.9 + 0.1 * math.sin(t * 9 + seed));
    if (t < 0.05) v *= 0.55 + 9 * t;
    return v;
  }

  void paint(Canvas canvas, double q, Color color) {
    if (q <= 0) return;
    final lim = math.min(q, end);
    final outer = <Offset>[];
    final inner = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      if (t > lim) break;
      var wd = width(t);
      if (dry) wd *= 0.25 + 0.75 * ((end - t) / 0.14).clamp(0.0, 1.0).toDouble();
      outer.add(pts[i] + nrm[i] * (wd / 2));
      inner.add(pts[i] - nrm[i] * (wd / 2));
    }
    if (outer.length > 1) {
      final path = Path()..addPolygon([...outer, ...inner.reversed], true);
      canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
    }
    for (final b in _bristles) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = b.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final s in b.segs) {
        if (s[0] >= q) break;
        final stop = math.min(s[1], q);
        final i0 = (s[0] * n).floor();
        final i1 = math.max(i0 + 1, (stop * n).floor());
        final path = Path();
        var started = false;
        for (var i = i0; i <= math.min(n, i1); i++) {
          final p = pts[i] + nrm[i] * (b.u * width(i / n) * 0.96);
          if (started) {
            path.lineTo(p.dx, p.dy);
          } else {
            path.moveTo(p.dx, p.dy);
            started = true;
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }
}

Offset Function(double) _arc(double cx, double cy, double r, double a0, double sweep) {
  return (t) {
    final a = (a0 + sweep * t) * math.pi / 180;
    final wob = r * 0.006;
    final rr = r + wob * math.sin(a * 5 + 1.9) + wob * 0.7 * math.sin(a * 3 + 3.8);
    return Offset(cx + rr * math.cos(a), cy + rr * math.sin(a));
  };
}

Offset Function(double) _line(Offset p0, Offset p1, [double wave = 0]) {
  return (t) => Offset(p0.dx + (p1.dx - p0.dx) * t, p0.dy + (p1.dy - p0.dy) * t + wave * math.sin(t * math.pi));
}

/// The logo strokes, built once. Coordinates are in a 1024 x 1024 box.
class _Logo {
  _Logo._();
  static final _Logo instance = _Logo._();

  final ring = _Stroke(_arc(512, 512, 330, -100, 344), 92, 2, 0.28, true);
  final bar = _Stroke(_line(const Offset(318, 515), const Offset(706, 509), -4), 38, 4, 0.75, false);
  final plates = <_Stroke>[
    _Stroke(_line(const Offset(338, 387), const Offset(335, 637)), 66, 11, 0.62, false),
    _Stroke(_line(const Offset(686, 387), const Offset(683, 637)), 66, 13, 0.62, false),
    _Stroke(_line(const Offset(404, 417), const Offset(407, 607)), 52, 12, 0.62, false),
    _Stroke(_line(const Offset(620, 417), const Offset(623, 607)), 52, 14, 0.62, false),
  ];
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final logo = _Logo.instance;
    canvas.save();
    canvas.scale(size.width / 1024);
    canvas.translate(512, 512);
    canvas.rotate(-14 * math.pi / 180);
    canvas.translate(-512, -512);

    logo.ring.paint(canvas, _easeOut(_seg(t, 0.10, 0.95)), _ink);
    logo.bar.paint(canvas, _easeOut(_seg(t, 0.80, 1.08)), _ink);
    for (var j = 0; j < 4; j++) {
      logo.plates[j].paint(canvas, _easeOut(_seg(t, 0.92 + 0.06 * j, 1.06 + 0.06 * j)), _ink);
    }

    final p = _seg(t, 1.28, 1.60);
    if (p > 0) {
      final scale = p < 1 ? 1.9 - 0.9 * _backOut(p) : 1.0;
      final alpha = math.min(1.0, p * 3);
      const sz = 124.0;
      canvas.save();
      canvas.translate(760, 760);
      canvas.rotate((-7 - 9 * (1 - p)) * math.pi / 180);
      canvas.scale(scale);
      final outer = RRect.fromRectAndRadius(const Rect.fromLTWH(-sz / 2, -sz / 2, sz, sz), const Radius.circular(sz * 0.11));
      canvas.drawRRect(outer, Paint()..color = _sealRed.withValues(alpha: alpha));
      final inner = RRect.fromRectAndRadius(
        Rect.fromLTWH(-sz / 2 + sz * 0.06, -sz / 2 + sz * 0.06, sz * 0.88, sz * 0.88),
        const Radius.circular(sz * 0.06),
      );
      canvas.drawRRect(
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sz * 0.027
          ..color = _sealText.withValues(alpha: 0.55 * alpha),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: 'F',
          style: TextStyle(fontFamily: Sumi.serif, fontSize: sz * 0.79, height: 1, color: _sealText.withValues(alpha: alpha)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.t != t;
}
