// The repo-scaffold smoke test, updated to the REAL shell (ticket app-shell
// accept entry 8: "Existing test/scaffold_test.dart updated to the real shell
// (it currently asserts the placeholder)").
//
// It used to pump a bare `MaterialApp` with the word "LearnToRead" in the
// middle of it. What it asserts now is the one thing every other suite in the
// repo takes for granted: `lib/main.dart` has a real entrypoint, and
// `LearnToReadApp` boots -- inside a plain `ProviderScope`, through
// `MaterialApp.router` and go_router -- to the profile picker (PRD §9 A-2,
// §8 Unit 1).
//
// Deliberately shallow. Every deeper behavior lives in test/app/: routing in
// router_test.dart, the composed loop in shell_integration_test.dart, the
// offline first run in offline_first_run_test.dart, layout in
// layout_smoke_test.dart.
//
// lib/app/{providers,app}.dart do not exist yet: this file fails to
// compile/analyze until they do -- the expected red state.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_to_read/app/app.dart';
import 'package:learn_to_read/app/providers.dart';
import 'package:learn_to_read/data/content/pack_installer.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/parent/consent_controller.dart';
import 'package:learn_to_read/features/profiles/profile_picker_screen.dart';
import 'package:learn_to_read/main.dart' as entrypoint;

const String _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

final String _phonicsJson = jsonEncode(<String, Object?>{
  'levels': <Object?>[
    <String, Object?>{
      'id': 'level.1',
      'ordinal': 1,
      'format': 'multiSentence',
      'vocabEnabled': false,
      'heartWords': <String>[],
      'skills': <Object?>[],
    },
  ],
  'stories': <Object?>[],
});

StoryPack _emptyStarterPack() => StoryPack(
  id: 'pack.starter',
  version: '1.0.0',
  minAppVersion: '1.0.0',
  stories: const <Story>[],
  twisters: const <TongueTwister>[],
  vocabCards: const <VocabCard>[],
  collectibles: const <Collectible>[],
  graphemeSounds: const <GraphemeSound>[],
  assetRefs: const <String>[],
  checksum: '',
);

class _NoNetworkTransport implements AnalyticsTransport {
  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async =>
      TransportResult.success;
}

void main() {
  late Directory analyticsDir;
  late Directory starterDir;
  late Directory installedDir;

  setUp(() {
    analyticsDir = Directory.systemTemp.createTempSync('scaffold_analytics_');
    starterDir = Directory.systemTemp.createTempSync('scaffold_starter_');
    installedDir = Directory.systemTemp.createTempSync('scaffold_installed_');
  });

  tearDown(() {
    for (final d in <Directory>[analyticsDir, starterDir, installedDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  List<Override> overrides() => <Override>[
    databaseExecutorProvider.overrideWithValue(NativeDatabase.memory()),
    starterPackProvider.overrideWithValue(
      LoadedPack(pack: _emptyStarterPack(), directory: starterDir),
    ),
    packInstallerProvider.overrideWithValue(
      PackInstaller(installedPacksDirectory: installedDir),
    ),
    phonicsContentProvider.overrideWithValue(loadPhonicsContent(_phonicsJson)),
    audioServiceProvider.overrideWithValue(FakeAudioService()),
    asrEngineProvider.overrideWithValue(
      FakeAsrEngine(script: const <Hypothesis>[]),
    ),
    micPermissionServiceProvider.overrideWithValue(
      FakeMicPermissionService(MicPermissionStatus.granted),
    ),
    cloudEngineInUseProvider.overrideWithValue(false),
    phonemeAudioRefsProvider.overrideWithValue(const <String, AudioRef>{}),
    installIdProvider.overrideWithValue(_installId),
    clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
    analyticsTransportProvider.overrideWithValue(_NoNetworkTransport()),
    analyticsStorageDirectoryProvider.overrideWithValue(analyticsDir),
    catalogFetcherProvider.overrideWithValue(null),
    appVersionProvider.overrideWithValue('1.0.0'),
  ];

  Future<void> bootShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: overrides(), child: const LearnToReadApp()),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('scaffold: the real shell boots to the profile picker', (
    tester,
  ) async {
    await bootShell(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ProfilePickerScreen), findsOneWidget);
  });

  testWidgets('scaffold: the shell is a routed MaterialApp (go_router, A-2)', (
    tester,
  ) async {
    await bootShell(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.routerConfig ?? app.routerDelegate,
      isNotNull,
      reason: 'navigation is go_router, not a Navigator 1.0 home widget',
    );
    expect(app.home, isNull);
    expect(
      find.text('LearnToRead'),
      findsNothing,
      reason: 'the placeholder shell is gone',
    );
  });

  test('scaffold: lib/main.dart still exposes a real entrypoint', () {
    expect(entrypoint.main, isA<void Function()>());
  });
}
