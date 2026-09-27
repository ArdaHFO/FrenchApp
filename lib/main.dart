import 'package:flutter/material.dart';

import 'app/app_scope.dart';
import 'app/app_shell.dart';
import 'app/app_state.dart';
import 'app/theme.dart';
import 'features/onboarding/level_select_screen.dart';
import 'features/onboarding/paris_opening_screen.dart';
import 'motion/motion_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FrenchApp());
}

class FrenchApp extends StatefulWidget {
  const FrenchApp({super.key});

  @override
  State<FrenchApp> createState() => _FrenchAppState();
}

class _FrenchAppState extends State<FrenchApp> {
  late final Future<AppState> _boot = _createState();
  AppState? _state;

  Future<AppState> _createState() async {
    final AppState state = await AppState.create();
    if (mounted) {
      _state = state;
    } else {
      state.dispose();
    }
    return state;
  }

  @override
  void dispose() {
    _state?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _boot,
      builder: (BuildContext context, AsyncSnapshot<AppState> snap) {
        final Widget home;
        if (snap.hasError) {
          home = _StartupError(error: snap.error!, stack: snap.stackTrace);
        } else if (!snap.hasData) {
          home = const ParisOpeningScreen();
        } else {
          home = const _Root();
        }

        final Widget app = MaterialApp(
          title: 'FrenchApp',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: home,
        );

        // AppScope, MaterialApp'in ÜSTÜNDE durmak zorunda.
        //
        // İçine (home'a) konursa yalnızca ilk rotanın alt ağacını kapsar.
        // Navigator.push ile açılan sayfalar Navigator'ın çocuğudur, yani
        // home'un kardeşidir; AppScope'u göremezler. O durumda
        // AppScope.of() null döner, release derlemesinde assert elendiği
        // için null check hatası atar ve sayfa gri/beyaz görünür.
        final AppState? state = snap.data;
        if (state == null) return app;
        return AppScope(state: state, child: app);
      },
    );
  }
}

/// İlk açılışta seviye seçimi, sonrasında ana kabuk.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    return AnimatedSwitcher(
      duration: MotionTokens.pageTransition,
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      child: app.onboardingDone
          ? const AppShell(key: ValueKey<String>('shell'))
          : const LevelSelectScreen(key: ValueKey<String>('onboarding')),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, this.stack});

  final Object error;
  final StackTrace? stack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.error_outline_rounded, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Uygulama açılamadı',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                SelectableText('$error'),
                if (stack != null) ...<Widget>[
                  const SizedBox(height: 16),
                  SelectableText(
                    '$stack',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
