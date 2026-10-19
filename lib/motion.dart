import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'visuals.dart';

// Night Ink motion: the glass tab bar, tab-switch transitions and the start-workout ensō.
// Everything respects the phone's "reduce motion" setting.

bool _reduced(BuildContext context) => MediaQuery.of(context).disableAnimations;

// ---------------------------------------------------------------------------
// Glass tab bar
// ---------------------------------------------------------------------------

/// Floating translucent tab bar. The active tab sits inside a small glass bubble that glides
/// and wobbles like a water droplet when you switch. Light ripples drift across the glass.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({super.key, required this.index, required this.onTap, required this.labels});

  final int index;
  final ValueChanged<int> onTap;
  final List<String> labels;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> with TickerProviderStateMixin {
  late final AnimationController _jelly = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _water = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  static const _labelStyle = TextStyle(fontFamily: Sumi.sans, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduced(context)) {
      _water.stop();
    } else if (!_water.isAnimating) {
      _water.repeat();
    }
  }

  @override
  void didUpdateWidget(GlassTabBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !_reduced(context)) _jelly.forward(from: 0);
  }

  @override
  void dispose() {
    _jelly.dispose();
    _water.dispose();
    super.dispose();
  }

  double _labelWidth(String text) {
    final tp = TextPainter(text: TextSpan(text: text, style: _labelStyle), textDirection: TextDirection.ltr)..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = _reduced(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(builder: (context, box) {
            final n = widget.labels.length;
            final slot = box.maxWidth / n;
            final bubbleW = math.min(slot + 10, _labelWidth(widget.labels[widget.index]) + 30);
            final left = slot * widget.index + (slot - bubbleW) / 2;
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 26, offset: Offset(0, 10))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                  child: Stack(children: [
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x40262421), Color(0x59141312)],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(child: IgnorePointer(child: CustomPaint(painter: _WaterPainter(_water)))),
                    ),
                    AnimatedPositioned(
                      duration: reduced ? Duration.zero : const Duration(milliseconds: 560),
                      curve: Curves.easeOutBack,
                      left: left,
                      top: 9,
                      width: bubbleW,
                      height: 46,
                      child: AnimatedBuilder(
                        animation: _jelly,
                        builder: (context, child) {
                          final t = _jelly.value;
                          final wobble = math.sin(t * math.pi * 2.2) * (1 - t);
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(1 + 0.28 * wobble, 1 - 0.16 * wobble, 1),
                            child: child,
                          );
                        },
                        child: const _Bubble(),
                      ),
                    ),
                    Row(children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: i == widget.index,
                            label: widget.labels[i],
                            excludeSemantics: true,
                            onTap: () => widget.onTap(i),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onTap(i),
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 260),
                                  style: _labelStyle.copyWith(
                                    color: i == widget.index ? const Color(0xFFFFFFFF) : Sumi.muted,
                                    fontWeight: i == widget.index ? FontWeight.w600 : FontWeight.w400,
                                    shadows: const [Shadow(color: Color(0xD9000000), blurRadius: 8)],
                                  ),
                                  child: Text(widget.labels[i]),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    const Positioned.fill(child: IgnorePointer(child: _GlassRim(radius: 32))),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// The droplet that marks the active tab.
class _Bubble extends StatelessWidget {
  const _Bubble();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33FFFAF0), Color(0x0AFFFAF0), Color(0x1AFFFAF0)],
          stops: [0, 0.6, 1],
        ),
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: const _GlassRim(radius: 23, strong: true),
    );
  }
}

/// Bright top-left edge and soft bottom-right edge, like light caught on curved glass.
class _GlassRim extends StatelessWidget {
  const _GlassRim({required this.radius, this.strong = false});

  final double radius;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _RimPainter(radius, strong));
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.radius, this.strong);

  final double radius;
  final bool strong;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), Radius.circular(radius));
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: strong
          ? const [Color(0xB3FFFFFF), Color(0x14FFFFFF), Color(0x40FFFFFF)]
          : const [Color(0x80FFFFFF), Color(0x0FFFFFFF), Color(0x33FFFFFF)],
      stops: const [0, 0.55, 1],
    ).createShader(Offset.zero & size);
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = shader,
    );
    final glow = RadialGradient(
      center: const Alignment(-0.75, -1.1),
      radius: 0.9,
      colors: [Color(strong ? 0x33FFFFFF : 0x24FFFFFF), const Color(0x00FFFFFF)],
    ).createShader(Offset.zero & size);
    canvas.drawRRect(r, Paint()..shader = glow);
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.radius != radius || old.strong != strong;
}

/// Slow drifting light ripples across the glass, like sunlight through moving water.
class _WaterPainter extends CustomPainter {
  _WaterPainter(this.anim) : super(repaint: anim);

  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = anim.value * math.pi * 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x14FFFFFF);
    for (var k = 0; k < 4; k++) {
      final path = Path();
      final baseY = size.height * (0.2 + 0.2 * k);
      for (var x = 0.0; x <= size.width; x += 6) {
        final y = baseY +
            3.5 * math.sin(x / 38 + phase + k * 1.7) +
            2.0 * math.sin(x / 17 - phase * 2 + k);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
    final cx = size.width * (0.5 + 0.42 * math.sin(phase));
    canvas.drawCircle(
      Offset(cx, size.height * 0.35),
      size.height * 0.9,
      Paint()
        ..shader = RadialGradient(colors: const [Color(0x10FFFFFF), Color(0x00FFFFFF)])
            .createShader(Rect.fromCircle(center: Offset(cx, size.height * 0.35), radius: size.height * 0.9)),
    );
  }

  @override
  bool shouldRepaint(_WaterPainter old) => false;
}

// ---------------------------------------------------------------------------
// Tab switching
// ---------------------------------------------------------------------------

/// Switches between tab pages: the old page slips away and blurs, the new one springs in from the
/// direction you are moving and is revealed top to bottom like ink soaking down the paper.
/// Ensō rings on the new page repaint themselves because the page is rebuilt.
class InkTabSwitcher extends StatefulWidget {
  const InkTabSwitcher({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<InkTabSwitcher> createState() => _InkTabSwitcherState();
}

class _InkTabSwitcherState extends State<InkTabSwitcher> {
  int _dir = 1;

  @override
  void didUpdateWidget(InkTabSwitcher old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _dir = widget.index > old.index ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = _reduced(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 680),
      reverseDuration: reduced ? Duration.zero : const Duration(milliseconds: 260),
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<int>(widget.index);
        return _TabTransition(animation: animation, incoming: incoming, dir: _dir, child: child);
      },
      child: KeyedSubtree(key: ValueKey<int>(widget.index), child: widget.child),
    );
  }
}

class _TabTransition extends StatelessWidget {
  const _TabTransition({required this.animation, required this.incoming, required this.dir, required this.child});

  final Animation<double> animation;
  final bool incoming;
  final int dir;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final v = animation.value;
        if (incoming) {
          final spring = Curves.easeOutBack.transform(v);
          final fade = Curves.easeOut.transform(math.min(1.0, v * 1.8));
          final reveal = Curves.easeOutCubic.transform(v);
          return Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(dir * 72 * (1 - spring), 0),
              child: Transform.scale(
                scale: 0.94 + 0.06 * spring,
                child: ClipRect(
                  clipper: _RevealClipper(reveal.clamp(0.0, 1.0).toDouble()),
                  child: child,
                ),
              ),
            ),
          );
        }
        final p = 1 - v;
        final ease = Curves.easeIn.transform(p);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(-dir * 46 * ease, 0),
            child: Transform.scale(
              scale: 1 - 0.06 * ease,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 5 * ease + 0.001, sigmaY: 5 * ease + 0.001),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Reveals the incoming page from the top down. A plain clip: cheap, and harmless once fully open.
class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height * fraction);

  @override
  bool shouldReclip(_RevealClipper old) => old.fraction != fraction;
}

// ---------------------------------------------------------------------------
// Start-workout ceremony
// ---------------------------------------------------------------------------

/// Opens a workout with a short ceremony: the screen turns to black paper, an ensō paints itself,
/// the routine name rises with "Breathe. Begin.", a red Go seal stamps on, then the ensō rushes
/// toward you and the workout screen rises in behind it. Tap anywhere to skip straight to the end.
Route<T> inkWorkoutRoute<T>({required String title, required Widget page}) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (context, animation, secondary) => _WorkoutIntro(title: title, child: page),
    transitionsBuilder: (context, animation, secondary, child) {
      if (animation.status == AnimationStatus.reverse) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      }
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _WorkoutIntro extends StatefulWidget {
  const _WorkoutIntro({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_WorkoutIntro> createState() => _WorkoutIntroState();
}

class _WorkoutIntroState extends State<_WorkoutIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2300));
  final _pageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reduced(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (_c.value < 0.62) _c.value = 0.62;
    _c.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        if (_c.value >= 1) return child!;
        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: ColoredBox(
              color: Sumi.paper,
              child: _EnsoCeremony(t: _c.value, title: widget.title, child: child!),
            ),
          ),
        );
      },
      child: KeyedSubtree(key: _pageKey, child: widget.child),
    );
  }
}

double _iv(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();

class _EnsoCeremony extends StatelessWidget {
  const _EnsoCeremony({required this.t, required this.title, required this.child});

  final double t;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (t >= 1) return child;
    final veil = 1 - Curves.easeIn.transform(_iv(t, 0.78, 0.97));
    final draw = Curves.easeOutCubic.transform(_iv(t, 0.06, 0.42));
    final words = Curves.easeOutCubic.transform(_iv(t, 0.38, 0.55));
    final sealP = _iv(t, 0.46, 0.6);
    final zoom = Curves.easeInCubic.transform(_iv(t, 0.64, 0.9));
    final pageIn = Curves.easeOutCubic.transform(_iv(t, 0.62, 0.84));
    final ring = math.min(MediaQuery.sizeOf(context).width * 0.72, 300.0);
    final sealScale = sealP <= 0 ? 0.0 : (sealP >= 1 ? 1.0 : 1.9 - 0.9 * Curves.easeOutBack.transform(sealP));

    return Stack(fit: StackFit.expand, children: [
      Opacity(
        opacity: pageIn,
        child: Transform.translate(offset: Offset(0, 40 * (1 - pageIn)), child: child),
      ),
      if (veil > 0)
        IgnorePointer(
          child: Opacity(
            opacity: veil.clamp(0.0, 1.0).toDouble(),
            child: const ColoredBox(color: Sumi.paper, child: AppBackground()),
          ),
        ),
      if (zoom < 1)
        IgnorePointer(
          child: Center(
            child: Opacity(
              opacity: 1 - zoom,
              child: Transform.scale(
                scale: 1 + 4.5 * zoom,
                child: SizedBox(
                  width: ring,
                  height: ring,
                  child: Stack(alignment: Alignment.center, children: [
                    Positioned.fill(
                      child: CustomPaint(painter: EnsoPainter(value: 0.97 * draw, stroke: ring * 0.06, seed: 3, ghost: false)),
                    ),
                    Opacity(
                      opacity: words,
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - words)),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(title, textAlign: TextAlign.center, style: serif(ring * 0.15)),
                          const SizedBox(height: 6),
                          Text('Breathe. Begin.', style: serif(17, italic: true, color: Sumi.muted)),
                        ]),
                      ),
                    ),
                    if (sealScale > 0)
                      Positioned(
                        right: ring * 0.06,
                        bottom: ring * 0.08,
                        child: Transform.rotate(
                          angle: (-8 - 8 * (1 - sealP)) * math.pi / 180,
                          child: Transform.scale(
                            scale: sealScale,
                            child: Container(
                              width: 54,
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Sumi.seal,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0x47F6EFE4), width: 2.5),
                              ),
                              child: Text('Go', style: serif(19, color: Sumi.sealText, height: 1)),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
