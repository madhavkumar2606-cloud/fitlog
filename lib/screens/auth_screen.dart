import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../session.dart';
import '../social.dart';
import '../widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < 6) {
      setState(() => _error = 'Enter a valid email and a password of at least 6 characters.');
      return;
    }
    await _run(() async {
      if (_creating) {
        final res = await _client.auth.signUp(email: email, password: password, emailRedirectTo: Config.authRedirect);
        if (res.session == null && mounted) {
          setState(() => _notice = 'Check your inbox for a confirmation link from Supabase. '
              'Tap it on this phone, then come back and sign in.');
        }
      } else {
        await _client.auth.signInWithPassword(email: email, password: password);
      }
    });
  }

  Future<void> _google() async {
    await _run(() async {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Config.authRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = AppSession.instance.backend;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Icon(Icons.fitness_center, size: 52, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('FitLog', textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Train. Eat. Level up with your friends.', textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 36),
            if (!online) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Accounts and friends are not set up in this version of the app, '
                    'so everything is saved on this phone only.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: AppSession.instance.continueAsGuest,
                child: const Text('Start using FitLog'),
              ),
            ] else ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Sign in')),
                  ButtonSegment(value: true, label: Text('Create account')),
                ],
                selected: {_creating},
                onSelectionChanged: (s) => setState(() {
                  _creating = s.first;
                  _error = null;
                  _notice = null;
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _hidePassword,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    tooltip: _hidePassword ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hidePassword = !_hidePassword),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 12),
                Text(_notice!, style: const TextStyle(color: goodColor)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_creating ? 'Create account' : 'Sign in'),
              ),
              if (Config.googleSignIn) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: theme.textTheme.bodySmall),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _google,
                icon: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Text('G',
                      style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 14)),
                ),
                label: const Text('Continue with Google'),
              ),
              ],
              const SizedBox(height: 20),
              Text(
                _creating
                    ? 'After creating your account you can request access. Your data stays private on your phone.'
                    : 'New here? Tap Create account, then request access.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// First step after creating an account: pick a public name, username and colour.
class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key, this.editing = false});
  final bool editing;

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  static final _valid = RegExp(r'^[a-z0-9_]{3,20}$');
  final _name = TextEditingController();
  final _username = TextEditingController();
  int _color = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final me = AppSession.instance.me;
    if (me != null) {
      _name.text = me.displayName;
      _username.text = me.username;
      _color = me.avatarColor;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final username = _username.text.trim().toLowerCase();
    if (name.isEmpty) {
      setState(() => _error = 'Add your name.');
      return;
    }
    if (!_valid.hasMatch(username)) {
      setState(() => _error = 'Usernames are 3 to 20 characters: lowercase letters, numbers and _.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await Social.instance.usernameTaken(username)) {
        if (!mounted) return;
        setState(() => _error = '@$username is taken. Try another one.');
        return;
      }
      final p = await Social.instance.saveMyProfile(username: username, displayName: name, avatarColor: _color);
      if (p != null) AppSession.instance.profileSaved(p);
      if (widget.editing && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _name.text.trim().isEmpty ? '?' : _name.text.trim();
    return PopScope(
      canPop: widget.editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) AppSession.instance.signOut();
      },
      child: Scaffold(
      appBar: AppBar(
        leading: widget.editing
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to sign in',
                onPressed: AppSession.instance.signOut,
              ),
        title: Text(widget.editing ? 'Edit public profile' : 'Create your profile'),
        actions: [
          if (!widget.editing)
            TextButton(onPressed: AppSession.instance.signOut, child: const Text('Sign out')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Avatar(key: ValueKey('$_color-$preview'), name: preview, color: _color, size: 88),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < avatarColors.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _color = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: avatarColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == i ? theme.colorScheme.onSurface : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Your name', helperText: 'Friends see this name'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixText: '@',
              helperText: 'Friends add you with this. Lowercase letters, numbers and _',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.editing ? 'Save' : 'Continue'),
          ),
        ],
      ),
    ));
  }
}
