import 'package:flutter/material.dart';

import 'db.dart';
import 'screens/food_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/today_screen.dart';
import 'screens/workout_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FitLogApp());
}

class FitLogApp extends StatelessWidget {
  const FitLogApp({super.key});

  @override
  Widget build(BuildContext context) {
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

class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool? _hasProfile;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final p = await AppDb.instance.getProfile();
    if (!mounted) return;
    setState(() => _hasProfile = p != null);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasProfile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_hasProfile == false) {
      return ProfileScreen(firstRun: true, onSaved: _check);
    }
    return const HomeShell();
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
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.fitness_center), label: 'Workouts'),
          NavigationDestination(
              icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant), label: 'Food'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Progress'),
        ],
      ),
    );
  }
}