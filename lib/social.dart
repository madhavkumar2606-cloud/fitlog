import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'game.dart';
import 'util.dart';

class PublicProfile {
  final String id, username, displayName;
  final int avatarColor, totalXp, level, streak;

  const PublicProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarColor,
    required this.totalXp,
    required this.level,
    required this.streak,
  });

  factory PublicProfile.fromMap(Map<String, dynamic> m) => PublicProfile(
        id: m['id'] as String,
        username: m['username'] as String,
        displayName: m['display_name'] as String,
        avatarColor: (m['avatar_color'] as num?)?.toInt() ?? 0,
        totalXp: (m['total_xp'] as num?)?.toInt() ?? 0,
        level: (m['level'] as num?)?.toInt() ?? 1,
        streak: (m['streak'] as num?)?.toInt() ?? 0,
      );
}

class FriendLink {
  final int id;
  final PublicProfile other;
  final bool incoming; // they sent it to me
  final bool accepted;
  const FriendLink(this.id, this.other, this.incoming, this.accepted);
}

class LeaderRow {
  final PublicProfile profile;
  final int xp;
  final int workouts;
  final bool isMe;
  const LeaderRow(this.profile, this.xp, this.workouts, this.isMe);
}

class FriendDetail {
  final PublicProfile profile;
  final Set<String> badges;
  final Map<String, int> weeklyXp; // week start -> xp
  const FriendDetail(this.profile, this.badges, this.weeklyXp);
}

String friendlyError(Object e) {
  if (e is AuthException) {
    if (e.message.toLowerCase().contains('provider is not enabled')) {
      return 'Google sign-in is not set up yet. Use email and password for now.';
    }
    if (e.message.toLowerCase().contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    return e.message;
  }
  if (e is PostgrestException) {
    if (e.code == '23505') return 'That already exists. Try a different one.';
    return e.message;
  }
  final text = e.toString();
  if (e is SocketException || text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'No internet connection. Check your connection and try again.';
  }
  return 'Something went wrong: $text';
}

/// Everything that talks to Supabase: profiles, friends, leaderboard and XP sync.
class Social {
  Social._();
  static final Social instance = Social._();

  bool ready = false; // set once Supabase.initialize succeeds

  SupabaseClient get _c => Supabase.instance.client;

  String? get myId => ready ? _c.auth.currentUser?.id : null;
  bool get available => myId != null;

  // ---------- My profile ----------

  Future<PublicProfile?> fetchMyProfile() async {
    final row = await _c.from('profiles').select().eq('id', myId!).maybeSingle();
    return row == null ? null : PublicProfile.fromMap(row);
  }

  Future<bool> usernameTaken(String username) async {
    final row = await _c.from('profiles').select('id').eq('username', username).maybeSingle();
    return row != null && row['id'] != myId;
  }

  Future<PublicProfile?> saveMyProfile({
    required String username,
    required String displayName,
    required int avatarColor,
  }) async {
    await _c.from('profiles').upsert({
      'id': myId!,
      'username': username,
      'display_name': displayName,
      'avatar_color': avatarColor,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return fetchMyProfile();
  }

  // ---------- Friends ----------

  Future<List<PublicProfile>> searchUsers(String query) async {
    final q = query.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (q.isEmpty) return [];
    final rows = await _c.from('profiles').select().ilike('username', '%$q%').neq('id', myId!).limit(10);
    return rows.map(PublicProfile.fromMap).toList();
  }

  Future<List<PublicProfile>> profilesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _c.from('profiles').select().inFilter('id', ids);
    return rows.map(PublicProfile.fromMap).toList();
  }

  Future<List<FriendLink>> friendLinks() async {
    final me = myId!;
    final rows = await _c.from('friendships').select().or('requester.eq.$me,addressee.eq.$me');
    final otherIds = <String>[
      for (final r in rows) (r['requester'] == me ? r['addressee'] : r['requester']) as String,
    ];
    final byId = {for (final p in await profilesByIds(otherIds)) p.id: p};
    final out = <FriendLink>[];
    for (final r in rows) {
      final incoming = r['addressee'] == me;
      final otherId = (incoming ? r['requester'] : r['addressee']) as String;
      final other = byId[otherId];
      if (other == null) continue;
      out.add(FriendLink((r['id'] as num).toInt(), other, incoming, r['status'] == 'accepted'));
    }
    out.sort((a, b) => a.other.displayName.toLowerCase().compareTo(b.other.displayName.toLowerCase()));
    return out;
  }

  Future<void> sendRequest(String toId) async {
    await _c.from('friendships').insert({'requester': myId!, 'addressee': toId});
  }

  Future<void> accept(int linkId) async {
    await _c.from('friendships').update({'status': 'accepted'}).eq('id', linkId);
  }

  Future<void> removeLink(int linkId) async {
    await _c.from('friendships').delete().eq('id', linkId);
  }

  // ---------- XP sync & leaderboard ----------

  /// Pushes this week's XP, level, streak and badges so friends can see them.
  Future<void> sync(GameState g) async {
    final me = myId;
    if (me == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _c.from('weekly_xp').upsert({
      'user_id': me,
      'week_start': weekStartKey(),
      'xp': g.weekXp,
      'workouts': g.workoutsThisWeek,
      'updated_at': now,
    });
    await _c.from('profiles').update({
      'total_xp': g.totalXp,
      'level': g.level,
      'streak': g.streak,
      'updated_at': now,
    }).eq('id', me);
    if (g.earned.isNotEmpty) {
      await _c.from('user_badges').upsert(
        [for (final id in g.earned.keys) {'user_id': me, 'badge': id}],
        onConflict: 'user_id,badge',
        ignoreDuplicates: true,
      );
    }
  }

  /// Fire-and-forget version of [sync] for use after logging something.
  void syncQuietly(GameState g) {
    if (!available) return;
    sync(g).catchError((Object e) => debugPrint('FitLog sync failed: $e'));
  }

  Future<List<LeaderRow>> leaderboard() async {
    final me = myId!;
    final links = await friendLinks();
    final ids = [me, for (final l in links) if (l.accepted) l.other.id];
    final profiles = await profilesByIds(ids);
    final rows = await _c.from('weekly_xp').select().eq('week_start', weekStartKey()).inFilter('user_id', ids);
    final xp = {for (final r in rows) r['user_id'] as String: (r['xp'] as num).toInt()};
    final workouts = {for (final r in rows) r['user_id'] as String: (r['workouts'] as num).toInt()};
    final out = [
      for (final p in profiles) LeaderRow(p, xp[p.id] ?? 0, workouts[p.id] ?? 0, p.id == me),
    ];
    out.sort((a, b) {
      final c = b.xp.compareTo(a.xp);
      return c != 0 ? c : a.profile.displayName.compareTo(b.profile.displayName);
    });
    return out;
  }

  Future<FriendDetail?> friendDetail(String id) async {
    final row = await _c.from('profiles').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    final badges = await _c.from('user_badges').select('badge').eq('user_id', id);
    final from = dayKey(DateTime.now().subtract(const Duration(days: 35)));
    final weeks = await _c.from('weekly_xp').select().eq('user_id', id).gte('week_start', from).order('week_start');
    return FriendDetail(
      PublicProfile.fromMap(row),
      {for (final b in badges) b['badge'] as String},
      {for (final w in weeks) w['week_start'] as String: (w['xp'] as num).toInt()},
    );
  }
}
