import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/access_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/food_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/today_screen.dart';
import 'screens/train_screen.dart';
import 'session.dart';
import 'update.dart';
import 'visuals.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Sumi.paper,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const FitLogApp());
  AppSession.instance.start();
}

class FitLogApp extends StatelessWidget {
  const FitLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitLog',
      debugShowCheckedModeBanner: false,
      theme: sumiTheme(),
      home: const _Gate(),
    );
  }
}

/// The Sumi theme: washi paper, black ink, serif titles, crisp buttons and black-and-white switches.
ThemeData sumiTheme() {
  const scheme = ColorScheme.light(
    primary: Sumi.ink,
    onPrimary: Sumi.porcelain,
    primaryContainer: Sumi.wash,
    onPrimaryContainer: Sumi.ink,
    secondary: Sumi.ink2,
    onSecondary: Sumi.porcelain,
    secondaryContainer: Sumi.porcelain,
    onSecondaryContainer: Sumi.ink,
    tertiary: Sumi.muted,
    onTertiary: Sumi.porcelain,
    error: Sumi.error,
    onError: Sumi.porcelain,
    errorContainer: Color(0xFFEBD9D4),
    onErrorContainer: Sumi.error,
    surface: Sumi.paper,
    onSurface: Sumi.ink,
    surfaceContainerLowest: Sumi.porcelain,
    surfaceContainerLow: Sumi.porcelain,
    surfaceContainer: Sumi.sheet,
    surfaceContainerHigh: Color(0xFFE9E5DE),
    surfaceContainerHighest: Sumi.wash,
    onSurfaceVariant: Sumi.muted,
    outline: Sumi.edge,
    outlineVariant: Sumi.rule,
    inverseSurface: Sumi.ink,
    onInverseSurface: Sumi.porcelain,
    surfaceTint: Colors.transparent,
  );
  TextStyle s(double size) => serif(size);
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: Sumi.sans,
    scaffoldBackgroundColor: Sumi.paper,
    splashFactory: InkRipple.splashFactory,
    textTheme: TextTheme(
      displayLarge: s(56),
      displayMedium: s(46),
      displaySmall: s(38),
      headlineLarge: s(36),
      headlineMedium: s(32),
      headlineSmall: s(26),
      titleLarge: s(23),
      titleMedium: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: Sumi.ink),
      titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Sumi.ink),
      bodyLarge: const TextStyle(fontSize: 15.5, color: Sumi.ink),
      bodyMedium: const TextStyle(fontSize: 14, color: Sumi.ink),
      bodySmall: const TextStyle(fontSize: 12, color: Sumi.muted),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.2),
      labelMedium: const TextStyle(fontSize: 12, letterSpacing: 0.4, color: Sumi.ink2),
      labelSmall: const TextStyle(fontSize: 10.5, letterSpacing: 1.2, color: Sumi.muted),
    ),
    iconTheme: const IconThemeData(color: Sumi.ink),
    appBarTheme: AppBarThemeData(
      backgroundColor: Sumi.paper,
      foregroundColor: Sumi.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: serif(26),
      iconTheme: const IconThemeData(color: Sumi.ink),
    ),
    cardTheme: CardThemeData(
      color: Sumi.porcelain.withAlpha(215),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Sumi.rule),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Sumi.ink,
        foregroundColor: Sumi.porcelain,
        disabledBackgroundColor: Sumi.wash,
        disabledForegroundColor: Sumi.faint,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: buttonShape,
        textStyle: const TextStyle(fontFamily: Sumi.sans, fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Sumi.ink,
        backgroundColor: Sumi.porcelain,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Color(0xFFD6D0C4)),
        shape: buttonShape,
        textStyle: const TextStyle(fontFamily: Sumi.sans, fontSize: 14.5, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Sumi.ink,
        textStyle: const TextStyle(fontFamily: Sumi.sans, fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: Sumi.ink)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Sumi.ink,
      foregroundColor: Sumi.porcelain,
      elevation: 1,
      shape: buttonShape,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => Sumi.porcelain),
      trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? Sumi.ink : const Color(0xFFE3DED5)),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? Sumi.ink : Sumi.edge),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Sumi.ink : null),
      checkColor: WidgetStateProperty.all(Sumi.porcelain),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.all(Sumi.ink)),
    chipTheme: ChipThemeData(
      backgroundColor: Sumi.porcelain,
      selectedColor: Sumi.ink,
      checkmarkColor: Sumi.porcelain,
      side: const BorderSide(color: Color(0xFFD6D0C4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(fontFamily: Sumi.sans, fontSize: 13, color: Sumi.ink),
      secondaryLabelStyle: const TextStyle(fontFamily: Sumi.sans, fontSize: 13, color: Sumi.porcelain),
    ),
    inputDecorationTheme: const InputDecorationThemeData(
      isDense: true,
      border: UnderlineInputBorder(borderSide: BorderSide(color: Sumi.edge, width: 1.5)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Sumi.edge, width: 1.5)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Sumi.ink, width: 1.8)),
      labelStyle: TextStyle(color: Sumi.muted),
      floatingLabelStyle: TextStyle(color: Sumi.ink),
      hintStyle: TextStyle(color: Sumi.faint),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Sumi.ink,
      selectionColor: Color(0x33151413),
      selectionHandleColor: Sumi.ink,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Sumi.sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: serif(26),
      contentTextStyle: const TextStyle(fontFamily: Sumi.sans, fontSize: 14, color: Sumi.ink, height: 1.4),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Sumi.sheet,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Sumi.edge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Sumi.ink,
      contentTextStyle: TextStyle(fontFamily: Sumi.sans, fontSize: 14, color: Sumi.porcelain),
      actionTextColor: Sumi.porcelain,
      behavior: SnackBarBehavior.floating,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Sumi.ink,
      unselectedLabelColor: Sumi.faint,
      indicatorColor: Sumi.ink,
      dividerColor: Sumi.rule,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Sumi.ink,
      linearTrackColor: Sumi.rule,
      circularTrackColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(color: Sumi.rule, thickness: 1),
    listTileTheme: const ListTileThemeData(iconColor: Sumi.ink2),
    popupMenuTheme: const PopupMenuThemeData(color: Sumi.sheet, surfaceTintColor: Colors.transparent),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: Sumi.ink, borderRadius: BorderRadius.all(Radius.circular(6))),
      textStyle: TextStyle(color: Sumi.porcelain, fontSize: 12),
    ),
  );
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
        if (session.isAccount && session.backend && !session.hasAccess) return const AccessScreen();
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
    return Scaffold(
      body: Center(
        child: Enso(value: 0.92, size: 180, stroke: 13, child: Text('FitLog', style: serif(36))),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Updater.promptIfNeeded(context);
    });
  }

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
      backgroundColor: Sumi.paper,
      body: Stack(children: [
        const Positioned.fill(child: AppBackground()),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
        ),
      ]),
      bottomNavigationBar: SumiTabBar(
        index: _index,
        onTap: _go,
        labels: const ['Today', 'Train', 'Food', 'Progress', 'Friends'],
      ),
    );
  }
}
