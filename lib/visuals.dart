import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------- App background ----------------

/// Deep navy gradient with two soft coloured glows. Used behind the main tabs.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  Widget _glow(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c.withAlpha(70), c.withAlpha(0)]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A2333), Color(0xFF121820)],
              ),
            ),
          ),
        ),
        Positioned(top: -120, right: -100, child: _glow(const Color(0xFFF4A259), 340)),
        Positioned(top: 260, left: -140, child: _glow(const Color(0xFFB794F6), 320)),
        Positioned(bottom: -160, right: -60, child: _glow(const Color(0xFF4FD1C5), 300)),
      ]),
    );
  }
}

// ---------------- Gradient button ----------------

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.colors = const [Color(0xFFF4A259), Color(0xFFE76F51)],
    this.height = 56,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final List<Color> colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          gradient: LinearGradient(colors: colors),
          boxShadow: [BoxShadow(color: colors.last.withAlpha(90), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: onPressed,
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) Icon(icon, color: const Color(0xFF1B1F27)),
                if (icon != null) const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(color: Color(0xFF1B1F27), fontSize: 17, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Food emoji ----------------

const _foodEmoji = <String, String>{
  'omelette': '🍳', 'omlet': '🍳', 'bhurji': '🍳', 'egg': '🥚', 'chicken': '🍗', 'tandoori': '🍗',
  'mutton': '🍖', 'keema': '🍖', 'fish': '🐟', 'prawn': '🦐', 'salmon': '🐟', 'tuna': '🐟',
  'biryani': '🍛', 'pulao': '🍛', 'fried rice': '🍛', 'rice': '🍚', 'khichdi': '🍚', 'pongal': '🍚',
  'dosa': '🥞', 'uttapam': '🥞', 'pesarattu': '🥞', 'idli': '⚪', 'appam': '🥞', 'vada': '🍩',
  'roti': '🫓', 'chapati': '🫓', 'paratha': '🫓', 'naan': '🫓', 'kulcha': '🫓', 'thepla': '🫓', 'puri': '🫓',
  'bhatura': '🫓', 'bread': '🍞', 'toast': '🍞', 'pav': '🍞', 'rusk': '🍞', 'jam': '🍓', 'butter': '🧈',
  'cheese': '🧀', 'paneer': '🧀', 'tofu': '🧀', 'dal': '🥣', 'sambar': '🥣', 'rasam': '🥣', 'rajma': '🫘',
  'chana': '🫘', 'chole': '🫘', 'soya': '🫘', 'sprouts': '🌱', 'curry': '🍲', 'gravy': '🍲', 'masala': '🍲',
  'kurma': '🍲', 'kadhi': '🍲', 'upma': '🥣', 'poha': '🥣', 'oats': '🥣', 'porridge': '🥣', 'dalia': '🥣',
  'muesli': '🥣', 'cornflakes': '🥣', 'milk': '🥛', 'curd': '🥛', 'dahi': '🥛', 'yogurt': '🥛', 'lassi': '🥛',
  'buttermilk': '🥛', 'raita': '🥛', 'whey': '🥤', 'shake': '🥤', 'protein': '💪', 'tea': '🍵', 'coffee': '☕',
  'juice': '🧃', 'coconut': '🥥', 'cola': '🥤', 'soft drink': '🥤', 'banana': '🍌', 'apple': '🍎',
  'mango': '🥭', 'orange': '🍊', 'grapes': '🍇', 'watermelon': '🍉', 'pineapple': '🍍', 'papaya': '🍈',
  'guava': '🍐', 'pomegranate': '🍎', 'dates': '🌴', 'raisins': '🍇', 'almond': '🌰', 'cashew': '🌰',
  'walnut': '🌰', 'peanut': '🥜', 'seeds': '🌰', 'makhana': '🍿', 'popcorn': '🍿', 'potato': '🥔',
  'aloo': '🥔', 'fries': '🍟', 'chips': '🍟', 'corn': '🌽', 'carrot': '🥕', 'tomato': '🍅', 'onion': '🧅',
  'cucumber': '🥒', 'broccoli': '🥦', 'salad': '🥗', 'palak': '🥬', 'bhindi': '🥬', 'gobi': '🥦',
  'baingan': '🍆', 'samosa': '🥟', 'momos': '🥟', 'pakora': '🧆', 'bajji': '🧆', 'bonda': '🧆',
  'dhokla': '🟨', 'noodles': '🍜', 'maggi': '🍜', 'pasta': '🍝', 'pizza': '🍕', 'burger': '🍔',
  'sandwich': '🥪', 'roll': '🌯', 'shawarma': '🌯', 'gulab': '🍡', 'rasgulla': '🍡', 'jalebi': '🥨',
  'kheer': '🍮', 'payasam': '🍮', 'halwa': '🍮', 'laddu': '🟠', 'chocolate': '🍫', 'nutella': '🍫',
  'ice cream': '🍨', 'honey': '🍯', 'sugar': '🍬', 'biscuit': '🍪', 'chikki': '🍬', 'bar': '🍫',
  'ghee': '🧈', 'oil': '🫒', 'pickle': '🫙', 'chutney': '🫙', 'mayonnaise': '🫙', 'quinoa': '🥣',
  'ragi': '🟤', 'bajra': '🫓', 'jowar': '🫓', 'sabudana': '🥣', 'bhel': '🥗', 'pani puri': '🥟',
  'murukku': '🥨', 'mixture': '🥨', 'namkeen': '🥨',
};

// Longer keys first so "fried rice" beats "rice" and "pani puri" beats "puri".
final _emojiKeys = _foodEmoji.keys.toList()..sort((a, b) => b.length.compareTo(a.length));

/// Picks a friendly emoji for a food name.
String foodEmoji(String name) {
  final n = name.toLowerCase();
  for (final k in _emojiKeys) {
    if (n.contains(k)) return _foodEmoji[k]!;
  }
  return '🍽️';
}

const mealEmoji = {'Breakfast': '🍳', 'Lunch': '🍛', 'Dinner': '🍲', 'Snacks': '🍎'};

// ---------------- Animated lifter ----------------

enum LiftKind { press, benchPress, pull, verticalPull, squat, hinge, curl, raise, calf, plank }

LiftKind liftKindFor(String exercise, String muscle) {
  final n = exercise.toLowerCase();
  bool has(String s) => n.contains(s);
  if (has('plank') || has('leg raise')) return LiftKind.plank;
  if (has('calf')) return LiftKind.calf;
  if (has('bench') || has('chest press') || has('incline') || has('fly') || has('skull')) return LiftKind.benchPress;
  if (has('pull-up') || has('pull up') || has('pulldown') || has('chin')) return LiftKind.verticalPull;
  if (has('row') || has('face pull') || has('shrug')) return LiftKind.pull;
  if (has('deadlift') || has('hip thrust') || has('good morning') || has('leg curl')) return LiftKind.hinge;
  if (has('squat') || has('leg press') || has('lunge') || has('extension')) return LiftKind.squat;
  if (has('curl')) return LiftKind.curl;
  if (has('raise')) return LiftKind.raise;
  if (has('press') || has('dip') || has('pushdown')) return LiftKind.press;
  switch (muscle) {
    case 'Back':
      return LiftKind.pull;
    case 'Quads':
    case 'Glutes':
      return LiftKind.squat;
    case 'Hamstrings':
      return LiftKind.hinge;
    case 'Biceps':
      return LiftKind.curl;
    case 'Calves':
      return LiftKind.calf;
    case 'Core':
      return LiftKind.plank;
    default:
      return LiftKind.press;
  }
}

/// Joint positions in a 100 x 100 box (y grows downwards).
class _Pose {
  const _Pose(this.head, this.neck, this.hip, this.knee, this.foot, this.elbow, this.hand);
  final Offset head, neck, hip, knee, foot, elbow, hand;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
        Offset.lerp(a.head, b.head, t)!,
        Offset.lerp(a.neck, b.neck, t)!,
        Offset.lerp(a.hip, b.hip, t)!,
        Offset.lerp(a.knee, b.knee, t)!,
        Offset.lerp(a.foot, b.foot, t)!,
        Offset.lerp(a.elbow, b.elbow, t)!,
        Offset.lerp(a.hand, b.hand, t)!,
      );
}

const _standHead = Offset(50, 16), _standNeck = Offset(50, 27), _standHip = Offset(50, 58);
const _standKnee = Offset(51, 78), _standFoot = Offset(50, 97);

const _poses = <LiftKind, List<_Pose>>{
  LiftKind.press: [
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(63, 36), Offset(58, 25)),
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(57, 13), Offset(54, 1)),
  ],
  LiftKind.benchPress: [
    _Pose(Offset(18, 58), Offset(27, 60), Offset(62, 60), Offset(76, 66), Offset(80, 92), Offset(42, 66), Offset(36, 50)),
    _Pose(Offset(18, 58), Offset(27, 60), Offset(62, 60), Offset(76, 66), Offset(80, 92), Offset(36, 44), Offset(36, 28)),
  ],
  LiftKind.pull: [
    _Pose(Offset(26, 40), Offset(34, 43), Offset(64, 48), Offset(68, 72), Offset(66, 97), Offset(36, 60), Offset(36, 78)),
    _Pose(Offset(26, 40), Offset(34, 43), Offset(64, 48), Offset(68, 72), Offset(66, 97), Offset(52, 46), Offset(42, 62)),
  ],
  LiftKind.verticalPull: [
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(58, 12), Offset(54, 1)),
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(64, 38), Offset(58, 24)),
  ],
  LiftKind.squat: [
    _Pose(_standHead, _standNeck, Offset(50, 56), Offset(52, 77), _standFoot, Offset(40, 32), Offset(45, 24)),
    _Pose(Offset(58, 38), Offset(55, 48), Offset(36, 72), Offset(60, 76), _standFoot, Offset(46, 54), Offset(50, 46)),
  ],
  LiftKind.hinge: [
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(52, 44), Offset(54, 62)),
    _Pose(Offset(76, 46), Offset(68, 50), Offset(44, 54), Offset(48, 76), _standFoot, Offset(66, 66), Offset(64, 84)),
  ],
  LiftKind.curl: [
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(54, 44), Offset(56, 62)),
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(54, 44), Offset(60, 28)),
  ],
  LiftKind.raise: [
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(54, 44), Offset(56, 60)),
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(68, 30), Offset(84, 28)),
  ],
  LiftKind.calf: [
    _Pose(_standHead, _standNeck, _standHip, _standKnee, _standFoot, Offset(54, 42), Offset(54, 58)),
    _Pose(Offset(50, 9), Offset(50, 20), Offset(50, 51), Offset(51, 71), Offset(50, 91), Offset(54, 35), Offset(54, 51)),
  ],
  LiftKind.plank: [
    _Pose(Offset(16, 60), Offset(25, 64), Offset(58, 68), Offset(74, 72), Offset(90, 78), Offset(26, 80), Offset(30, 92)),
    _Pose(Offset(16, 58), Offset(25, 62), Offset(58, 66), Offset(74, 71), Offset(90, 78), Offset(26, 80), Offset(30, 92)),
  ],
};

/// A looping stick-figure animation of the exercise being performed.
class LiftFigure extends StatefulWidget {
  const LiftFigure({super.key, required this.kind, this.color = Colors.white, this.size = 140});
  final LiftKind kind;
  final Color color;
  final double size;

  @override
  State<LiftFigure> createState() => _LiftFigureState();
}

class _LiftFigureState extends State<LiftFigure> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _LiftPainter(widget.kind, Curves.easeInOut.transform(_c.value), widget.color),
        ),
      ),
    );
  }
}

class _LiftPainter extends CustomPainter {
  _LiftPainter(this.kind, this.t, this.color);
  final LiftKind kind;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    Offset p(Offset o) => Offset(o.dx * s, o.dy * s);
    final poses = _poses[kind]!;
    final pose = _Pose.lerp(poses[0], poses[1], t);
    final limb = Paint()
      ..color = color
      ..strokeWidth = 4.2 * s
      ..strokeCap = StrokeCap.round;
    final body = Paint()
      ..color = color
      ..strokeWidth = 6 * s
      ..strokeCap = StrokeCap.round;
    final gear = Paint()
      ..color = const Color(0xFF1B1F27)
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.round;

    // Floor shadow.
    canvas.drawOval(Rect.fromCenter(center: Offset(50 * s, 98 * s), width: 46 * s, height: 5 * s),
        Paint()..color = Colors.black.withAlpha(50));
    if (kind == LiftKind.benchPress) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(12 * s, 63 * s, 58 * s, 6 * s), Radius.circular(2 * s)),
          Paint()..color = Colors.black.withAlpha(80));
      canvas.drawLine(p(const Offset(20, 69)), p(const Offset(20, 97)), gear);
      canvas.drawLine(p(const Offset(62, 69)), p(const Offset(62, 97)), gear);
    }
    // Legs (two, slightly apart).
    canvas.drawLine(p(pose.hip), p(pose.knee), limb);
    canvas.drawLine(p(pose.knee), p(pose.foot), limb);
    canvas.drawLine(p(pose.hip), p(pose.knee.translate(-4, 1)), limb);
    canvas.drawLine(p(pose.knee.translate(-4, 1)), p(pose.foot.translate(-6, 0)), limb);
    // Torso and arm.
    canvas.drawLine(p(pose.hip), p(pose.neck), body);
    canvas.drawLine(p(pose.neck), p(pose.elbow), limb);
    canvas.drawLine(p(pose.elbow), p(pose.hand), limb);
    // Head.
    canvas.drawCircle(p(pose.head), 7.5 * s, Paint()..color = color);
    // Weight in hand.
    if (kind != LiftKind.plank) {
      final h = p(pose.hand);
      final barbell = kind == LiftKind.benchPress || kind == LiftKind.squat || kind == LiftKind.hinge;
      final half = (barbell ? 22 : 7) * s;
      final horizontal = kind != LiftKind.benchPress;
      final a = horizontal ? h.translate(-half, 0) : h.translate(0, -half);
      final b = horizontal ? h.translate(half, 0) : h.translate(0, half);
      canvas.drawLine(a, b, gear..strokeWidth = 3 * s);
      final plate = Paint()..color = const Color(0xFF1B1F27);
      final pw = (barbell ? 4.5 : 4) * s, ph = (barbell ? 15 : 9) * s;
      for (final e in [a, b]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: e, width: horizontal ? pw : ph, height: horizontal ? ph : pw),
                Radius.circular(1.5 * s)),
            plate);
      }
    }
  }

  @override
  bool shouldRepaint(_LiftPainter old) => old.t != t || old.kind != kind || old.color != color;
}

// ---------------- Confetti ----------------

class ConfettiController extends ChangeNotifier {
  int _bursts = 0;
  int get bursts => _bursts;
  void burst() {
    _bursts++;
    notifyListeners();
  }
}

class _Particle {
  _Particle(math.Random r, Size area)
      : x = area.width / 2 + (r.nextDouble() - 0.5) * 60,
        y = area.height * 0.55,
        vx = (r.nextDouble() - 0.5) * 900,
        vy = -500 - r.nextDouble() * 700,
        rot = r.nextDouble() * math.pi,
        spin = (r.nextDouble() - 0.5) * 12,
        size = 6 + r.nextDouble() * 6,
        color = _colors[r.nextInt(_colors.length)];
  double x, y, vx, vy, rot;
  final double spin, size;
  final Color color;
  static const _colors = [
    Color(0xFFF4A259), Color(0xFF6FCF97), Color(0xFF7FB2F0), Color(0xFFB794F6), Color(0xFFF2C94C), Color(0xFFF687B3),
  ];
}

/// Full-screen confetti layer that bursts whenever [controller.burst] is called.
class ConfettiLayer extends StatefulWidget {
  const ConfettiLayer({super.key, required this.controller});
  final ConfettiController controller;

  @override
  State<ConfettiLayer> createState() => _ConfettiLayerState();
}

class _ConfettiLayerState extends State<ConfettiLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  final _rnd = math.Random();
  List<_Particle> _parts = [];
  Size _area = Size.zero;
  double _lastT = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_fire);
    _anim.addListener(_step);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_fire);
    _anim.dispose();
    super.dispose();
  }

  void _fire() {
    if (_area == Size.zero) return;
    _parts = List.generate(70, (_) => _Particle(_rnd, _area));
    _lastT = 0;
    _anim.forward(from: 0);
  }

  void _step() {
    final t = _anim.value * 1.6;
    final dt = (t - _lastT).clamp(0.0, 0.05).toDouble();
    _lastT = t;
    for (final p in _parts) {
      p.vy += 1500 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.spin * dt;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        _area = c.biggest;
        return CustomPaint(
          size: c.biggest,
          painter: _ConfettiPainter(_anim.isAnimating ? _parts : const [], 1 - _anim.value),
        );
      }),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.parts, this.fade);
  final List<_Particle> parts;
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in parts) {
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rot);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          Paint()..color = p.color.withAlpha((255 * fade.clamp(0.0, 1.0)).round()));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}

// ---------------- Pulsing ring ----------------

/// A softly pulsing circle, used to highlight the current set.
class PulseCircle extends StatefulWidget {
  const PulseCircle({super.key, required this.color, required this.child, this.size = 42});
  final Color color;
  final Widget child;
  final double size;

  @override
  State<PulseCircle> createState() => _PulseCircleState();
}

class _PulseCircleState extends State<PulseCircle> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.value;
        return Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: widget.color, width: 2.5),
            boxShadow: [
              BoxShadow(color: widget.color.withAlpha((120 * (1 - v)).round()), blurRadius: 4 + 14 * v, spreadRadius: 6 * v),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
