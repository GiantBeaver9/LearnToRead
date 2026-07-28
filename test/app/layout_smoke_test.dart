// Headless layout coverage + the lib/app/ half of the token-lint gate
// (PRD §8 Unit 1 "Golden tests render library, reading, and collection
// screens in all four layout classes without overflow or clipped Rive
// stages" and "no child-facing widget references a color/font outside the
// design-token file"; ticket app-shell accept entries 6 and 7).
//
// This suite is the headless proxy for the [DEVICE] golden acceptance: it
// drives the REAL shell (router + providers + every merged screen) to each
// child-facing route at all four `LayoutClass` sizes and asserts nothing
// overflows or throws. The pixel goldens themselves are an owner/[DEVICE]
// task and are skip-marked below with a reason, following the convention in
// test/features/map/layout_classes_test.dart.
//
// It also carries the lib/app/ token-lint scan. test/design/token_lint_test.dart
// (design-tokens' frozen suite) scans lib/features/ and lib/design/ only; the
// ticket extends the rule to lib/app/, and this ticket's own suite is where
// that extension lives -- the same three rules, applied to the shell's files.
//
// NOTHING under lib/app/ exists yet: this suite fails to compile/analyze until
// lib/app/{providers,router,app}.dart are written -- the expected red state.
// (The token-lint scan additionally reports zero violations vacuously until
// then, and becomes a real gate the moment the directory appears.)
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:learn_to_read/app/app.dart';
import 'package:learn_to_read/app/providers.dart';
import 'package:learn_to_read/app/router.dart';
import 'package:learn_to_read/data/content/pack_installer.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/parent/consent_controller.dart';

// ---------------------------------------------------------------------------
// The four layout classes (same sizes the merged units' own layout suites use).
// ---------------------------------------------------------------------------

const Map<String, Size> _layoutSizes = <String, Size>{
  'phonePortrait': Size(375, 812),
  'phoneLandscape': Size(812, 375),
  'tabletPortrait': Size(768, 1024),
  'tabletLandscape': Size(1024, 768),
};

// ---------------------------------------------------------------------------
// Token lint (same three rules as test/design/token_lint_test.dart, applied to
// lib/app/ -- deliberately duplicated rather than imported: that file is the
// design-tokens unit's frozen suite and this ticket does not own it).
// ---------------------------------------------------------------------------

final RegExp _colorLiteral = RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}\)');
final RegExp _colorsDot = RegExp(r'\bColors\.[A-Za-z][A-Za-z0-9_]*');
final RegExp _inlineFont = RegExp(r'''TextStyle\([^)]*fontFamily\s*:\s*['"]''');
final RegExp _cupertino = RegExp(r'\bCupertino[A-Za-z]*');

List<String> _scanDirectory(Directory dir, List<RegExp> rules) {
  final violations = <String>[];
  if (!dir.existsSync()) return violations;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsStringSync().split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final rule in rules) {
        if (rule.hasMatch(lines[i])) {
          violations.add('${entity.path}:${i + 1}: ${rule.pattern}');
        }
      }
    }
  }
  return violations;
}

// ---------------------------------------------------------------------------
// Fixtures (file-local, per this codebase's convention).
// ---------------------------------------------------------------------------

const String _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

const Map<String, String> _phonemeForLetter = <String, String>{
  'a': 'AE', 'c': 'K', 'e': 'EH', 'h': 'H', 'i': 'IH', 'n': 'N', 'o': 'AA',
  'r': 'R', 's': 'S', 't': 'T', 'u': 'AH', 'w': 'W', 'l': 'L', 'g': 'G',
  'd': 'D', 'm': 'M', 'b': 'B', 'p': 'P', 'f': 'F', 'y': 'Y',
};

List<({String graphemes, String phonemeId})> _gpm(String text) => <({
  String graphemes,
  String phonemeId,
})>[
  for (final ch in text.split(''))
    (graphemes: ch, phonemeId: _phonemeForLetter[ch] ?? 'AH'),
];

WordToken _w(String text) => WordToken(
  text: text,
  graphemePhonemeMap: _gpm(text),
  pronunciationAudioRef: 'audio/words/$text.wav',
);

/// A paragraph-length body: the reading screen's worst layout case (PRD §9
/// A-8 bounds paragraph levels at 40-90 words).
const List<String> _paragraphWords = <String>[
  'the', 'otter', 'sat', 'on', 'a', 'log', 'and', 'the', 'log', 'rolled',
  'down', 'the', 'hill', 'into', 'the', 'cold', 'green', 'river', 'where',
  'the', 'fish', 'were', 'hiding', 'under', 'the', 'roots', 'of', 'an', 'old',
  'tree', 'that', 'had', 'fallen', 'in', 'the', 'storm', 'last', 'winter',
  'before', 'the', 'snow', 'came', 'down', 'across', 'the', 'whole', 'valley',
];

Story _story(String id, String levelId, List<String> words) => Story(
  id: id,
  levelId: levelId,
  title: 'Story $id',
  pages: <Page>[
    Page(
      sentences: <Sentence>[
        Sentence(words: <WordToken>[for (final t in words) _w(t)]),
      ],
    ),
  ],
  riveAnimationRef: 'rive/$id.riv',
  celebrationAudioRef: 'audio/celebration/$id.wav',
  collectibleRef: 'collectible.$id',
  skillsExercised: const <PhonicsSkill>[],
  packId: 'pack.starter',
  contentVersion: '1',
);

/// A beyond-launch content graph: 12 stories, 4 twisters, 12 collectibles,
/// 16 grapheme cards. If the shell's chrome is going to clip anything at a
/// phone-landscape size, this is what surfaces it.
final String _phonicsJson = jsonEncode(<String, Object?>{
  'levels': <Object?>[
    <String, Object?>{
      'id': 'level.1',
      'ordinal': 1,
      'format': 'multiSentence',
      'vocabEnabled': false,
      'heartWords': <String>[],
      'skills': <Object?>[
        <String, Object?>{
          'id': 'skill.1',
          'name': 'CVC',
          'sequenceOrder': 1,
          'introducesGraphemes': <String>['a', 'c', 't', 's'],
        },
      ],
    },
  ],
  'stories': <Object?>[
    for (var i = 1; i <= 12; i++)
      <String, Object?>{'id': 'story.$i', 'levelId': 'level.1'},
  ],
});

StoryPack _starterStoryPack() => StoryPack(
  id: 'pack.starter',
  version: '1.0.0',
  minAppVersion: '1.0.0',
  stories: <Story>[
    // story.1 is the paragraph-length worst case the reading route renders.
    _story('story.1', 'level.1', _paragraphWords),
    for (var i = 2; i <= 12; i++)
      _story('story.$i', 'level.1', const <String>['the', 'cat', 'sat']),
  ],
  twisters: <TongueTwister>[
    for (var i = 1; i <= 4; i++)
      TongueTwister(
        id: 'twister.$i',
        levelId: 'level.1',
        words: <WordToken>[_w('sam'), _w('sat')],
        targetPhonemeId: 'S',
        narrationAudioRef: 'audio/twisters/twister.$i.wav',
        packId: 'pack.starter',
      ),
  ],
  vocabCards: const <VocabCard>[],
  collectibles: <Collectible>[
    for (var i = 1; i <= 12; i++)
      Collectible(
        id: 'collectible.story.$i',
        storyId: 'story.$i',
        riveRef: 'rive/collectibles/$i.riv',
        sceneSlot: '${i ~/ 4}:${i % 4}',
      ),
  ],
  graphemeSounds: <GraphemeSound>[
    for (var i = 0; i < 16; i++)
      GraphemeSound(
        id: 'grapheme.$i',
        grapheme: 'g$i',
        phonemeIds: const <String>['S'],
        introducedAtLevelId: 'level.1',
        exampleWords: const <
          ({String wordText, String pronunciationAudioRef, String minLevelId})
        >[],
      ),
  ],
  assetRefs: const <String>[],
  checksum: '',
);

Profile _profile() => Profile(
  localId: 'profile.ada',
  displayName: 'Ada',
  ageBand: AgeBand.fiveToSix,
  currentLevelId: 'level.1',
  micConsent: true,
  cloudAsrConsent: false,
  createdAt: DateTime.utc(2026, 1, 1),
);

class _NoNetworkTransport implements AnalyticsTransport {
  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async =>
      TransportResult.success;
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The Material/Cupertino component types that must never appear on a
/// child-facing route: the shell applies the storybook design system, so
/// stock chrome showing through is a regression, not a style preference
/// (PRD §8 Unit 1: "the UI feels drawn, not assembled from Material/Cupertino
/// components. No stock component styling may be visible in child-facing
/// screens").
const List<Type> _bannedStockChrome = <Type>[
  AppBar,
  SliverAppBar,
  BottomNavigationBar,
  NavigationBar,
  NavigationRail,
  Drawer,
  FloatingActionButton,
  Card,
  ListTile,
  Chip,
  ElevatedButton,
  TextButton,
  OutlinedButton,
  Switch,
  Slider,
  TabBar,
];

class _Harness {
  late final Directory analyticsDir;
  late final Directory starterDir;
  late final Directory installedDir;
  late final ProviderContainer container;
  late final AppDatabase db;

  Future<void> setUp() async {
    analyticsDir = Directory.systemTemp.createTempSync('layout_smoke_analytics_');
    starterDir = Directory.systemTemp.createTempSync('layout_smoke_starter_');
    installedDir = Directory.systemTemp.createTempSync('layout_smoke_installed_');

    container = ProviderContainer(
      overrides: <Override>[
        databaseExecutorProvider.overrideWithValue(NativeDatabase.memory()),
        starterPackProvider.overrideWithValue(
          LoadedPack(pack: _starterStoryPack(), directory: starterDir),
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
        phonemeAudioRefsProvider.overrideWithValue(
          const <String, AudioRef>{'S': 'audio/phonemes/S.wav'},
        ),
        installIdProvider.overrideWithValue(_installId),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
        analyticsTransportProvider.overrideWithValue(_NoNetworkTransport()),
        analyticsStorageDirectoryProvider.overrideWithValue(analyticsDir),
        catalogFetcherProvider.overrideWithValue(null),
        appVersionProvider.overrideWithValue('1.0.0'),
      ],
    );

    db = container.read(appDatabaseProvider);
    await db.profilesDao.insertProfile(_profile());
    // Half the trail completed, so the map renders all three node treatments
    // (completed / awake / asleep) plus the collection scene's earned slots.
    for (var i = 1; i <= 6; i++) {
      await db.storyProgressDao.upsertProgress(
        StoryProgress(
          profileId: 'profile.ada',
          storyId: 'story.$i',
          status: StoryStatus.completed,
          completedAt: DateTime.utc(2026, 1, 1),
          timesRead: 1,
        ),
      );
      await db.collectionDao.grantCollectible(
        profileId: 'profile.ada',
        collectibleId: 'collectible.story.$i',
      );
    }
  }

  void tearDown() {
    container.dispose();
    for (final d in <Directory>[analyticsDir, starterDir, installedDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  }

  Widget get app => UncontrolledProviderScope(
    container: container,
    child: const LearnToReadApp(),
  );

  GoRouter get router => container.read(appRouterProvider);
}

void main() {
  late _Harness h;

  /// Registers the shell harness for the enclosing group only.
  ///
  /// Deliberately per-group rather than file-level: the token-lint group below
  /// is a pure static scan of lib/app/ and must not be coupled to whether the
  /// shell can be constructed at all.
  void useHarness() {
    setUp(() async {
      h = _Harness();
      await h.setUp();
    });
    tearDown(() => h.tearDown());
  }

  /// Boots the shell at [size], selects the profile, and lands on [path].
  Future<void> pumpRoute(
    WidgetTester tester,
    Size size,
    String path, {
    bool selectProfile = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(h.app);
    await _pumpFrames(tester);
    if (selectProfile) {
      await tester.tap(find.byKey(const Key('profile-picker-tile-profile.ada')));
      await _pumpFrames(tester);
    }
    if (path != kRoutePathProfilePicker) {
      h.router.go(path);
      await _pumpFrames(tester);
    }
  }

  // =========================================================================
  group('all four layout classes render every child-facing route (accept 7)', () {
    useHarness();

    for (final entry in _layoutSizes.entries) {
      final className = entry.key;
      final size = entry.value;

      testWidgets('POSITIVE: $className -- profile picker lays out cleanly', (
        tester,
      ) async {
        await pumpRoute(
          tester,
          size,
          kRoutePathProfilePicker,
          selectProfile: false,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('POSITIVE: $className -- progress map (library) lays out cleanly', (
        tester,
      ) async {
        await pumpRoute(tester, size, kRoutePathMap);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'POSITIVE: $className -- the reading screen lays out cleanly with '
        'paragraph-length text and its stage region',
        (tester) async {
          await pumpRoute(tester, size, '/reading/story.1');
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('word-text-0')), findsOneWidget);
        },
      );

      testWidgets('POSITIVE: $className -- the collection scene lays out cleanly', (
        tester,
      ) async {
        await pumpRoute(tester, size, kRoutePathCollection);
        expect(tester.takeException(), isNull);
      });

      testWidgets('POSITIVE: $className -- the Sound Garden lays out cleanly', (
        tester,
      ) async {
        await pumpRoute(tester, size, kRoutePathSoundGarden);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // =========================================================================
  group('no stock Material/Cupertino chrome on child-facing routes (accept 6)', () {
    useHarness();

    for (final path in <String>[
      kRoutePathMap,
      kRoutePathCollection,
      kRoutePathSoundGarden,
    ]) {
      testWidgets('NEGATIVE: $path renders none of the stock components', (
        tester,
      ) async {
        await pumpRoute(tester, _layoutSizes['phonePortrait']!, path);

        for (final type in _bannedStockChrome) {
          expect(
            find.byType(type),
            findsNothing,
            reason: '$type is stock chrome and must not be visible on $path',
          );
        }
      });
    }
  });

  // =========================================================================
  group('token lint extends to lib/app/ (accept 6)', () {
    test(
      'POSITIVE: no file under lib/app/ contains a raw Color(0x...) literal, '
      'a Colors.* reference, or an inline TextStyle fontFamily literal',
      () {
        final violations = _scanDirectory(Directory('lib/app'), <RegExp>[
          _colorLiteral,
          _colorsDot,
          _inlineFont,
        ]);
        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );

    test(
      'POSITIVE: no file under lib/app/ references a Cupertino component -- '
      'the shell is one design system, not two',
      () {
        final violations = _scanDirectory(Directory('lib/app'), <RegExp>[
          _cupertino,
        ]);
        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );

    test('NEGATIVE: the scanner itself flags a planted violation', () {
      final temp = Directory.systemTemp.createTempSync('layout_smoke_lint_');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      File('${temp.path}/bad.dart').writeAsStringSync(
        'final ink = Color(0xFF112233);\ncolor: Colors.red,\n',
      );
      expect(
        _scanDirectory(temp, <RegExp>[_colorLiteral, _colorsDot, _inlineFont]),
        hasLength(2),
      );
    });

    test('EDGE: a missing lib/app/ directory scans to zero violations', () {
      expect(
        _scanDirectory(Directory('lib/does-not-exist'), <RegExp>[_colorLiteral]),
        isEmpty,
      );
    });
  });

  // =========================================================================
  group('[DEVICE] Unit 1 golden acceptance (routed to the ticket owner)', () {
    test(
      '[DEVICE] golden: the library (progress map) in all four layout classes',
      () {},
      skip: '[DEVICE] Pixel goldens are owner-verified: the illustrated trail '
          'is owner-commissioned artwork (PRD §10 OQ-4) and the Rive stage '
          'needs a licensed runtime asset that does not exist in this '
          'container. The headless proxy above pins no-overflow at all four '
          'classes.',
    );

    test(
      '[DEVICE] golden: the reading screen in all four layout classes, with '
      'an unclipped Rive stage region',
      () {},
      skip: '[DEVICE] Same reason: no licensed Rive asset and no owner '
          'illustration in this container. "Clipped Rive stage" is a pixel '
          'property no headless assertion can stand in for.',
    );

    test(
      '[DEVICE] golden: the collection scene in all four layout classes',
      () {},
      skip: '[DEVICE] Same reason. Also covers the colour-vision simulation '
          'screenshots (protanopia/deuteranopia) in PRD §8 Unit 1, which are '
          'a design-review artefact rather than a test assertion.',
    );
  });
}
