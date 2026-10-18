import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game.dart';
import '../session.dart';
import '../social.dart';
import '../util.dart';
import '../visuals.dart';
import '../widgets.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    if (!session.isAccount || !Social.instance.available) {
      return Scaffold(
          backgroundColor: Colors.transparent, appBar: AppBar(title: const Text('Friends')), body: const _SignInPitch());
    }
    if (session.me == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Friends')),
        body: const EmptyNote('Could not reach the server. Check your internet, then reopen the app.'),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Friends'),
          bottom: const TabBar(tabs: [Tab(text: 'Leaderboard'), Tab(text: 'Friends')]),
        ),
        body: const TabBarView(children: [_LeaderboardTab(), _FriendsTab()]),
      ),
    );
  }
}

class _SignInPitch extends StatelessWidget {
  const _SignInPitch();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = AppSession.instance.backend;
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.emoji_events, size: 64, color: warnColor),
      const SizedBox(height: 12),
      Text('Compete with friends', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 20),
      point(Icons.leaderboard, 'A weekly leaderboard that resets every Monday'),
      point(Icons.bolt, 'Earn XP from workouts, records and daily quests'),
      point(Icons.military_tech, "See your friends' levels, streaks and badges"),
      const SizedBox(height: 24),
      if (online)
        FilledButton(
          onPressed: AppSession.instance.signOut,
          child: const Text('Sign in or create an account'),
        )
      else
        Text(
          'Online features are not set up in this version of the app.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
    ]);
  }
}

// ---------------- Leaderboard ----------------

class _LeaderboardTab extends StatefulWidget {
  const _LeaderboardTab();

  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab> {
  List<LeaderRow>? _rows;
  GameState? _game;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await Game.refresh();
      await Social.instance.sync(g);
      final rows = await Social.instance.leaderboard();
      if (!mounted) return;
      setState(() {
        _game = g;
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  int _questXpLeft(GameState g) {
    var left = 0;
    for (final q in g.quests) {
      if (!q.done) left += q.def.xp;
    }
    if (!g.allQuestsDone) left += XpRules.allQuestsBonus;
    return left;
  }

  String _message(List<LeaderRow> rows, GameState g) {
    final i = rows.indexWhere((r) => r.isMe);
    if (rows.length <= 1) return 'Add friends to start competing. The leaderboard resets every Monday.';
    if (i == 0) {
      final lead = rows[0].xp - rows[1].xp;
      return lead == 0
          ? 'You are tied for first with ${firstName(rows[1].profile.displayName)}. One quest breaks the tie.'
          : 'You are leading by $lead XP over ${firstName(rows[1].profile.displayName)}. Keep it up!';
    }
    final gap = rows[i - 1].xp - rows[i].xp;
    final left = _questXpLeft(g);
    final who = firstName(rows[i - 1].profile.displayName);
    final hint = left >= gap && gap > 0
        ? " Finishing today's quests (up to $left XP) would put you ahead."
        : ' A workout is worth 40 to 100 XP.';
    return 'You are #${i + 1}, $gap XP behind $who.$hint';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final g = _game;
    if (_error != null && rows == null) {
      return ListView(children: [
        EmptyNote(_error!),
        Center(child: FilledButton(onPressed: _load, child: const Text('Try again'))),
      ]);
    }
    if (rows == null || g == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final ws = weekStart(DateTime.now());
    final we = DateTime(ws.year, ws.month, ws.day + 6);
    final resetIn = 7 - (DateTime.now().weekday - 1);
    final leader = rows.isEmpty ? 1 : (rows.first.xp <= 0 ? 1 : rows.first.xp);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(children: [
            Text('${shortDate(dayKey(ws))} to ${shortDate(dayKey(we))}', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text(resetIn == 1 ? 'Resets tomorrow' : 'Resets in $resetIn days', style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 12),
          _Podium(rows: rows.take(3).toList()),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.primary.withAlpha(30),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.campaign_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(_message(rows, g))),
              ]),
            ),
          ),
          if (rows.length <= 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: () => DefaultTabController.of(context).animateTo(1),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add friends'),
              ),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++)
            Card(
              shape: rows[i].isMe
                  ? RoundedRectangleBorder(
                      side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: rows[i].isMe
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FriendProfileScreen(profile: rows[i].profile)),
                        ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
                  child: Row(children: [
                    SizedBox(
                      width: 28,
                      child: Text('${i + 1}',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    Avatar(
                      name: rows[i].profile.displayName,
                      color: rows[i].profile.avatarColor,
                      size: 40,
                      level: rows[i].profile.level,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              rows[i].isMe ? 'You' : rows[i].profile.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          Text('${fmtInt(rows[i].xp)} XP',
                              style: theme.textTheme.titleSmall?.copyWith(color: xpColor, fontWeight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 6),
                        AnimatedBar(value: rows[i].xp / leader, color: rows[i].isMe ? theme.colorScheme.primary : xpColor),
                        const SizedBox(height: 4),
                        Text(
                          '${rows[i].workouts} ${rows[i].workouts == 1 ? 'workout' : 'workouts'} this week'
                          '${rows[i].profile.streak > 0 ? '  |  ${rows[i].profile.streak}-day streak' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            "Friends' scores update when they open FitLog.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.rows});
  final List<LeaderRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // Display order: 2nd, 1st, 3rd.
    final order = <int>[if (rows.length > 1) 1, 0, if (rows.length > 2) 2];
    const heights = [120.0, 88.0, 64.0];
    const medal = [Sumi.ink, Sumi.ink2, Color(0xFF827C72)];
    return SizedBox(
      height: 290,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final i in order)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (i == 0) const Icon(Icons.workspace_premium, color: Sumi.ink, size: 28),
                Avatar(name: rows[i].profile.displayName, color: rows[i].profile.avatarColor, size: i == 0 ? 56 : 46),
                const SizedBox(height: 6),
                Text(
                  rows[i].isMe ? 'You' : firstName(rows[i].profile.displayName),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
                Text('${fmtInt(rows[i].xp)} XP', style: theme.textTheme.labelSmall?.copyWith(color: xpColor)),
                const SizedBox(height: 6),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: heights[i]),
                  duration: Duration(milliseconds: 600 + 200 * i),
                  curve: Curves.easeOutBack,
                  builder: (context, h, _) => Container(
                    height: h < 0 ? 0 : h,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.topCenter,
                    padding: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: medal[i].withAlpha(rows[i].isMe ? 255 : 170),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w900, color: Sumi.porcelain)),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ---------------- Friends ----------------

class _FriendsTab extends StatefulWidget {
  const _FriendsTab();

  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  final _search = TextEditingController();
  List<FriendLink>? _links;
  List<PublicProfile> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final links = await Social.instance.friendLinks();
      if (!mounted) return;
      setState(() {
        _links = links;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final r = await Social.instance.searchUsers(q);
      if (!mounted) return;
      setState(() => _results = r);
      if (r.isEmpty) showSnack(context, 'No one found with a username like "$q".');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showSnack(context, done);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  FriendLink? _linkWith(String id) {
    for (final l in _links ?? const <FriendLink>[]) {
      if (l.other.id == id) return l;
    }
    return null;
  }

  Widget _relationButton(PublicProfile p) {
    final link = _linkWith(p.id);
    if (link == null) {
      return FilledButton.tonal(
        onPressed: () => _act(() => Social.instance.sendRequest(p.id), 'Request sent to ${p.displayName}'),
        child: const Text('Add'),
      );
    }
    if (link.accepted) return const Chip(label: Text('Friends'));
    if (link.incoming) {
      return FilledButton(
        onPressed: () => _act(() => Social.instance.accept(link.id), 'You and ${p.displayName} are now friends'),
        child: const Text('Accept'),
      );
    }
    return const Chip(label: Text('Requested'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = AppSession.instance.me!;
    final links = _links;
    final incoming = links?.where((l) => l.incoming && !l.accepted).toList() ?? [];
    final outgoing = links?.where((l) => !l.incoming && !l.accepted).toList() ?? [];
    final friends = links?.where((l) => l.accepted).toList() ?? [];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: ListTile(
              leading: Avatar(name: me.displayName, color: me.avatarColor),
              title: Text('@${me.username}'),
              subtitle: const Text('Share your username so friends can add you'),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy username',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: me.username));
                  if (context.mounted) showSnack(context, 'Copied @${me.username}');
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            onSubmitted: (_) => _doSearch(),
            decoration: InputDecoration(
              hintText: 'Find friends by username',
              prefixIcon: const Icon(Icons.person_search),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(icon: const Icon(Icons.search), tooltip: 'Search', onPressed: _doSearch),
            ),
          ),
          for (final p in _results)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Avatar(name: p.displayName, color: p.avatarColor, level: p.level),
              title: Text(p.displayName),
              subtitle: Text('@${p.username}'),
              trailing: _relationButton(p),
            ),
          if (_error != null) EmptyNote(_error!),
          if (links == null && _error == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (incoming.isNotEmpty) ...[
            SectionHeader(title: 'Requests (${incoming.length})'),
            for (final l in incoming)
              Card(
                child: ListTile(
                  leading: Avatar(name: l.other.displayName, color: l.other.avatarColor, level: l.other.level),
                  title: Text(l.other.displayName),
                  subtitle: Text('@${l.other.username} wants to be friends'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Decline',
                      onPressed: () => _act(() => Social.instance.removeLink(l.id), 'Request declined'),
                    ),
                    IconButton.filled(
                      icon: const Icon(Icons.check),
                      tooltip: 'Accept',
                      onPressed: () =>
                          _act(() => Social.instance.accept(l.id), 'You and ${l.other.displayName} are now friends'),
                    ),
                  ]),
                ),
              ),
          ],
          if (links != null) ...[
            SectionHeader(title: 'Friends (${friends.length})'),
            if (friends.isEmpty)
              const EmptyNote('No friends yet. Search for a username above to send a request.'),
            for (final l in friends)
              Card(
                child: ListTile(
                  leading: Avatar(name: l.other.displayName, color: l.other.avatarColor, level: l.other.level),
                  title: Text(l.other.displayName),
                  subtitle: Text(
                      '@${l.other.username}  |  Level ${l.other.level} ${levelTitle(l.other.level)}'
                      '${l.other.streak > 0 ? '  |  ${l.other.streak}-day streak' : ''}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FriendProfileScreen(profile: l.other)),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (_) async {
                      final ok = await confirmDialog(context, 'Remove ${l.other.displayName}?',
                          'You will no longer see each other on the leaderboard.', 'Remove');
                      if (ok) await _act(() => Social.instance.removeLink(l.id), 'Friend removed');
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove friend'))],
                  ),
                ),
              ),
          ],
          if (outgoing.isNotEmpty) ...[
            const SectionHeader(title: 'Waiting for a reply'),
            for (final l in outgoing)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Avatar(name: l.other.displayName, color: l.other.avatarColor),
                title: Text(l.other.displayName),
                subtitle: Text('@${l.other.username}'),
                trailing: TextButton(
                  onPressed: () => _act(() => Social.instance.removeLink(l.id), 'Request cancelled'),
                  child: const Text('Cancel'),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text('Friends see your name, level, streak, weekly XP and badges. Never your food or weight.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ---------------- Friend profile ----------------

class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({super.key, required this.profile});
  final PublicProfile profile;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  FriendDetail? _detail;
  GameState? _mine;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Social.instance.friendDetail(widget.profile.id);
      final g = await Game.refresh();
      if (!mounted) return;
      setState(() {
        _detail = d;
        _mine = g;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _detail;
    final p = d?.profile ?? widget.profile;
    final level = levelFor(p.totalXp);
    final progress = (p.totalXp - xpForLevel(level)) / (xpForLevel(level + 1) - xpForLevel(level));
    return Scaffold(
      appBar: AppBar(title: Text(p.displayName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: AnimatedRing(
              value: progress,
              color: xpColor,
              size: 112,
              stroke: 7,
              child: Avatar(name: p.displayName, color: p.avatarColor, size: 82),
            ),
          ),
          const SizedBox(height: 8),
          Text('@${p.username}', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          Text('Level $level ${levelTitle(level)}  |  ${fmtInt(p.totalXp)} XP',
              textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.copyWith(color: xpColor)),
          if (p.streak > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.local_fire_department, color: fireColor, size: 18),
                const SizedBox(width: 4),
                Text('${p.streak}-day streak', style: const TextStyle(color: fireColor)),
              ]),
            ),
          const SizedBox(height: 16),
          if (_error != null) EmptyNote(_error!),
          if (d == null && _error == null) const Center(child: CircularProgressIndicator()),
          if (d != null && _mine != null) ...[
            _headToHead(d, _mine!),
            const SizedBox(height: 8),
            _weeksChart(d),
            SectionHeader(title: 'Badges', trailing: Text('${d.badges.length} / ${badgeDefs.length}')),
            Wrap(spacing: 14, runSpacing: 14, children: [
              for (final b in badgeDefs)
                Tooltip(
                  message: '${b.name}: ${b.description}',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Opacity(
                    opacity: d.badges.contains(b.id) ? 1 : 0.25,
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: d.badges.contains(b.id) ? xpColor : theme.colorScheme.surfaceContainerHighest,
                      child: Icon(b.icon, color: Sumi.porcelain),
                    ),
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _headToHead(FriendDetail d, GameState mine) {
    final theme = Theme.of(context);
    final theirs = d.weeklyXp[weekStartKey()] ?? 0;
    final mineXp = mine.weekXp;
    final top = [theirs, mineXp, 1].reduce((a, b) => a > b ? a : b);
    final diff = mineXp - theirs;
    final name = firstName(d.profile.displayName);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This week, head to head', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _bar('You', mineXp, top, theme.colorScheme.primary),
          const SizedBox(height: 10),
          _bar(name, theirs, top, xpColor),
          const SizedBox(height: 12),
          Text(
            diff > 0
                ? 'You are ahead of $name by $diff XP.'
                : diff < 0
                    ? '$name is ahead by ${-diff} XP. Time to train!'
                    : 'Dead even. Next quest wins.',
            style: theme.textTheme.bodyMedium,
          ),
        ]),
      ),
    );
  }

  Widget _bar(String label, int xp, int top, Color color) {
    final theme = Theme.of(context);
    return Row(children: [
      SizedBox(width: 72, child: Text(label, overflow: TextOverflow.ellipsis)),
      Expanded(child: AnimatedBar(value: xp / top, color: color, height: 14)),
      SizedBox(
        width: 70,
        child: Text('${fmtInt(xp)} XP', textAlign: TextAlign.right, style: theme.textTheme.labelLarge),
      ),
    ]);
  }

  Widget _weeksChart(FriendDetail d) {
    final theme = Theme.of(context);
    final now = weekStart(DateTime.now());
    final weeks = [for (var i = 4; i >= 0; i--) DateTime(now.year, now.month, now.day - 7 * i)];
    final values = [for (final w in weeks) (d.weeklyXp[dayKey(w)] ?? 0).toDouble()];
    final top = values.fold<double>(10, (a, b) => b > a ? b : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text('Weekly XP', style: theme.textTheme.titleMedium),
          ),
          SizedBox(
            height: 140,
            child: BarChart(BarChartData(
              maxY: top * 1.15,
              minY: 0,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    '${rod.toY.round()} XP',
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
                      if (i < 0 || i >= weeks.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(i == weeks.length - 1 ? 'Now' : shortDate(dayKey(weeks[i])),
                            style: theme.textTheme.labelSmall),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < weeks.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: values[i],
                      width: 22,
                      color: i == weeks.length - 1 ? xpColor : xpColor.withAlpha(140),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
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
