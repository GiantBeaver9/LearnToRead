// Pins lib/design/rive_stage.dart (StoryStage contract) and
// lib/design/fake_rive_stage.dart (FakeStoryStage) — accept #8.
// "Every story artboard exposes the same state-machine inputs — idle,
// celebrate, collect — so app code never special-cases a story; a
// FakeStoryStage records input triggers for tests and reports a
// currently-active state."
//
// Neither lib file exists yet: this file fails to compile/analyze until
// both are created, which is the expected red state.
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/rive_stage.dart';

void main() {
  group('StoryStageInput contract — exactly idle/celebrate/collect', () {
    test('POSITIVE: exactly three state-machine inputs, named as pinned', () {
      final names = StoryStageInput.values.map((v) => v.name).toSet();
      expect(StoryStageInput.values.length, equals(3));
      expect(names, equals(<String>{'idle', 'celebrate', 'collect'}));
    });
  });

  group('FakeStoryStage — records triggers, reports active state', () {
    test(
      'POSITIVE: implements the StoryStage contract '
      '(so app code can depend on StoryStage alone, per Unit 8)',
      () {
        final fake = FakeStoryStage();
        expect(fake, isA<StoryStage>());
      },
    );

    test(
      'EDGE: a freshly constructed stage has recorded no triggers and is '
      'idle by default (the stage shows its idle scene before any input, '
      'per PRD Unit 8: present during reading showing the idle state)',
      () {
        final fake = FakeStoryStage();
        expect(fake.triggeredInputs, isEmpty);
        expect(fake.activeState, equals(StoryStageInput.idle));
      },
    );

    test(
      'POSITIVE: triggering celebrate updates the active state to celebrate',
      () {
        final fake = FakeStoryStage();
        fake.trigger(StoryStageInput.celebrate);
        expect(fake.activeState, equals(StoryStageInput.celebrate));
      },
    );

    test(
      'POSITIVE: triggering collect updates the active state to collect and '
      'is recorded in triggeredInputs',
      () {
        final fake = FakeStoryStage();
        fake.trigger(StoryStageInput.collect);
        expect(fake.activeState, equals(StoryStageInput.collect));
        expect(fake.triggeredInputs, contains(StoryStageInput.collect));
      },
    );

    test(
      'POSITIVE: triggeredInputs records every trigger in call order '
      '(a full history, not just the last input)',
      () {
        final fake = FakeStoryStage();
        fake.trigger(StoryStageInput.idle);
        fake.trigger(StoryStageInput.celebrate);
        fake.trigger(StoryStageInput.collect);
        expect(
          fake.triggeredInputs,
          equals(<StoryStageInput>[
            StoryStageInput.idle,
            StoryStageInput.celebrate,
            StoryStageInput.collect,
          ]),
        );
        expect(fake.activeState, equals(StoryStageInput.collect));
      },
    );

    test(
      'NEGATIVE: repeated triggers of the same input are each recorded '
      '(not de-duplicated / collapsed into a Set)',
      () {
        final fake = FakeStoryStage();
        fake.trigger(StoryStageInput.celebrate);
        fake.trigger(StoryStageInput.celebrate);
        expect(fake.triggeredInputs.length, equals(2));
        expect(
          fake.triggeredInputs,
          equals(<StoryStageInput>[StoryStageInput.celebrate, StoryStageInput.celebrate]),
        );
      },
    );

    test(
      'EDGE: two independent FakeStoryStage instances do not share state '
      '(each story/scene owns its own stage — reading screen vs '
      'celebration sequence must not cross-trigger)',
      () {
        final a = FakeStoryStage();
        final b = FakeStoryStage();
        a.trigger(StoryStageInput.celebrate);
        expect(a.activeState, equals(StoryStageInput.celebrate));
        expect(b.activeState, equals(StoryStageInput.idle));
        expect(b.triggeredInputs, isEmpty);
      },
    );
  });
}
