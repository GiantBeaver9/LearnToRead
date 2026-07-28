// Test suite for lib/features/sound_garden/sound_garden_screen.dart (PRD
// §8 Unit 15 "Sound Garden (phonetic practice area)"; ticket sound-garden
// accept entries 1, 3, 4, 10, 11).
//
// None of lib/features/sound_garden/{sound_garden_screen,sound_card,
// sound_card_controller,echo_session,example_words}.dart exist yet: every
// import below fails to resolve, which is the expected red state.
//
// THIS FILE IS THE CANONICAL PINNED API for the whole ticket. Sibling files
// (awake_muted_test.dart, echo_session_test.dart, example_words_test.dart,
// no_failure_state_test.dart, layout_classes_test.dart) restate only the
// slice of this API they exercise, exactly as reading_tracker_test.dart is
// canonical for the listening-tracker ticket's five-file suite.
//
// =============================================================================
// PINNED API (implementation does not exist yet -- red-for-right-reason)
// =============================================================================
//
// lib/features/sound_garden/sound_card_controller.dart:
//
//   enum CardWakeState { awake, muted }
//
//   /// Pure derivation (PRD §8 Unit 15 "Visibility (ratified)"): awake iff
//   /// `card.introducedAtLevelId`'s ordinal (resolved against `levels`) is
//   /// <= `profile.currentLevelId`'s ordinal -- INCLUSIVE boundary (a card
//   /// introduced at exactly the profile's current level is awake, never
//   /// muted). Ordinals are resolved via `levels.firstWhere((l) => l.id ==
//   /// ...)`, mirroring the idiom in lib/pipeline/cumulative_grapheme_set.dart
//   /// and lib/pipeline/decodability_linter.dart. Throws ArgumentError if
//   /// either id is not found in `levels`.
//   CardWakeState wakeStateFor({
//     required GraphemeSound card,
//     required Profile profile,
//     required List<Level> levels,
//   });
//
//   /// Plays `card.phonemeIds` in order, gaplessly: each phoneme's audio is
//   /// awaited via `audioService.completionOf` before the next one's `play()`
//   /// is issued -- the same gapless mechanism PhonemeSequencer uses for a
//   /// WordToken's graphemePhonemeMap (PRD §8 Unit 15 "gapless via
//   /// PhonemeSequencer"; GraphemeSound has no WordToken to hand
//   /// PhonemeSequencer directly, so this is the raw-phonemeId-list
//   /// equivalent of the same sequencing contract). Throws
//   /// PhonemeAudioNotFoundException-equivalent (propagates
//   /// AudioRefNotFoundException from audioService) if a phonemeId has no
//   /// entry in phonemeAudioRefs; the sequence stops at the failing phoneme.
//   Future<void> playSoundCard(
//     GraphemeSound card, {
//     required AudioService audioService,
//     required Map<String, AudioRef> phonemeAudioRefs,
//     AudioChannel channel = AudioChannel.help,
//   });
//
// lib/features/sound_garden/sound_card.dart:
//
//   enum CardEchoState { hidden, listening, matched }
//
//   /// Presentational, fully controlled by props -- mirrors MapNode's
//   /// marker-widget convention (see test/features/map/map_states_test.dart):
//   /// every marker below is a zero-size KeyedSubtree sibling, findable by
//   /// Key without depending on paint/pixel output.
//   ///
//   /// PINNED CONTRAST vs MapNode: MapNode's asleep nodes swallow taps
//   /// (`onTap: isTappable ? onTap : null`). SoundCardWidget deliberately
//   /// does NOT gate on wakeState -- PRD §8 Unit 15: "Muted cards are still
//   /// fully tappable and echoable." `onTap` is wired unconditionally,
//   /// regardless of `wakeState`.
//   ///
//   /// Structural markers (id == card.id):
//   ///   - ValueKey('sound-card-<id>')              the tap target (GestureDetector),
//   ///                                               onTap ALWAYS wired
//   ///   - ValueKey('sound-card-text-<id>')          the grapheme face Text;
//   ///                                               .data == card.grapheme,
//   ///                                               style.fontFamily ==
//   ///                                               DesignTokens.readingFontFamily
//   ///   - ValueKey('sound-card-muted-<id>')         present iff wakeState == muted
//   ///   - ValueKey('sound-card-echo-prompt-<id>')   present iff echoState == listening
//   ///   - ValueKey('sound-card-sparkle-<id>')       present iff echoState == matched
//   class SoundCardWidget extends StatelessWidget {
//     const SoundCardWidget({
//       super.key,
//       required GraphemeSound card,
//       required CardWakeState wakeState,
//       CardEchoState echoState = CardEchoState.hidden,
//       required VoidCallback onTap,
//     });
//   }
//
// lib/features/sound_garden/echo_session.dart:
//
//   /// The outcome of one echo attempt.
//   class EchoResult {
//     const EchoResult({required bool matched, required double matchedFraction});
//     final bool matched;
//     final double matchedFraction;
//   }
//
//   /// A lightweight engine+scorer loop (ticket note: "do NOT pull in
//   /// listening-tracker -- no words, no silence/struggle/tap semantics
//   /// here"). See echo_session_test.dart for the full pinned contract.
//   class EchoSession {
//     EchoSession({
//       required AsrEngine engine,
//       required SoundModeScorer scorer,
//       List<String> biasingContext = const [],
//     });
//     bool get isListening;
//     bool get matched;
//     double get matchedFraction;
//     void start({void Function()? onMatch});
//     EchoResult stop();
//   }
//
// lib/features/sound_garden/example_words.dart: see example_words_test.dart
// for the full pinned contract (visibleExampleWords, highlightRangeFor,
// ExampleWordChip). Not exercised directly by this file.
//
// lib/features/sound_garden/sound_garden_screen.dart:
//
//   /// Renders the FULL `inventory` (PRD: "all cards visible from day one")
//   /// as SoundCardWidgets. Tapping a card:
//   ///   1. fires `sound_card_played` (AnalyticsEventName.soundCardPlayed,
//   ///      no event-specific fields) via onAnalyticsEvent,
//   ///   2. calls playSoundCard(...) and awaits it,
//   ///   3. once playback completes, IF profile.micConsent: sets that card's
//   ///      echoState to listening, builds a scorer via
//   ///      `buildScorer(card)`, constructs an EchoSession(engine:
//   ///      echoEngine, scorer: ...) and calls `start(onMatch: ...)`; the
//   ///      onMatch callback sets echoState to matched and fires
//   ///      `sound_card_echo` (fields: {'matched': true}) exactly once.
//   ///      IF !profile.micConsent: echoState stays hidden and echoEngine
//   ///      is never touched (`start` never called) -- listen-only mode.
//   class SoundGardenScreen extends StatefulWidget {
//     const SoundGardenScreen({
//       super.key,
//       required Profile profile,
//       required int profileOrdinal,
//       required int levelOrdinal,
//       required String installId,
//       required List<GraphemeSound> inventory,
//       required List<Level> levels,
//       required AudioService audioService,
//       required Map<String, AudioRef> phonemeAudioRefs,
//       required Set<AudioRef> downloadedExampleWordAudioRefs,
//       required AsrEngine echoEngine,
//       required SoundModeScorer Function(GraphemeSound card) buildScorer,
//       required void Function(AnalyticsEvent event) onAnalyticsEvent,
//     });
//   }
//
// Genuinely unpinned by the PRD/ticket (this suite therefore treats these
// as builder/injection points, never asserts a specific choice):
//   - Which phonemeId (if any) is the "drilled"/double-weighted phoneme for
//     a Sound Garden card's echo scoring -- GraphemeSound has no
//     `targetPhonemeId` field (unlike TongueTwister). `buildScorer` is
//     supplied by the caller for exactly this reason.
//   - The exact `biasingContext` EchoSession.start() passes to
//     `engine.start()` -- sound mode does not require expected-text
//     hybridization (that is a word-mode concept, PRD §6), so this suite
//     only ever asserts whether `engine.start` was called, never with what
//     argument.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/sound_garden/sound_garden_screen.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

List<Level> _levels() => [
      for (var i = 1; i <= 5; i++)
        Level(
          id: 'level.$i',
          ordinal: i,
          newSkills: const [],
          format: LevelFormat.sentence,
          vocabEnabled: false,
        ),
    ];

GraphemeSound _card(
  String id,
  String grapheme,
  List<String> phonemeIds,
  String introducedAtLevelId, {
  List<({String wordText, String pronunciationAudioRef, String minLevelId})>
      exampleWords = const [],
}) =>
    GraphemeSound(
      id: id,
      grapheme: grapheme,
      phonemeIds: phonemeIds,
      introducedAtLevelId: introducedAtLevelId,
      exampleWords: exampleWords,
    );

/// The fixture inventory: six cards spanning the categories PRD §8 Unit 15
/// names (short vowel, digraph, blend, vowel team, diphthong,
/// r-controlled), at varying introduced levels -- some awake, some muted,
/// against a profile at level.3.
List<GraphemeSound> _inventory() => [
      _card('gs.a', 'a', const ['AE'], 'level.1'),
      _card('gs.sh', 'sh', const ['SH'], 'level.2'),
      _card('gs.bl', 'bl', const ['B', 'L'], 'level.3'),
      _card('gs.ea', 'ea', const ['IY'], 'level.4'),
      _card('gs.oi', 'oi', const ['OI'], 'level.5'),
      _card('gs.ar', 'ar', const ['AR'], 'level.5'),
    ];

Profile _profile({bool micConsent = true, String currentLevelId = 'level.3'}) =>
    Profile(
      localId: 'profile.amara',
      displayName: 'Amara',
      ageBand: AgeBand.fiveToSix,
      currentLevelId: currentLevelId,
      micConsent: micConsent,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

Map<String, AudioRef> _phonemeAudioRefs() => const {
      'AE': 'audio/phonemes/AE.mp3',
      'SH': 'audio/phonemes/SH.mp3',
      'B': 'audio/phonemes/B.mp3',
      'L': 'audio/phonemes/L.mp3',
      'IY': 'audio/phonemes/IY.mp3',
      'OI': 'audio/phonemes/OI.mp3',
      'AR': 'audio/phonemes/AR.mp3',
    };

Hypothesis _phones(List<String> phones) =>
    Hypothesis(wordHypotheses: const ['<phones>'], phoneHypotheses: phones);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Drains FakeAudioService's play log in order by completing each handle in
/// turn, pumping after every completion so the widget can react before the
/// next `play()` (if any) is issued -- proves gaplessness as a side effect:
/// if a second play() were issued before the first completes, `callLog`
/// would already contain it before this helper gets to it.
Future<void> _drainSequentialPlayback(
  WidgetTester tester,
  FakeAudioService audioService,
  int expectedPlayCount,
) async {
  var drained = 0;
  while (drained < expectedPlayCount) {
    await tester.pump();
    final playEntries = audioService.callLog.whereType<PlayLogEntry>().toList();
    expect(
      playEntries.length,
      greaterThan(drained),
      reason: 'expected another play() to have been issued by now',
    );
    audioService.completePlayback(playEntries[drained].handle);
    drained++;
  }
  // Orchestrator test-fix: two pumps, not one. The completion delivered
  // above resolves during the next pump's microtask flush, which runs
  // after that pump's hasScheduledFrame check - a setState fired there
  // (engine start, listening marker) can only render on a second pump.
  // Same framework constraint fixed in spike_channel_test (929dc3b).
  await tester.pump();
  await tester.pump();
}

void main() {
  group('SoundGardenScreen — full inventory rendered (accept 1, 2)', () {
    testWidgets(
        'POSITIVE: all six fixture cards render their tap target, '
        'regardless of awake/muted state', (tester) async {
      final inventory = _inventory();
      await tester.pumpWidget(_wrap(SoundGardenScreen(
        profile: _profile(),
        profileOrdinal: 1,
        levelOrdinal: 3,
        installId: _installId,
        inventory: inventory,
        levels: _levels(),
        audioService: FakeAudioService(),
        phonemeAudioRefs: _phonemeAudioRefs(),
        downloadedExampleWordAudioRefs: const {},
        echoEngine: FakeAsrEngine(script: const []),
        buildScorer: (card) => SoundModeScorer(
          targetPhonemeSequence: card.phonemeIds,
          targetPhonemeId: card.phonemeIds.first,
        ),
        onAnalyticsEvent: (_) {},
      )));
      await tester.pump();

      for (final card in inventory) {
        expect(
          find.byKey(ValueKey('sound-card-${card.id}')),
          findsOneWidget,
          reason: '${card.id} must render even though it may be muted',
        );
      }
    });

    testWidgets(
        'POSITIVE: card face shows the grapheme large in the reading '
        'typeface (token-styled)', (tester) async {
      await tester.pumpWidget(_wrap(SoundGardenScreen(
        profile: _profile(),
        profileOrdinal: 1,
        levelOrdinal: 3,
        installId: _installId,
        inventory: _inventory(),
        levels: _levels(),
        audioService: FakeAudioService(),
        phonemeAudioRefs: _phonemeAudioRefs(),
        downloadedExampleWordAudioRefs: const {},
        echoEngine: FakeAsrEngine(script: const []),
        buildScorer: (card) => SoundModeScorer(
          targetPhonemeSequence: card.phonemeIds,
          targetPhonemeId: card.phonemeIds.first,
        ),
        onAnalyticsEvent: (_) {},
      )));
      await tester.pump();

      final textFinder = find.byKey(const ValueKey('sound-card-text-gs.sh'));
      expect(textFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.data, 'sh');
      expect(textWidget.style?.fontFamily, DesignTokens.readingFontFamily);
    });
  });

  group('SoundGardenScreen — tap plays phonemes gaplessly, in order '
      '(accept 3)', () {
    testWidgets(
        'POSITIVE: tapping a multi-phoneme card (blend "bl") plays B then '
        'L, and the second play is not issued until the first completes',
        (tester) async {
      final audioService = FakeAudioService();
      await tester.pumpWidget(_wrap(SoundGardenScreen(
        profile: _profile(),
        profileOrdinal: 1,
        levelOrdinal: 3,
        installId: _installId,
        inventory: _inventory(),
        levels: _levels(),
        audioService: audioService,
        phonemeAudioRefs: _phonemeAudioRefs(),
        downloadedExampleWordAudioRefs: const {},
        echoEngine: FakeAsrEngine(script: const []),
        buildScorer: (card) => SoundModeScorer(
          targetPhonemeSequence: card.phonemeIds,
          targetPhonemeId: card.phonemeIds.first,
        ),
        onAnalyticsEvent: (_) {},
      )));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('sound-card-gs.bl')));
      await tester.pump();

      // Only the FIRST phoneme's play should be issued so far -- gapless
      // means sequential, not simultaneous.
      var plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(1));
      expect(plays.single.ref, 'audio/phonemes/B.mp3');
      expect(plays.single.channel, AudioChannel.help);

      audioService.completePlayback(plays.single.handle);
      await tester.pump();

      plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(2), reason: 'L plays only after B completes');
      expect(plays[1].ref, 'audio/phonemes/L.mp3');

      audioService.completePlayback(plays[1].handle);
      await tester.pump();

      plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(2), reason: 'no further phonemes to play');
    });
  });

  group('SoundGardenScreen — echo path + sparkle on match (accept 4)', () {
    testWidgets(
        'POSITIVE: after playback, with consent, the echo prompt appears '
        'and the engine is started; a matching hypothesis earns the '
        'sparkle', (tester) async {
      final audioService = FakeAudioService();
      // Orchestrator test-fix: with zero delivery delay the SH hypothesis
      // resolves in the same microtask flush as engine.start, so the
      // pinned intermediate state (prompt visible, sparkle absent) is
      // unobservable. Deliver on the fake's own timer; pumpAndSettle
      // then advances it to the match.
      final echoEngine = FakeAsrEngine(
        script: [_phones(const ['SH'])],
        delayBetweenHypotheses: const Duration(milliseconds: 50),
      );
      await tester.pumpWidget(_wrap(SoundGardenScreen(
        profile: _profile(micConsent: true),
        profileOrdinal: 1,
        levelOrdinal: 3,
        installId: _installId,
        inventory: _inventory(),
        levels: _levels(),
        audioService: audioService,
        phonemeAudioRefs: _phonemeAudioRefs(),
        downloadedExampleWordAudioRefs: const {},
        echoEngine: echoEngine,
        buildScorer: (card) => SoundModeScorer(
          targetPhonemeSequence: card.phonemeIds,
          targetPhonemeId: card.phonemeIds.first,
          matchThreshold: kSoundModeMatchThreshold,
          perPhonemeMaxDistance: kSoundModePerPhonemeMaxDistance,
          targetPhonemeWeight: kSoundModeTargetPhonemeWeight,
        ),
        onAnalyticsEvent: (_) {},
      )));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('sound-card-gs.sh')));
      await _drainSequentialPlayback(tester, audioService, 1);

      expect(echoEngine.recordedBiasingContext, isNotNull,
          reason: 'engine.start must be called once playback ends, with '
              'consent granted');
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.sh')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.sh')), findsNothing);

      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.sh')), findsOneWidget,
          reason: 'the scripted SH hypothesis matches the target sequence');
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.sh')), findsNothing);
    });
  });

  group('SoundGardenScreen — analytics (accept 10)', () {
    testWidgets(
        'POSITIVE: sound_card_played fires on tap; sound_card_echo(matched: '
        'true) fires exactly once when the echo matches', (tester) async {
      final audioService = FakeAudioService();
      final echoEngine = FakeAsrEngine(script: [_phones(const ['SH'])]);
      final events = <AnalyticsEvent>[];
      await tester.pumpWidget(_wrap(SoundGardenScreen(
        profile: _profile(micConsent: true),
        profileOrdinal: 2,
        levelOrdinal: 3,
        installId: _installId,
        inventory: _inventory(),
        levels: _levels(),
        audioService: audioService,
        phonemeAudioRefs: _phonemeAudioRefs(),
        downloadedExampleWordAudioRefs: const {},
        echoEngine: echoEngine,
        buildScorer: (card) => SoundModeScorer(
          targetPhonemeSequence: card.phonemeIds,
          targetPhonemeId: card.phonemeIds.first,
        ),
        onAnalyticsEvent: events.add,
      )));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('sound-card-gs.sh')));
      await _drainSequentialPlayback(tester, audioService, 1);
      await tester.pumpAndSettle();

      final played = events.where((e) => e.name == AnalyticsEventName.soundCardPlayed);
      expect(played, hasLength(1));
      expect(played.single.storyId, isNull);
      expect(played.single.fields, isEmpty);
      // Base fields conform to the §5 payload contract regardless of this
      // event's own schema tests (analytics ticket owns full schema
      // coverage) -- a light sanity check that this call site builds a
      // valid payload at all.
      expect(() => validateEventPayload(played.single.toPayload()), returnsNormally);

      final echoed = events.where((e) => e.name == AnalyticsEventName.soundCardEcho);
      expect(echoed, hasLength(1));
      expect(echoed.single.fields['matched'], isTrue);
      expect(() => validateEventPayload(echoed.single.toPayload()), returnsNormally);
    });
  });

  group('SoundGardenScreen — consent-off is listen-only (accept 11)', () {
    testWidgets(
        'NEGATIVE: with micConsent off, playback still works but no echo '
        'prompt ever appears and the engine is never started', (tester) async {
      final audioService = FakeAudioService();
      final echoEngine = FakeAsrEngine(script: [_phones(const ['SH'])]);
      final events = <AnalyticsEvent>[];
      await tester.pumpWidget(_wrap(SoundGardenScreen(
        profile: _profile(micConsent: false),
        profileOrdinal: 1,
        levelOrdinal: 3,
        installId: _installId,
        inventory: _inventory(),
        levels: _levels(),
        audioService: audioService,
        phonemeAudioRefs: _phonemeAudioRefs(),
        downloadedExampleWordAudioRefs: const {},
        echoEngine: echoEngine,
        buildScorer: (card) => SoundModeScorer(
          targetPhonemeSequence: card.phonemeIds,
          targetPhonemeId: card.phonemeIds.first,
        ),
        onAnalyticsEvent: events.add,
      )));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('sound-card-gs.sh')));
      await _drainSequentialPlayback(tester, audioService, 1);
      await tester.pumpAndSettle();

      expect(echoEngine.recordedBiasingContext, isNull,
          reason: 'no engine may ever be started without mic consent');
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.sh')), findsNothing);
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.sh')), findsNothing);

      // Listen-only: the card still plays its sound.
      expect(audioService.callLog.whereType<PlayLogEntry>(), hasLength(1));
      expect(events.where((e) => e.name == AnalyticsEventName.soundCardPlayed), hasLength(1));
      expect(events.where((e) => e.name == AnalyticsEventName.soundCardEcho), isEmpty);
    });
  });
}
