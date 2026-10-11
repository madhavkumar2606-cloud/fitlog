import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../db.dart';
import '../game.dart';
import '../session.dart';
import '../update.dart';
import '../util.dart';
import '../widgets.dart';
import 'access_screen.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  GameState? _game;
  String _name = '';
  Map<String, int> _xpByDay = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await Game.refresh();
    final p = await AppDb.instance.getProfile();
    final xp = await AppDb.instance.xpByDay(daysAgoKey(13));
    if (!mounted) return;
    setState(() {
      _game = g;
      _name = p?.name ?? '';
      _xpByDay = xp;
    });
  }

  Future<void> _signOut() async {
    final session = AppSession.instance;
    final ok = await confirmDialog(
      context,
      session.isAccount ? 'Sign out?' : 'Sign in or create an account?',
      session.isAccount
          ? 'Your data stays saved in your account on this phone. Sign back in any time.'
          : 'Your offline data will move into the account you sign in with.',
      session.isAccount ? 'Sign out' : 'Continue',
    );
    if (!ok || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await session.signOut();
  }

  Future<void> _checkUpdate() async {
    UpdateInfo? info;
    try {
      info = await Updater.check();
    } catch (_) {
      if (mounted) showSnack(context, 'Could not check. Make sure you are online.');
      return;
    }
    if (!mounted) return;
    if (info == null) {
      showSnack(context, AppInfo.version.isEmpty ? 'Update checks only work in the GitHub version.' : 'You have the latest version.');
      return;
    }
    await Updater.showUpdateDialog(context, info);
  }

  void _showBadge(BadgeDef b, bool earned, String? date) {
    final g = _game!;
    final theme = Theme.of(context);
    final value = b.value(g.stats);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: earned ? xpColor : theme.colorScheme.surfaceContainerHighest,
            child: Icon(b.icon, size: 36, color: earned ? const Color(0xFF1B1F27) : theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text(b.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(b.description, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (earned)
            Text(date == null ? 'Unlocked' : 'Unlocked: ${prettyDay(date)}',
                style: const TextStyle(color: goodColor))
          else ...[
            AnimatedBar(value: b.progress(g.stats), color: xpColor, height: 10),
            const SizedBox(height: 6),
            Text('${fmtInt(value.clamp(0, b.target))} / ${fmtInt(b.target)}', style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _game;
    final session = AppSession.instance;
    final me = session.me;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: g == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Center(
                  child: AnimatedRing(
                    value: g.levelProgress,
                    color: xpColor,
                    size: 120,
                    stroke: 8,
                    child: Avatar(
                      name: _name.isEmpty ? (me?.displayName ?? '?') : _name,
                      color: me?.avatarColor ?? 0,
                      size: 88,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(_name.isEmpty ? (me?.displayName ?? 'You') : _name,
                    textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                Text(
                  me != null ? '@${me.username}' : (session.isAccount ? 'Signed in' : 'Offline, on this phone only'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text('Level ${g.level} ${g.title}  |  ${fmtInt(g.totalXp)} XP',
                    textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.copyWith(color: xpColor)),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.9,
                  children: [
                    StatTile(value: '${g.streak}', label: 'day streak', icon: Icons.local_fire_department, color: fireColor),
                    StatTile(value: '${g.stats.bestStreak}', label: 'best streak', icon: Icons.whatshot, color: fireColor),
                    StatTile(value: '${g.stats.workouts}', label: 'workouts', icon: Icons.fitness_center),
                    StatTile(value: '${g.stats.prs}', label: 'personal records', icon: Icons.emoji_events, color: warnColor),
                    StatTile(value: '${g.stats.questsDone}', label: 'quests done', icon: Icons.task_alt, color: goodColor),
                    StatTile(value: '${g.earned.length}', label: 'badges', icon: Icons.military_tech, color: xpColor),
                  ],
                ),
                const SizedBox(height: 12),
                _xpChart(),
                SectionHeader(title: 'Badges', trailing: Text('${g.earned.length} / ${badgeDefs.length}')),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.7,
                  children: [
                    for (final b in badgeDefs) _badgeCell(b, g),
                  ],
                ),
                const SizedBox(height: 16),
                if (session.isAdmin)
                  Card(
                    color: xpColor.withAlpha(30),
                    child: Column(children: [
                      ListTile(
                        leading: const Icon(Icons.verified_user_outlined, color: xpColor),
                        title: const Text('Access requests'),
                        subtitle: const Text('Approve people who paid or got a free invite'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const AdminAccessScreen())),
                      ),
                      ListTile(
                        leading: const Icon(Icons.qr_code_2, color: xpColor),
                        title: const Text('Payment settings'),
                        subtitle: const Text('UPI ID, price and message'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const PaymentSettingsScreen())),
                      ),
                    ]),
                  ),
                if (!session.isAdmin && session.access?.accessUntil != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.event_available, color: goodColor),
                      title: Text('Access until ${shortDate(dayKey(session.access!.accessUntil!))}'),
                      subtitle: const Text('You will be asked to renew after this date'),
                    ),
                  ),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Body stats and goal'),
                      subtitle: const Text('Weight, height, activity, lose / maintain / gain'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                        await _load();
                      },
                    ),
                    if (session.isAccount && me != null)
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: const Text('Public profile'),
                        subtitle: const Text('Name, username and colour your friends see'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                              context, MaterialPageRoute(builder: (_) => const UsernameScreen(editing: true)));
                          if (mounted) setState(() {});
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.system_update_outlined),
                      title: const Text('Check for updates'),
                      subtitle: Text('You have ${AppInfo.label}'),
                      onTap: _checkUpdate,
                    ),
                    ListTile(
                      leading: Icon(session.isAccount ? Icons.logout : Icons.login),
                      title: Text(session.isAccount ? 'Sign out' : 'Sign in to add friends'),
                      onTap: _signOut,
                    ),
                  ]),
                ),
              ],
            ),
    );
  }

  Widget _badgeCell(BadgeDef b, GameState g) {
    final theme = Theme.of(context);
    final earned = g.earned.containsKey(b.id);
    return GestureDetector(
      onTap: () => _showBadge(b, earned, g.earned[b.id]),
      child: Column(children: [
        Stack(alignment: Alignment.center, children: [
          if (!earned)
            AnimatedRing(value: b.progress(g.stats), color: xpColor, size: 60, stroke: 4),
          CircleAvatar(
            radius: earned ? 30 : 24,
            backgroundColor: earned ? xpColor : theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              earned ? b.icon : Icons.lock_outline,
              color: earned ? const Color(0xFF1B1F27) : theme.colorScheme.onSurfaceVariant,
              size: earned ? 28 : 20,
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          b.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: theme.textTheme.labelSmall?.copyWith(
            color: earned ? null : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ]),
    );
  }

  Widget _xpChart() {
    final theme = Theme.of(context);
    final days = [for (var i = 13; i >= 0; i--) daysAgoKey(i)];
    final values = [for (final d in days) (_xpByDay[d] ?? 0).toDouble()];
    final top = values.fold<double>(10, (a, b) => b > a ? b : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text('XP over the last 2 weeks', style: theme.textTheme.titleMedium),
          ),
          SizedBox(
            height: 150,
            child: BarChart(BarChartData(
              maxY: top * 1.15,
              minY: 0,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    '${prettyDay(days[group.x])}\n${rod.toY.round()} XP',
                    TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= days.length || (i % 2 != 1)) return const SizedBox.shrink();
                      final d = parseDay(days[i]);
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${d.day}', style: theme.textTheme.labelSmall),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: values[i],
                      width: 12,
                      color: i == days.length - 1 ? xpColor : xpColor.withAlpha(150),
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
}
