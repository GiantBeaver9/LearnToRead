/// The app widget: a routed, token-themed [MaterialApp] plus the two
/// app-level jobs nothing below it can do (PRD §8 Unit 1 shell half, §8
/// Unit 11's launch catalog check, §8 Unit 12's session lifecycle; ticket
/// `app-shell`).
///
/// [LearnToReadApp] performs no feature logic. It:
///
///  1. builds `MaterialApp.router` over `appRouterProvider` (A-2: go_router,
///     never a Navigator 1.0 `home`),
///  2. applies the design-system theme so no stock component styling shows
///     through on a child-facing screen,
///  3. kicks off the launch catalog check, fire-and-forget — its failure is
///     silent and nothing the child can see depends on it (§6 Offline), and
///  4. reports app lifecycle to `SessionTracker`, which is what turns "the
///     app was put down for more than 120 s" into a session end and, if a
///     story was open, a `story_abandoned`.
///
/// ## Unpinned decision, documented in docs/app-shell.md
///
/// A session ending on a background timeout does **not** send the child back
/// to the profile picker. §8 Unit 12 pins session *analytics* boundaries
/// ("a session starts at profile selection"), not a navigation consequence,
/// so the child stays exactly where they were and the next session opens at
/// the next profile selection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:learn_to_read/app/providers.dart';
import 'package:learn_to_read/app/router.dart';
import 'package:learn_to_read/design/tokens.dart';

/// The design-system theme.
///
/// Deliberately thin: every child-facing screen paints from [DesignTokens]
/// directly, so this exists to stop the framework's own defaults (surfaces,
/// text colour, the default type face) from showing through anywhere the
/// screens do not paint themselves.
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: DesignTokens.displayFontFamily,
    scaffoldBackgroundColor: DesignTokens.screenBackground,
    canvasColor: DesignTokens.screenBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: DesignTokens.wordVocabBlue,
      surface: DesignTokens.surfaceBackground,
      primary: DesignTokens.wordVocabBlue,
      onSurface: DesignTokens.wordUnreadInk,
    ),
  );
}

/// The whole app.
class LearnToReadApp extends ConsumerStatefulWidget {
  const LearnToReadApp({super.key});

  @override
  ConsumerState<LearnToReadApp> createState() => _LearnToReadAppState();
}

class _LearnToReadAppState extends ConsumerState<LearnToReadApp>
    with WidgetsBindingObserver {
  /// Whether the app is currently in the background.
  ///
  /// Tracked here rather than inferred per callback because a real device
  /// walks `inactive -> hidden -> paused` on the way down and back up again
  /// on the way in; `SessionTracker.onBackground` must be told once, at the
  /// moment the child actually put the app down, since that timestamp is what
  /// the abandonment is dated at.
  bool _backgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sessions = ref.read(sessionTrackerProvider);
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_backgrounded) return;
        _backgrounded = true;
        sessions.onBackground();
      case AppLifecycleState.resumed:
        if (!_backgrounded) return;
        _backgrounded = false;
        sessions.onForeground();
      case AppLifecycleState.detached:
        sessions.onClose();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fire-and-forget (PRD §8 Unit 11 "online: catalog checked in the
    // background"). Watched rather than read so the check is kicked off
    // exactly once, at boot, and its result is never awaited by anything the
    // child can see.
    ref.watch(launchCatalogCheckProvider);

    return MaterialApp.router(
      title: 'LearnToRead',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
