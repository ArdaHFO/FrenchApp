import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// [AppState]'i widget ağacına dağıtır.
///
/// Paket kullanmıyoruz. Riverpod, durum gerçekten karmaşıklaştığında
/// (Faz 5 quiz motoru civarı) eklenecek. Şimdilik tek bir InheritedNotifier
/// yeterli ve bağımlılık getirmiyor.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final AppScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope ağaçta bulunamadı');
    return scope!.notifier!;
  }
}
