import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'screens/food_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/today_screen.dart';
import 'screens/workout_screen.dart';
import 'session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FitLogApp());
  AppSession.instance.start();
}

class FitLogApp extends StatelessWidget {
  const FitLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Iron blue with a warm plate-orange accent.
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3D5A80),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFF4A259),
      onPrimary: const Color(0xFF2B1600),
      surface: const Color(0xFF18202B),
    );
    return MaterialApp(
      title: 'FitLog',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF18202B),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const _Gate(),
    );
  }
}

/// Decides what to show: loading, sign-in, username setup, body profile setup, or the app.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.mode == AuthMode.loading) return const _Splash();
        if (session.mode == AuthMode.signedOut) return const AuthScreen();
        if (session.needsUsername) return const UsernameScreen();
        if (!session.hasBodyProfile) {
          return ProfileScreen(
            key: ValueKey('setup-${session.userId}'),
            firstRun: true,
            onSaved: session.bodyProfileSaved,
          );
        }
        return HomeShell(key: ValueKey(session.userId ?? 'guest'));
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.fitness_center, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('FitLog', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
        ]),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      TodayScreen(onNavigate: _go),
      const WorkoutScreen(),
      const FoodScreen(),
      const ProgressScreen(),
      const FriendsScreen(),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.fitness_center), label: 'Train'),
          NavigationDestination(
              icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant), label: 'Food'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
          NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Friends'),
        ],
      ),
    );
  }
}
