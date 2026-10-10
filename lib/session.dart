import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'db.dart';
import 'social.dart';

enum AuthMode { loading, signedOut, guest, account }

/// Who is using the app right now, and which data file is open.
class AppSession extends ChangeNotifier {
  AppSession._();
  static final AppSession instance = AppSession._();

  AuthMode mode = AuthMode.loading;
  String? userId;
  PublicProfile? me;
  bool needsUsername = false;
  bool hasBodyProfile = false;
  bool _switching = false;
  StreamSubscription<AuthState>? _sub;

  bool get backend => Social.instance.ready;
  bool get isAccount => mode == AuthMode.account;

  Future<void> start() async {
    if (Config.hasBackend) {
      try {
        await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseKey);
        Social.instance.ready = true;
        _sub = Supabase.instance.client.auth.onAuthStateChange.listen(_onAuth, onError: (Object _) {});
      } catch (e) {
        debugPrint('Supabase init failed: $e');
      }
    }
    final user = backend ? Supabase.instance.client.auth.currentUser : null;
    if (user != null) {
      await _enterAccount(user.id);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('guest') ?? false) {
      await continueAsGuest();
      return;
    }
    _set(AuthMode.signedOut);
  }

  void _onAuth(AuthState state) {
    final user = state.session?.user;
    if (state.event == AuthChangeEvent.signedIn && user != null && userId != user.id) {
      _enterAccount(user.id);
    } else if (state.event == AuthChangeEvent.signedOut && mode == AuthMode.account) {
      _toSignedOut();
    }
  }

  void _set(AuthMode m) {
    mode = m;
    notifyListeners();
  }

  Future<void> _enterAccount(String uid) async {
    if (_switching) return;
    _switching = true;
    _set(AuthMode.loading);
    try {
      await AppDb.instance.openFor('fitlog_$uid.db', claimGuest: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('guest', false);
      userId = uid;
      try {
        me = await Social.instance.fetchMyProfile();
        needsUsername = me == null;
      } catch (e) {
        // Offline: let them use the app; we'll ask for a username next time.
        me = null;
        needsUsername = false;
      }
      hasBodyProfile = await AppDb.instance.getProfile() != null;
      mode = AuthMode.account;
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  Future<void> continueAsGuest() async {
    await AppDb.instance.openFor(guestDbFile);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('guest', true);
    userId = null;
    me = null;
    needsUsername = false;
    hasBodyProfile = await AppDb.instance.getProfile() != null;
    _set(AuthMode.guest);
  }

  Future<void> _toSignedOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('guest', false);
    await AppDb.instance.close();
    userId = null;
    me = null;
    needsUsername = false;
    _set(AuthMode.signedOut);
  }

  Future<void> signOut() async {
    if (mode == AuthMode.account && backend) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    }
    await _toSignedOut();
  }

  void profileSaved(PublicProfile p) {
    me = p;
    needsUsername = false;
    notifyListeners();
  }

  void bodyProfileSaved() {
    hasBodyProfile = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
