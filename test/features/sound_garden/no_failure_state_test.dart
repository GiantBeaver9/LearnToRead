// Negative-space test suite for the Sound Garden feature (PRD §8 Unit 15
// "The echo is optional and there is no failure state -- a card never says
// 'wrong'"; "No completion state, no collectibles, no progression
// mechanics exist anywhere in the feature"; ticket sound-garden accept
// entries 5, 9).
//
// This file covers TWO distinct negative guarantees:
//   (a) behaviorally, a non-matching echo attempt leaves a card in its
//       neutral/listening state -- no negative widget ever appears;
//   (b) structurally, no file under lib/features/sound_garden/ references
//       any completion/collectible/progression concept -- this is a free
//       practice space with no API surface for "done".
//
// lib/features/sound_garden/sound_garden_screen.dart does not exist yet:
// the behavioral group's import fails to resolve, which is the expected
// red state for this file as a whole (mirrors token_lint_test.dart's
// structure: a compile-red top-level import plus a scanner group that is
// vacuously green against a directory that does not exist yet, and
// becomes the real gate the moment lib/features/sound_garden/ is created).
//
// See sound_garden_screen_test.dart for the canonical pinned API.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/sound_garden/sound_garden_screen.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

List<Level> _levels() => [
      Level(
        id: 'level.1',
        ordinal: 1,
        newSkills: const [],
        format: LevelFormat.sentence,
        vocabEnabled: false,
      ),
    ];

GraphemeSound _card() => GraphemeSound(
      id: 'gs.sh',
      grapheme: 'sh',
      phonemeIds: const ['SH'],
      introducedAtLevelId: 'level.1',
      exampleWords: const [],
    );

Profile _profile() => Profile(
      localId: 'profile.amara',
      displayName: 'Amara',
      ageBand: AgeBand.fiveToSix,
      currentLevelId: 'level.1',
      micConsent: true,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

Hypothesis _phones(List<String> phones) =>
    Hypothesis(wordHypotheses: const ['<phones>'], phoneHypotheses: phones);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('behavioral: a non-matching echo leaves the card neutral '
      '(accept 5)', () {
    testWidgets(
        'NEGATIVE: hypotheses that never cross the A-13 threshold produce '
        'no sparkle and no other new widget -- the card stays in its '
        'listening/neutral state indefinitely', (tester) async {
      final audioService = FakeAudioService();
      // 'Z' never aligns with the target 'SH' at distance <= 1, so the
      // scorer's matchedFraction stays 0.0 forever regardless of how many
      // times it is produced.
      final echoEngine = FakeAsrEngine(
        script: [_phones(const ['Z']), _phones(const ['Z']), _phones(const ['Z'])],
      );

      await tester.pumpWidget(_wrap(SoundGardenScreen(
        profile: _profile(),
        profileOrdinal: 1,
        levelOrdinal: 1,
        installId: _installId,
        inventory: [_card()],
        levels: _levels(),
        audioService: audioService,
        phonemeAudioRefs: const {'SH': 'audio/phonemes/SH.mp3'},
        downloadedExampleWordAudioRefs: const {},
        echoEngine: echoEngine,
        buildScorer: (card) => SoundModeScorer(
          targetPhonemeSequence: card.phonemeIds,
          targetPhonemeId: card.phonemeIds.first,
        ),
        onAnalyticsEvent: (_) {},
      )));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('sound-card-gs.sh')));
      await tester.pump(); // issue play()
      final plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(1));
      audioService.completePlayback(plays.single.handle);
      await tester.pumpAndSettle();

      // Neutral: still listening, no sparkle, and — the whole point of
      // this test — no widget tree anywhere under this screen carries a
      // key naming a negative/failure concept.
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.sh')), findsOneWidget);
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.sh')), findsNothing);
      expect(find.textContaining('wrong', findRichText: true), findsNothing);
      expect(find.textContaining('Wrong', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);

      for (final bannedKeyFragment in ['wrong', 'error', 'fail', 'negative', 'red-x']) {
        expect(
          find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.contains(bannedKeyFragment)),
          findsNothing,
          reason: 'no widget key may name the "$bannedKeyFragment" concept',
        );
      }
    });
  });

  group('structural: no completion/collectible/progression API surface '
      '(accept 9)', () {
    Directory soundGardenDir() => Directory('lib/features/sound_garden');

    List<File> soundGardenDartFiles() {
      final dir = soundGardenDir();
      if (!dir.existsSync()) return const [];
      return dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    }

    test(
      'NEGATIVE: no file under lib/features/sound_garden/ imports a '
      'completion/collectible/progression DAO (CollectionDao, '
      'StoryProgressDao, TwisterProgressDao) -- vacuously true before the '
      'feature exists, becomes the real gate once it does',
      () {
        const bannedImports = [
          'collection_dao.dart',
          'story_progress_dao.dart',
          'twister_progress_dao.dart',
        ];
        final violations = <String>[];
        for (final file in soundGardenDartFiles()) {
          final source = file.readAsStringSync();
          for (final banned in bannedImports) {
            if (source.contains(banned)) {
              violations.add('${file.path} imports $banned');
            }
          }
        }
        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );

    test(
      'NEGATIVE: no file under lib/features/sound_garden/ references '
      'CollectionState, StoryProgress, TwisterProgress, or Collectible -- '
      'this is a free practice space, observed only via sound_card_played '
      '/ sound_card_echo analytics (PRD §8 Unit 15)',
      () {
        const bannedTypes = [
          'CollectionState',
          'StoryProgress',
          'TwisterProgress',
          'Collectible',
        ];
        final violations = <String>[];
        for (final file in soundGardenDartFiles()) {
          final source = file.readAsStringSync();
          for (final banned in bannedTypes) {
            if (source.contains(banned)) {
              violations.add('${file.path} references $banned');
            }
          }
        }
        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );

    test(
      'NEGATIVE: no file under lib/features/sound_garden/ references a '
      '"completed"/"collectible"/"progress" concept by name at all -- a '
      'stricter lexical scan than the type-name check above, catching a '
      'differently-named completion concept the type check would miss',
      () {
        const bannedWords = ['completion', 'completed', 'collectible', 'progression'];
        final violations = <String>[];
        for (final file in soundGardenDartFiles()) {
          final lower = file.readAsStringSync().toLowerCase();
          for (final banned in bannedWords) {
            if (lower.contains(banned)) {
              violations.add('${file.path} contains "$banned"');
            }
          }
        }
        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );

    test(
      'POSITIVE (scanner self-check): the scanner used above correctly '
      'flags a fixture file that DOES reference a banned concept, proving '
      'the vacuous passes above are "not yet built", not "cannot detect"',
      () {
        final tempDir = Directory.systemTemp.createTempSync('no_failure_state_test_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        File('${tempDir.path}/oops.dart').writeAsStringSync(
          'import "../collection/collection_dao.dart";\nclass X { StoryProgress? p; }\n',
        );

        final files = tempDir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();
        var violationCount = 0;
        for (final file in files) {
          final source = file.readAsStringSync();
          if (source.contains('collection_dao.dart') || source.contains('StoryProgress')) {
            violationCount++;
          }
        }
        expect(violationCount, greaterThan(0));
      },
    );
  });
}
