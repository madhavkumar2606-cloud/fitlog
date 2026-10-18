import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../db.dart';
import '../util.dart';
import '../visuals.dart';
import '../widgets.dart';

// ---------------- Game model ----------------

class _Obstacle {
  _Obstacle(this.x, this.kind, this.w, this.h);
  double x;
  final int kind; // 0 dumbbell, 1 kettlebell, 2 bench
  final double w, h;
}

class _Item {
  _Item(this.x, this.y, this.kind);
  double x;
  final double y; // height above the floor
  final int kind; // 0 shake, 1 apple, 2 egg, 3 doughnut, 4 burger
  bool get junk => kind >= 3;
}

class _Pop {
  _Pop(this.x, this.y, this.text, this.color);
  double x, y;
  double life = 0.8;
  final String text;
  final Color color;
}

class DashGame {
  static const playerX = 64.0;
  static const playerW = 30.0;
  static const playerH = 56.0;
  static const gravity = 2300.0;
  static const itemPoints = [15, 10, 10, -20, -20];
  static const itemEmoji = ['🥤', '🍎', '🥚', '🍩', '🍔'];

  final _rnd = math.Random();
  Size size = Size.zero;

  bool started = false;
  bool over = false;
  double time = 0;
  double dist = 0;
  double speed = 280;
  double py = 0; // height above the floor
  double vy = 0;
  int jumpsLeft = 2;
  int lives = 3;
  int bonus = 0;
  int healthy = 0;
  double hurt = 0; // seconds of invincibility after a hit
  double _nextObstacle = 1.4;
  double _nextItem = 0.9;
  final obstacles = <_Obstacle>[];
  final items = <_Item>[];
  final pops = <_Pop>[];

  double get floor => size.height * 0.80;
  int get score => math.max(0, (dist / 12).floor() + bonus);

  void reset() {
    started = false;
    over = false;
    time = 0;
    dist = 0;
    speed = 280;
    py = 0;
    vy = 0;
    jumpsLeft = 2;
    lives = 3;
    bonus = 0;
    healthy = 0;
    hurt = 0;
    _nextObstacle = 1.4;
    _nextItem = 0.9;
    obstacles.clear();
    items.clear();
    pops.clear();
  }

  void jump() {
    if (over) return;
    started = true;
    if (jumpsLeft > 0) {
      vy = jumpsLeft == 2 ? 820 : 680;
      jumpsLeft--;
    }
  }

  Rect get playerRect => Rect.fromLTWH(playerX, floor - py - playerH, playerW, playerH);

  void update(double dt) {
    if (!started || over || size == Size.zero) return;
    time += dt;
    speed = math.min(640, 280 + time * 9);
    dist += speed * dt;
    if (hurt > 0) hurt -= dt;

    // Jump physics.
    vy -= gravity * dt;
    py += vy * dt;
    if (py <= 0) {
      py = 0;
      vy = 0;
      jumpsLeft = 2;
    }

    // Spawning.
    _nextObstacle -= dt;
    if (_nextObstacle <= 0) {
      final kind = _rnd.nextInt(3);
      final dims = [
        const Size(54, 30), // dumbbell: wide and low
        const Size(34, 46), // kettlebell: tall
        const Size(70, 34), // bench: widest
      ][kind];
      obstacles.add(_Obstacle(size.width + 20, kind, dims.width, dims.height));
      _nextObstacle = 0.85 + _rnd.nextDouble() * 1.15;
    }
    _nextItem -= dt;
    if (_nextItem <= 0) {
      final junk = _rnd.nextDouble() < 0.3;
      final kind = junk ? 3 + _rnd.nextInt(2) : _rnd.nextInt(3);
      items.add(_Item(size.width + 20, 60 + _rnd.nextDouble() * 150, kind));
      _nextItem = 0.7 + _rnd.nextDouble() * 1.1;
    }

    // Move everything left.
    for (final o in obstacles) {
      o.x -= speed * dt;
    }
    for (final it in items) {
      it.x -= speed * dt;
    }
    obstacles.removeWhere((o) => o.x + o.w < -20);
    items.removeWhere((it) => it.x < -40);
    for (final p in pops) {
      p.life -= dt;
      p.y -= 40 * dt;
    }
    pops.removeWhere((p) => p.life <= 0);

    // Collisions (slightly forgiving boxes).
    final me = playerRect.deflate(5);
    if (hurt <= 0) {
      for (final o in List.of(obstacles)) {
        final r = Rect.fromLTWH(o.x, floor - o.h, o.w, o.h).deflate(4);
        if (r.overlaps(me)) {
          lives--;
          hurt = 1.2;
          obstacles.remove(o);
          pops.add(_Pop(playerX, floor - py - playerH - 10, 'Ouch!', const Color(0xFF8E2F25)));
          if (lives <= 0) over = true;
          break;
        }
      }
    }
    for (final it in List.of(items)) {
      final r = Rect.fromCenter(center: Offset(it.x, floor - it.y), width: 30, height: 30);
      if (r.overlaps(me)) {
        items.remove(it);
        final pts = itemPoints[it.kind];
        bonus += pts;
        if (!it.junk) healthy++;
        pops.add(_Pop(it.x, floor - it.y - 20, pts > 0 ? '+$pts' : '$pts',
            it.junk ? const Color(0xFF8E2F25) : const Color(0xFF151413)));
      }
    }
  }
}

// ---------------- Painter ----------------

class _DashPainter extends CustomPainter {
  _DashPainter(this.g, this.primary);
  final DashGame g;
  final Color primary;

  static final Map<String, TextPainter> _emoji = {};

  TextPainter _tp(String s, double size) {
    return _emoji.putIfAbsent('$s@$size', () {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size)),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final floor = g.floor;
    // Gym wall.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF3F0EA), Color(0xFFEEEBE5)],
        ).createShader(Offset.zero & size),
    );
    // Parallax: windows and racks drifting slowly.
    final wallShift = (g.dist * 0.25) % 220;
    final win = Paint()..color = const Color(0xFFE6E1D8);
    for (var x = -wallShift; x < size.width + 220; x += 220) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + 30, floor - 230, 90, 110), const Radius.circular(6)), win);
      final rack = Paint()
        ..color = const Color(0xFFD3CCC0)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x + 160, floor), Offset(x + 160, floor - 120), rack);
      canvas.drawLine(Offset(x + 200, floor), Offset(x + 200, floor - 120), rack);
      canvas.drawLine(Offset(x + 150, floor - 90), Offset(x + 210, floor - 90), rack);
    }
    // Floor with moving stripes.
    canvas.drawRect(Rect.fromLTWH(0, floor, size.width, size.height - floor), Paint()..color = const Color(0xFFE9E5DE));
    canvas.drawLine(Offset(0, floor), Offset(size.width, floor),
        Paint()
          ..color = primary
          ..strokeWidth = 3);
    final stripe = Paint()..color = const Color(0xFFD9D3C8);
    final floorShift = g.dist % 60;
    for (var x = -floorShift; x < size.width; x += 60) {
      canvas.drawRect(Rect.fromLTWH(x, floor + 14, 30, 6), stripe);
    }

    // Obstacles.
    for (final o in g.obstacles) {
      _obstacle(canvas, o, floor);
    }
    // Items.
    for (final it in g.items) {
      final bob = math.sin((g.time * 4) + it.x / 40) * 4;
      final tp = _tp(DashGame.itemEmoji[it.kind], 28);
      tp.paint(canvas, Offset(it.x - tp.width / 2, floor - it.y - tp.height / 2 + bob));
    }
    // Player (blinks after a hit).
    if (g.hurt <= 0 || (g.hurt * 10).floor().isEven) _player(canvas, floor);

    // Floating points.
    for (final p in g.pops) {
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withAlpha((255 * (p.life / 0.8)).clamp(0, 255).round()),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.x - tp.width / 2, p.y));
    }
  }

  void _obstacle(Canvas c, _Obstacle o, double floor) {
    final metal = Paint()..color = const Color(0xFF6D675E);
    final dark = Paint()..color = const Color(0xFF151413);
    switch (o.kind) {
      case 0: // dumbbell
        final cy = floor - o.h / 2;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.x + 8, cy - 4, o.w - 16, 8), const Radius.circular(3)), metal);
        for (final px in [o.x, o.x + o.w - 14]) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px, floor - o.h, 14, o.h), const Radius.circular(4)), dark);
        }
      case 1: // kettlebell
        final body = Offset(o.x + o.w / 2, floor - o.w / 2);
        c.drawCircle(body, o.w / 2, dark);
        c.drawArc(Rect.fromCenter(center: Offset(body.dx, floor - o.h + 12), width: o.w * 0.7, height: 22), math.pi,
            math.pi, false,
            Paint()
              ..color = dark.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6);
        c.drawCircle(body.translate(-5, -4), 4, Paint()..color = const Color(0x40EEEBE5));
      default: // bench
        final top = floor - o.h;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.x, top, o.w, 10), const Radius.circular(4)),
            Paint()..color = const Color(0xFF151413));
        c.drawRect(Rect.fromLTWH(o.x + 8, top + 10, 6, o.h - 10), metal);
        c.drawRect(Rect.fromLTWH(o.x + o.w - 14, top + 10, 6, o.h - 10), metal);
    }
  }

  void _player(Canvas c, double floor) {
    final r = g.playerRect;
    final hipY = r.bottom - 24;
    final shoulderY = r.top + 18;
    final cx = r.center.dx;
    final line = Paint()
      ..color = const Color(0xFF151413)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final shirt = Paint()
      ..color = primary
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final airborne = g.py > 1;
    final phase = g.time * g.speed / 30;
    final swing = airborne ? 0.0 : math.sin(phase) * 0.9;

    // Legs.
    Offset leg(double a, double len) => Offset(cx + math.sin(a) * len, hipY + math.cos(a) * len);
    if (airborne) {
      c.drawLine(Offset(cx, hipY), Offset(cx + 10, hipY + 12), line);
      c.drawLine(Offset(cx + 10, hipY + 12), Offset(cx - 2, hipY + 20), line);
      c.drawLine(Offset(cx, hipY), Offset(cx - 8, hipY + 14), line);
      c.drawLine(Offset(cx - 8, hipY + 14), Offset(cx - 16, hipY + 8), line);
    } else {
      c.drawLine(Offset(cx, hipY), leg(swing, 24), line);
      c.drawLine(Offset(cx, hipY), leg(-swing, 24), line);
    }
    // Body.
    c.drawLine(Offset(cx, hipY), Offset(cx + 2, shoulderY), shirt);
    // Arms.
    final arm = airborne ? -1.2 : -swing;
    c.drawLine(Offset(cx + 2, shoulderY + 4), Offset(cx + 2 + math.sin(arm) * 18, shoulderY + 4 + math.cos(arm) * 18), line);
    c.drawLine(Offset(cx + 2, shoulderY + 4), Offset(cx + 2 - math.sin(arm) * 18, shoulderY + 4 + math.cos(arm) * 18), line);
    // Head and headband.
    final head = Offset(cx + 3, r.top + 6);
    c.drawCircle(head, 9, Paint()..color = const Color(0xFF151413));
    c.drawLine(head.translate(-9, -3), head.translate(9, -3),
        Paint()
          ..color = const Color(0xFFEEEBE5)
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_DashPainter old) => true;
}

// ---------------- Screen ----------------

const gameXpTiers = [100, 500, 1000];
const gameXpPerTier = 5;

class GymDashScreen extends StatefulWidget {
  const GymDashScreen({super.key});

  @override
  State<GymDashScreen> createState() => _GymDashScreenState();
}

class _GymDashScreenState extends State<GymDashScreen> with SingleTickerProviderStateMixin {
  final _game = DashGame();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _best = 0;
  bool _newBest = false;
  int _xpEarned = 0;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    AppDb.instance.getMeta('game_best').then((v) {
      if (mounted) setState(() => _best = int.tryParse(v ?? '') ?? 0);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
    setState(() => _game.update(dt));
    if (_game.over && !_finishing) _finish();
  }

  void _tap() {
    if (_game.over) return;
    if (!_game.started) {
      _last = Duration.zero;
      if (!_ticker.isActive) _ticker.start();
    }
    _game.jump();
  }

  Future<void> _finish() async {
    _finishing = true;
    _ticker.stop();
    final score = _game.score;
    final today = todayKey();
    var xp = 0;
    for (final t in gameXpTiers) {
      if (score >= t) {
        final added = await AppDb.instance
            .awardXp(XpEvent(today, 'game', '$today:$t', gameXpPerTier, 'Gym Dash: $t points'));
        if (added) xp += gameXpPerTier;
      }
    }
    final isBest = score > _best;
    if (isBest) await AppDb.instance.setMeta('game_best', '$score');
    if (!mounted) return;
    setState(() {
      _xpEarned = xp;
      _newBest = isBest;
      if (isBest) _best = score;
    });
  }

  void _restart() {
    setState(() {
      _game.reset();
      _finishing = false;
      _newBest = false;
      _xpEarned = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = _game;
    return Scaffold(
      backgroundColor: Sumi.paper,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          g.size = box.biggest;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _tap(),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _DashPainter(g, theme.colorScheme.primary))),
              // HUD
              Positioned(
                left: 8,
                top: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Sumi.ink),
                  tooltip: 'Exit game',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 10,
                child: Column(children: [
                  Text('${g.score}', style: serif(38)),
                  Text('Best $_best', style: const TextStyle(fontSize: 12, color: Sumi.muted)),
                ]),
              ),
              Positioned(
                right: 16,
                top: 18,
                child: Row(children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(i < g.lives ? Icons.favorite : Icons.favorite_border,
                          color: Sumi.ink, size: 22),
                    ),
                ]),
              ),
              if (!g.started && !g.over) Center(child: _startCard(theme)),
              if (g.over && _finishing) Center(child: _overCard(theme)),
            ]),
          );
        }),
      ),
    );
  }

  Widget _startCard(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.all(28),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Gym Dash', style: serif(34)),
          const SizedBox(height: 10),
          const Text('Tap to jump. Tap again in the air to double jump.', textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text('Grab 🥤 🍎 🥚 for points\nSkip 🍩 🍔 junk food\nJump over the gym gear',
              textAlign: TextAlign.center, style: TextStyle(height: 1.5)),
          const SizedBox(height: 12),
          Text('Reach 100, 500 and 1,000 points for up to ${gameXpTiers.length * gameXpPerTier} XP a day.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Text('Tap anywhere to start',
              style: serif(18, italic: true)),
        ]),
      ),
    );
  }

  Widget _overCard(ThemeData theme) {
    final g = _game;
    return Card(
      margin: const EdgeInsets.all(28),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_newBest ? 'New best!' : 'Workout over!',
              style: serif(30)),
          const SizedBox(height: 8),
          Text('${g.score}', style: serif(56)),
          Text('points  |  best $_best', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text('${g.healthy} healthy foods grabbed', style: theme.textTheme.bodySmall),
          if (_xpEarned > 0) ...[
            const SizedBox(height: 10),
            XpPill(_xpEarned, done: true),
          ],
          const SizedBox(height: 18),
          Row(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            const SizedBox(width: 12),
            FilledButton(onPressed: _restart, child: const Text('Play again')),
          ]),
        ]),
      ),
    );
  }
}

/// Small card used on the Today screen to open the game.
class GymDashCard extends StatelessWidget {
  const GymDashCard({super.key, required this.best, required this.onPlayed});
  final int best;
  final VoidCallback onPlayed;

  @override
  Widget build(BuildContext context) {
    return SumiCard(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const GymDashScreen()));
        onPlayed();
      },
      child: Row(children: [
        const Enso(value: 0.75, size: 46, stroke: 4, seed: 9, child: Icon(Icons.play_arrow, size: 18, color: Sumi.ink)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Gym Dash', style: serif(22)),
            const SizedBox(height: 2),
            Text(
              best > 0 ? 'Your best: ${fmtInt(best)}. Beat it for bonus xp.' : 'Mini game: dodge the gym gear, grab the protein.',
              style: const TextStyle(fontSize: 12, color: Sumi.muted),
            ),
          ]),
        ),
        const Text('Play  →', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
