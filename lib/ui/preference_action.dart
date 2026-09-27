import 'package:flutter/material.dart';

// Weakly owned by the originating element; no retained route after disposal.
final _pendingPreferences = Expando<Set<String>>();

/// Explicit preference changes are current user actions, not learning sessions.
/// Ignore duplicate pending taps; show failure rather than detach its Future.
Future<void> persistPreference(BuildContext context, String key,
    Future<void> Function() action) async {
  final pending = _pendingPreferences[context] ??= <String>{};
  if (!pending.add(key)) return;
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sonuç kaydedilemedi. Tekrar deneyin.'),
      ));
    }
  } finally {
    pending.remove(key);
  }
}
