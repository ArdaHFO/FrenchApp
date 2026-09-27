import 'dart:async';

class ProgressUnavailable implements Exception {
  const ProgressUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Admission is synchronous; execution is FIFO. Only store helpers may join
/// an already accepted operation. Its lease expires when the body completes.
class ProgressCoordinator {
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool restoring = false;
  bool recoveryRequired = false;
  int generation = 0;
  final Object _zoneKey = Object();

  bool get accepting => _closing == null && !restoring && !recoveryRequired;
  bool isCurrent(int token) => accepting && token == generation;

  Future<T> run<T>(Future<T> Function() body, {int? token}) {
    if (!accepting || (token != null && token != generation)) {
      return Future<T>.error(const ProgressUnavailable(
          'İlerleme değişiyor veya oturum eskidi. Ekranı yeniden açın.'));
    }
    return _append(body);
  }

  Future<T> store<T>(int token, Future<T> Function() body) {
    final lease = Zone.current[_zoneKey];
    if (lease is _ProgressLease && lease.active && token == generation) {
      return Future<T>.sync(body);
    }
    return run(body, token: token);
  }

  Future<T> _append<T>(Future<T> Function() body) {
    final next = _tail.then((_) async {
      final lease = _ProgressLease();
      try {
        return await runZoned(body, zoneValues: {_zoneKey: lease});
      } finally {
        lease.active = false;
      }
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<T> restore<T>(Future<T> Function() body) {
    if (!accepting) return run(body);
    restoring = true;
    return _append(() async {
      try {
        return await body();
      } finally {
        restoring = false; // closing/recovery still keep admission closed.
      }
    });
  }

  Future<void> recover(Future<void> Function() body) {
    if (_closing != null || restoring || !recoveryRequired) {
      return Future.error(const ProgressUnavailable('Yeniden yükleme uygun değil.'));
    }
    restoring = true;
    return _append(() async {
      try {
        await body();
        recoveryRequired = false;
      } finally {
        restoring = false;
      }
    });
  }

  Future<void> close(Future<void> Function() closeDatabase) {
    return _closing ??= _tail.then((_) => closeDatabase());
  }
}

class _ProgressLease {
  bool active = true;
}

/// Standalone stores used by tests remain usable without an AppState. Every
/// store owned by AppState is bound once to its coordinator and generation.
mixin CoordinatedProgressStore {
  ProgressCoordinator? _coordinator;
  int? _generation;
  void bindProgress(ProgressCoordinator coordinator) {
    if (_coordinator != null) throw StateError('Store already bound');
    _coordinator = coordinator;
    _generation = coordinator.generation;
  }

  Future<T> coordinate<T>(Future<T> Function() body) => _coordinator == null
      ? Future<T>.sync(body)
      : _coordinator!.store(_generation!, body);
}
