// Pins the API of lib/features/parent/pilot_progress_view.dart (PRD §8
// Unit 10 pinned design: "Pilot progress view: one plain screen per child
// -- stories completed and the words that needed help (from
// WordHelpRecord, with help tier). No charts or trends; exists so pilot
// parents can report concretely."; ticket accept entry 4: "Pilot progress
// view: one plain screen per child listing stories completed and the
// words that needed help with help tier, matching fixture WordHelpRecord
// data exactly (widget test -- transcribed acceptance); no charts or
// trends anywhere.").
//
// lib/features/parent/pilot_progress_view.dart does not exist yet -- this
// suite is EXPECTED to fail to compile until it is written with exactly
// the shape pinned below; that failure IS the red state.
//
// Pinned API surface:
//
//   class PilotProgressView extends StatelessWidget {
//     const PilotProgressView({
//       Key? key,
//       required Profile profile,
//       required List<StoryProgress> storyProgress,      // any status; the
//                                                         // view filters to
//                                                         // StoryStatus.completed
//                                                         // for display
//       required List<WordHelpRecord> wordHelpRecords,   // any encounter/
//                                                         // help state; the
//                                                         // view filters to
//                                                         // helpCount > 0
//                                                         // for the "words
//                                                         // that needed
//                                                         // help" list --
//                                                         // pure-encounter
//                                                         // rows
//                                                         // (helpCount==0)
//                                                         // are recognized
//                                                         // and excluded,
//                                                         // not crashed on
//     });
//   }
//
//   Keys (pinned, test-load-bearing):
//     Key('pilot-progress-view')                 -- root
//     Key('completed-stories-list')              -- always present, even
//                                                    when empty
//     Key('completed-story-<storyId>')           -- one per completed story
//     Key('helped-words-list')                   -- always present, even
//                                                    when empty
//     Key('helped-word-<wordText>')              -- one per word with
//                                                    helpCount > 0
//
//   Pinned tier label text (exact strings a helped-word row must render,
//   alongside the word text itself):
//     HelpLevel.soundOut -> 'Sound-out help'
//     HelpLevel.modeled  -> 'Modeled help'
//   (HelpLevel.none never reaches a helped-word row -- helpCount > 0
//   filtering guarantees this.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/parent/pilot_progress_view.dart';

Profile _profile() => Profile(
  localId: 'p1',
  displayName: 'Ada',
  ageBand: AgeBand.fiveToSix,
  currentLevelId: 'level.1',
  micConsent: false,
  cloudAsrConsent: false,
  createdAt: DateTime(2026, 1, 1),
);

Widget _viewApp({
  required List<StoryProgress> storyProgress,
  required List<WordHelpRecord> wordHelpRecords,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PilotProgressView(
        profile: _profile(),
        storyProgress: storyProgress,
        wordHelpRecords: wordHelpRecords,
      ),
    ),
  );
}

void main() {
  group('PilotProgressView completed stories (positive)', () {
    testWidgets(
      'lists exactly the completed stories from the fixture, excluding '
      'locked/available ones',
      (tester) async {
        final storyProgress = [
          const StoryProgress(
            profileId: 'p1',
            storyId: 'story.1',
            status: StoryStatus.completed,
            timesRead: 1,
          ),
          const StoryProgress(
            profileId: 'p1',
            storyId: 'story.2',
            status: StoryStatus.available,
            timesRead: 0,
          ),
          const StoryProgress(
            profileId: 'p1',
            storyId: 'story.3',
            status: StoryStatus.completed,
            timesRead: 2,
          ),
          const StoryProgress(
            profileId: 'p1',
            storyId: 'story.4',
            status: StoryStatus.locked,
            timesRead: 0,
          ),
        ];

        await tester.pumpWidget(
          _viewApp(storyProgress: storyProgress, wordHelpRecords: const []),
        );

        expect(
          find.byKey(const Key('completed-story-story.1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('completed-story-story.3')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('completed-story-story.2')),
          findsNothing,
          reason: 'available (not yet completed) stories must not list',
        );
        expect(
          find.byKey(const Key('completed-story-story.4')),
          findsNothing,
          reason: 'locked stories must not list',
        );
      },
    );
  });

  group('PilotProgressView helped words (positive: matches fixture exactly)', () {
    testWidgets(
      'lists every word with helpCount > 0, each showing its exact tier '
      'label from lastHelpLevel',
      (tester) async {
        final records = [
          const WordHelpRecord(
            profileId: 'p1',
            wordText: 'cat',
            encounterCount: 3,
            helpCount: 1,
            lastHelpLevel: HelpLevel.soundOut,
          ),
          const WordHelpRecord(
            profileId: 'p1',
            wordText: 'elephant',
            encounterCount: 5,
            helpCount: 3,
            lastHelpLevel: HelpLevel.modeled,
          ),
        ];

        await tester.pumpWidget(
          _viewApp(storyProgress: const [], wordHelpRecords: records),
        );

        final catRow = find.byKey(const Key('helped-word-cat'));
        expect(catRow, findsOneWidget);
        expect(
          find.descendant(of: catRow, matching: find.text('cat')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: catRow, matching: find.text('Sound-out help')),
          findsOneWidget,
        );

        final elephantRow = find.byKey(const Key('helped-word-elephant'));
        expect(elephantRow, findsOneWidget);
        expect(
          find.descendant(of: elephantRow, matching: find.text('elephant')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: elephantRow,
            matching: find.text('Modeled help'),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group(
    'PilotProgressView helped words (edge: encounters-only words handled '
    'correctly)',
    () {
      testWidgets(
        'a word that was only encountered (helpCount == 0) never needed '
        'help and does NOT appear in the helped-words list',
        (tester) async {
          final records = [
            const WordHelpRecord(
              profileId: 'p1',
              wordText: 'dog',
              encounterCount: 4,
              helpCount: 0,
              lastHelpLevel: HelpLevel.none,
            ),
            const WordHelpRecord(
              profileId: 'p1',
              wordText: 'fox',
              encounterCount: 2,
              helpCount: 1,
              lastHelpLevel: HelpLevel.soundOut,
            ),
          ];

          await tester.pumpWidget(
            _viewApp(storyProgress: const [], wordHelpRecords: records),
          );

          expect(
            find.byKey(const Key('helped-word-dog')),
            findsNothing,
            reason:
                'encounters-only words (never needed help) must be '
                'excluded from the helped-words list',
          );
          expect(find.byKey(const Key('helped-word-fox')), findsOneWidget);
        },
      );

      testWidgets(
        'a fixture of only encounters-only words renders an empty (but '
        'present) helped-words list without crashing',
        (tester) async {
          final records = [
            const WordHelpRecord(
              profileId: 'p1',
              wordText: 'dog',
              encounterCount: 4,
              helpCount: 0,
              lastHelpLevel: HelpLevel.none,
            ),
          ];

          await tester.pumpWidget(
            _viewApp(storyProgress: const [], wordHelpRecords: records),
          );

          expect(find.byKey(const Key('helped-words-list')), findsOneWidget);
          expect(find.byKey(const Key('helped-word-dog')), findsNothing);
        },
      );
    },
  );

  group('PilotProgressView (negative: no charts or trends anywhere)', () {
    testWidgets(
      'renders no progress bars, sliders, or chart/trend iconography for '
      'the help data',
      (tester) async {
        final records = [
          const WordHelpRecord(
            profileId: 'p1',
            wordText: 'cat',
            encounterCount: 10,
            helpCount: 4,
            lastHelpLevel: HelpLevel.modeled,
          ),
        ];

        await tester.pumpWidget(
          _viewApp(storyProgress: const [], wordHelpRecords: records),
        );

        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(find.byIcon(Icons.show_chart), findsNothing);
        expect(find.byIcon(Icons.bar_chart), findsNothing);
        expect(find.byIcon(Icons.trending_up), findsNothing);
        expect(find.byIcon(Icons.trending_down), findsNothing);
        expect(find.textContaining('trend', findRichText: true), findsNothing);
      },
    );
  });

  group('PilotProgressView (edge: empty fixtures)', () {
    testWidgets(
      'zero completed stories and zero helped words renders gracefully '
      '(both list containers present, no item rows, no crash)',
      (tester) async {
        await tester.pumpWidget(
          _viewApp(storyProgress: const [], wordHelpRecords: const []),
        );

        expect(find.byKey(const Key('pilot-progress-view')), findsOneWidget);
        expect(
          find.byKey(const Key('completed-stories-list')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('helped-words-list')), findsOneWidget);
      },
    );
  });
}
