import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../access.dart';
import '../session.dart';
import '../social.dart';
import '../update.dart';
import '../util.dart';
import '../widgets.dart';

String _date(DateTime d) => shortDate(dayKey(d)) + (d.year != DateTime.now().year ? ' ${d.year}' : '');

/// Shown to signed-in people who are not approved yet. Paid and free users use the same button.
class AccessScreen extends StatefulWidget {
  const AccessScreen({super.key});

  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen> {
  final _utr = TextEditingController();
  final _note = TextEditingController();
  PaymentConfig _config = PaymentConfig.empty;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Updater.promptIfNeeded(context);
    });
  }

  @override
  void dispose() {
    _utr.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await AccessService.instance.config();
      if (mounted) setState(() => _config = c);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _check() async {
    await AppSession.instance.refreshAccess();
    if (!mounted) return;
    final a = AppSession.instance.access;
    if (a != null && a.pending) showSnack(context, 'Still waiting for approval.');
  }

  Future<void> _submit() async {
    final utr = _utr.text.trim();
    if (utr.isNotEmpty && !RegExp(r'^[A-Za-z0-9]{8,30}$').hasMatch(utr)) {
      setState(() => _error = 'That transaction ID looks wrong. It is usually a 12-digit number (UTR) in your UPI app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AccessService.instance.submit(utr: utr, note: _note.text);
      await AppSession.instance.refreshAccess();
      if (mounted) showSnack(context, 'Request sent. You will get in as soon as it is approved.');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUpi() async {
    final me = AppSession.instance.me;
    final link = _config.upiLink('FitLog ${me == null ? '' : '@${me.username}'}'.trim());
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      showSnack(context, 'Could not open a UPI app. Copy the UPI ID and pay from GPay, PhonePe or Paytm.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = AppSession.instance;
    final a = session.access;
    final hasUpi = _config.upiId.isNotEmpty;
    final me = session.me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Get access'),
        actions: [TextButton(onPressed: session.signOut, child: const Text('Sign out'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _check,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  if (a != null && a.pending) _statusCard(
                    icon: Icons.hourglass_top,
                    color: warnColor,
                    title: 'Request sent',
                    body: 'Sent ${a.requestedAt == null ? '' : prettyDay(dayKey(a.requestedAt!)).toLowerCase()}. '
                        'You will get in as soon as it is approved. Pull down or tap below to check.',
                    action: FilledButton.tonal(onPressed: _check, child: const Text('Check again')),
                  ),
                  if (a != null && a.rejected) _statusCard(
                    icon: Icons.block,
                    color: theme.colorScheme.error,
                    title: 'Not approved',
                    body: a.adminNote ?? 'Your request was not approved. You can send a new one below.',
                  ),
                  if (a != null && a.expired) _statusCard(
                    icon: Icons.event_busy,
                    color: fireColor,
                    title: 'Your access has ended',
                    body: 'It ended on ${_date(a.accessUntil!)}. Renew below to keep training with FitLog.',
                  ),
                  const SizedBox(height: 4),
                  Text('Welcome${me == null ? '' : ', ${firstName(me.displayName)}'}!',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    _config.message.isNotEmpty
                        ? _config.message
                        : 'Pay using the QR or UPI ID, then send your request. Got a free invite? Just tap Request access.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (hasUpi)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          if (_config.priceText.isNotEmpty)
                            Text(_config.priceText,
                                style: theme.textTheme.headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.primary)),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                            child: QrImageView(
                              data: _config.upiLink('FitLog ${me == null ? '' : '@${me.username}'}'.trim()),
                              size: 200,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Scan from another phone, or use the button below',
                              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_config.upiId),
                            subtitle: Text('Pay to ${_config.payeeName}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copy UPI ID',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _config.upiId));
                                if (context.mounted) showSnack(context, 'UPI ID copied');
                              },
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _openUpi,
                              icon: const Icon(Icons.account_balance_wallet_outlined),
                              label: const Text('Pay with UPI app'),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _utr,
                    keyboardType: TextInputType.visiblePassword,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'UPI transaction ID (UTR)',
                      helperText: 'The 12-digit number in your payment app. Leave empty for a free invite.',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _note,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Message (optional)',
                      hintText: 'e.g. Free invite from Tania',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(a == null ? 'Request access' : 'Send request again'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Card(
      color: color.withAlpha(35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(body),
              if (action != null) ...[const SizedBox(height: 10), action],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Admin: approve requests ----------------

class AdminAccessScreen extends StatefulWidget {
  const AdminAccessScreen({super.key});

  @override
  State<AdminAccessScreen> createState() => _AdminAccessScreenState();
}

class _AdminAccessScreenState extends State<AdminAccessScreen> {
  List<AccessRequest>? _all;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AccessService.instance.allRequests();
      if (!mounted) return;
      setState(() {
        _all = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
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

  Future<void> _approve(AccessRequest r) async {
    final now = DateTime.now();
    final options = <(String, DateTime?)>[
      ('1 month', DateTime(now.year, now.month + 1, now.day, 23, 59)),
      ('3 months', DateTime(now.year, now.month + 3, now.day, 23, 59)),
      ('6 months', DateTime(now.year, now.month + 6, now.day, 23, 59)),
      ('1 year', DateTime(now.year + 1, now.month, now.day, 23, 59)),
      ('Forever (free access)', null),
    ];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Give ${r.profile?.displayName ?? 'this person'} access for',
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (var i = 0; i < options.length; i++)
            ListTile(
              leading: Icon(options[i].$2 == null ? Icons.all_inclusive : Icons.event_available),
              title: Text(options[i].$1),
              subtitle: options[i].$2 == null ? null : Text('Until ${_date(options[i].$2!)}'),
              onTap: () => Navigator.pop(ctx, i),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    final until = options[picked].$2;
    await _act(() => AccessService.instance.approve(r.userId, until),
        'Approved ${r.profile?.displayName ?? ''} ${until == null ? 'forever' : 'until ${_date(until)}'}');
  }

  Future<void> _reject(AccessRequest r, {bool revoke = false}) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(revoke ? 'Remove access?' : 'Reject request?'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Reason (they will see this)', hintText: 'e.g. Payment not received'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(revoke ? 'Remove' : 'Reject')),
        ],
      ),
    );
    final reason = ctrl.text;
    ctrl.dispose();
    if (ok != true) return;
    await _act(() => AccessService.instance.reject(r.userId, reason), revoke ? 'Access removed' : 'Request rejected');
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final pending = all?.where((r) => r.pending).toList() ?? [];
    final approved = all?.where((r) => r.approved).toList() ?? [];
    final rejected = all?.where((r) => r.rejected).toList() ?? [];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Access requests'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Payment settings',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentSettingsScreen())),
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: 'Pending (${pending.length})'),
            Tab(text: 'Approved (${approved.length})'),
            Tab(text: 'Rejected (${rejected.length})'),
          ]),
        ),
        body: _error != null
            ? ListView(children: [
                EmptyNote(_error!),
                Center(child: FilledButton(onPressed: _load, child: const Text('Try again'))),
              ])
            : all == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _list(pending, 'No pending requests. New ones appear here.'),
                    _list(approved, 'Nobody approved yet.'),
                    _list(rejected, 'No rejected requests.'),
                  ]),
      ),
    );
  }

  Widget _list(List<AccessRequest> items, String empty) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          if (items.isEmpty) EmptyNote(empty),
          for (final r in items) _requestCard(r),
        ],
      ),
    );
  }

  Widget _requestCard(AccessRequest r) {
    final theme = Theme.of(context);
    final p = r.profile;
    final paid = r.utr != null && r.utr!.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(name: p?.displayName ?? '?', color: p?.avatarColor ?? 0, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.displayName ?? 'Unknown user', style: theme.textTheme.titleSmall),
                Text(p == null ? '' : '@${p.username}', style: theme.textTheme.bodySmall),
              ]),
            ),
            if (r.requestedAt != null) Text(prettyDay(dayKey(r.requestedAt!)), style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Icon(paid ? Icons.payments_outlined : Icons.card_giftcard, size: 18, color: paid ? goodColor : xpColor),
            const SizedBox(width: 8),
            Expanded(
              child: paid
                  ? SelectableText('UTR ${r.utr}', style: theme.textTheme.bodyMedium)
                  : Text('No payment: free request', style: theme.textTheme.bodyMedium),
            ),
            if (paid)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy UTR',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: r.utr!));
                  if (mounted) showSnack(context, 'UTR copied. Check it in your bank or UPI app.');
                },
              ),
          ]),
          if (r.note != null) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('"${r.note}"', style: theme.textTheme.bodySmall),
          ),
          if (r.approved) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              r.accessUntil == null
                  ? 'Access forever'
                  : r.active
                      ? 'Access until ${_date(r.accessUntil!)}'
                      : 'Expired on ${_date(r.accessUntil!)}',
              style: TextStyle(color: r.active ? goodColor : fireColor),
            ),
          ),
          if (r.rejected && r.adminNote != null) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Reason: ${r.adminNote}', style: theme.textTheme.bodySmall),
          ),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (r.pending) ...[
              TextButton(onPressed: () => _reject(r), child: const Text('Reject')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => _approve(r), child: const Text('Approve')),
            ],
            if (r.approved) ...[
              TextButton(onPressed: () => _reject(r, revoke: true), child: const Text('Remove access')),
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: () => _approve(r), child: const Text('Extend')),
            ],
            if (r.rejected) FilledButton.tonal(onPressed: () => _approve(r), child: const Text('Approve')),
          ]),
        ]),
      ),
    );
  }
}

// ---------------- Admin: payment settings ----------------

class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  final _upi = TextEditingController();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _price = TextEditingController();
  final _message = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AccessService.instance.config().then((c) {
      if (!mounted) return;
      setState(() {
        _upi.text = c.upiId;
        _name.text = c.payeeName;
        _amount.text = c.amount == null ? '' : fmtW(c.amount!);
        _price.text = c.priceText;
        _message.text = c.message;
        _loading = false;
      });
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _loading = false);
        showSnack(context, friendlyError(e));
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_upi, _name, _amount, _price, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final upi = _upi.text.trim();
    if (upi.isNotEmpty && !upi.contains('@')) {
      showSnack(context, 'A UPI ID looks like name@okaxis or 98xxxxxx@ybl.');
      return;
    }
    setState(() => _saving = true);
    try {
      await AccessService.instance.saveConfig(PaymentConfig(
        upiId: upi,
        payeeName: _name.text.trim().isEmpty ? 'FitLog' : _name.text.trim(),
        amount: parseNum(_amount.text),
        priceText: _price.text.trim(),
        message: _message.text.trim(),
      ));
      if (!mounted) return;
      showSnack(context, 'Saved. Everyone sees the new details right away.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment settings'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                controller: _upi,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Your UPI ID',
                  helperText: 'Find it in GPay: tap your photo, it is under your QR code',
                ),
              ),
              const SizedBox(height: 16),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name shown when paying')),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  helperText: 'Filled into the UPI app automatically. Leave empty to let people type it.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Price label', hintText: 'e.g. ₹49 / month'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Message on the request screen'),
              ),
            ]),
    );
  }
}
