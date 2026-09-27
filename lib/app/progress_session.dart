import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'app_state.dart';

/// Capture once, not on rebuild. A delayed callback from a pre-restore route
/// must not become a new action on the imported progress.
mixin ProgressSession<T extends StatefulWidget> on State<T> {
  AppState? _progressApp;
  int? _progressToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _progressApp ??= AppScope.of(context);
    _progressToken ??= _progressApp!.progressGeneration;
  }

  bool get progressReady => mounted &&
      allowProgress(context, _progressApp!, _progressToken!);
}

bool allowProgress(BuildContext context, AppState app, int generation) {
  if (!context.mounted) return false;
  if (app.progress.isCurrent(generation)) return true;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
    content: Text('İlerleme değişiyor veya bu oturum eskidi. Ekranı yeniden açın.'),
  ));
  return false;
}
