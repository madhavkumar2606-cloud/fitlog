import 'package:supabase_flutter/supabase_flutter.dart';

import 'social.dart';

/// Payment details shown on the request-access screen (editable by the admin).
class PaymentConfig {
  final String upiId, payeeName, priceText, message;
  final double? amount;

  const PaymentConfig({
    required this.upiId,
    required this.payeeName,
    required this.priceText,
    required this.message,
    this.amount,
  });

  factory PaymentConfig.fromMap(Map<String, dynamic> m) => PaymentConfig(
        upiId: (m['upi_id'] as String?) ?? '',
        payeeName: (m['payee_name'] as String?) ?? 'FitLog',
        priceText: (m['price_text'] as String?) ?? '',
        message: (m['message'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toDouble(),
      );

  static const empty = PaymentConfig(upiId: '', payeeName: 'FitLog', priceText: '', message: '');

  /// Standard UPI payment link understood by GPay, PhonePe, Paytm and others.
  String upiLink(String note) {
    final e = Uri.encodeComponent;
    final am = amount != null && amount! > 0 ? '&am=${amount!.toStringAsFixed(2)}' : '';
    return 'upi://pay?pa=${e(upiId)}&pn=${e(payeeName)}&cu=INR&tn=${e(note)}$am';
  }
}

class AccessRequest {
  final String userId;
  final String status; // pending | approved | rejected
  final String? utr, note, adminNote;
  final DateTime? accessUntil;
  final DateTime? requestedAt;
  final PublicProfile? profile;

  const AccessRequest({
    required this.userId,
    required this.status,
    this.utr,
    this.note,
    this.adminNote,
    this.accessUntil,
    this.requestedAt,
    this.profile,
  });

  factory AccessRequest.fromMap(Map<String, dynamic> m, {PublicProfile? profile}) => AccessRequest(
        userId: m['user_id'] as String,
        status: m['status'] as String,
        utr: m['utr'] as String?,
        note: m['note'] as String?,
        adminNote: m['admin_note'] as String?,
        accessUntil: m['access_until'] == null ? null : DateTime.parse(m['access_until'] as String).toLocal(),
        requestedAt: m['requested_at'] == null ? null : DateTime.parse(m['requested_at'] as String).toLocal(),
        profile: profile,
      );

  bool get approved => status == 'approved';
  bool get pending => status == 'pending';
  bool get rejected => status == 'rejected';
  bool get active => approved && (accessUntil == null || accessUntil!.isAfter(DateTime.now()));
  bool get expired => approved && !active;
}

/// Access requests, approvals and payment settings (all stored in Supabase).
class AccessService {
  AccessService._();
  static final AccessService instance = AccessService._();

  SupabaseClient get _c => Supabase.instance.client;
  String get _me => _c.auth.currentUser!.id;

  Future<bool> isAdmin() async {
    final row = await _c.from('admins').select('user_id').eq('user_id', _me).maybeSingle();
    return row != null;
  }

  Future<PaymentConfig> config() async {
    final row = await _c.from('app_config').select().eq('id', 1).maybeSingle();
    return row == null ? PaymentConfig.empty : PaymentConfig.fromMap(row);
  }

  Future<void> saveConfig(PaymentConfig c) async {
    await _c.from('app_config').update({
      'upi_id': c.upiId,
      'payee_name': c.payeeName,
      'price_text': c.priceText,
      'message': c.message,
      'amount': c.amount,
    }).eq('id', 1);
  }

  Future<AccessRequest?> myRequest() async {
    final row = await _c.from('access_requests').select().eq('user_id', _me).maybeSingle();
    return row == null ? null : AccessRequest.fromMap(row);
  }

  /// Sends (or re-sends) a request. [utr] is empty for free invites.
  Future<void> submit({String? utr, String? note}) async {
    String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    final data = {
      'utr': clean(utr),
      'note': clean(note),
      'status': 'pending',
      'access_until': null,
      'decided_at': null,
      'admin_note': null,
      'requested_at': DateTime.now().toUtc().toIso8601String(),
    };
    final existing = await myRequest();
    if (existing == null) {
      await _c.from('access_requests').insert({'user_id': _me, ...data});
    } else {
      await _c.from('access_requests').update(data).eq('user_id', _me);
    }
  }

  // ---------- Admin ----------

  Future<List<AccessRequest>> allRequests() async {
    final rows = await _c.from('access_requests').select().order('requested_at', ascending: false);
    final ids = [for (final r in rows) r['user_id'] as String];
    final byId = {for (final p in await Social.instance.profilesByIds(ids)) p.id: p};
    return [for (final r in rows) AccessRequest.fromMap(r, profile: byId[r['user_id']])];
  }

  /// Approves until [until], or forever when [until] is null.
  Future<void> approve(String userId, DateTime? until) async {
    await _c.from('access_requests').update({
      'status': 'approved',
      'access_until': until?.toUtc().toIso8601String(),
      'admin_note': null,
      'decided_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', userId);
  }

  Future<void> reject(String userId, String? reason) async {
    await _c.from('access_requests').update({
      'status': 'rejected',
      'access_until': null,
      'admin_note': (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
      'decided_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', userId);
  }
}
