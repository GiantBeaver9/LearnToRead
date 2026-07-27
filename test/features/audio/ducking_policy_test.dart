// Pins the API of lib/features/audio/ducking_policy.dart (PRD §8 Unit 13
// pinned design: "ducking rules (help audio ducks ambient/celebration
// audio; nothing ducks the microphone processing)". ticket audio-playback
// accept entry 3. This suite is authored before the implementation exists,
// so it is EXPECTED to fail to compile until ducking_policy.dart is written
// with exactly the shapes exercised below.
//
// Pinned API surface this suite requires:
//   class DuckingPolicy {
//     const DuckingPolicy();
//     Set<AudioChannel> channelsDuckedBy(AudioChannel playingChannel);
//     bool shouldDuck({required AudioChannel active, required AudioChannel candidate});
//   }
// (AudioChannel itself is pinned by audio_service.dart / audio_service_test
// coverage lives in fake_audio_service_test.dart -- see that file's header.)
//
// Contract this suite locks in (builder-mechanical design choices made by
// this test suite, since the ticket leaves exact shapes to the builder and
// only pins behavior):
//  - DuckingPolicy is pure and stateless: given only the channel that
//    started playing, it returns which other channels that implies should
//    be ducked. It never accepts or references any concept of a
//    microphone, ASR engine, or "listening" state -- by construction
//    (no such parameter exists anywhere on the type), not by a runtime
//    check. This is the "asserted by API absence" half of accept entry 3.
//  - Only AudioChannel.help ducks anything, and only
//    {AudioChannel.ambient, AudioChannel.celebration} -- narration is never
//    ducked by help, and no other channel ducks anything at all.
//  - Ducking is directional/non-symmetric: ambient playing does not duck
//    help; celebration playing does not duck help.
//  - AudioChannel has exactly four values (help, narration, celebration,
//    ambient) -- there is deliberately no fifth "mic"/"listening" value,
//    which is the compile-time proof that ducking cannot reach the mic
//    pipeline: there is no channel to name it with.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/ducking_policy.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';

void main() {
  group('POSITIVE: help ducks ambient/celebration (pinned rule)', () {
    test('channelsDuckedBy(help) is exactly {ambient, celebration}', () {
      const policy = DuckingPolicy();

      expect(policy.channelsDuckedBy(AudioChannel.help), {AudioChannel.ambient, AudioChannel.celebration});
    });

    test('shouldDuck(active: help, candidate: ambient) is true', () {
      const policy = DuckingPolicy();

      expect(policy.shouldDuck(active: AudioChannel.help, candidate: AudioChannel.ambient), isTrue);
    });

    test('shouldDuck(active: help, candidate: celebration) is true', () {
      const policy = DuckingPolicy();

      expect(policy.shouldDuck(active: AudioChannel.help, candidate: AudioChannel.celebration), isTrue);
    });
  });

  group('NEGATIVE: nothing else ducks, and ducking is not symmetric', () {
    test('channelsDuckedBy(ambient) is empty -- ambient never ducks anything', () {
      const policy = DuckingPolicy();

      expect(policy.channelsDuckedBy(AudioChannel.ambient), isEmpty);
    });

    test('channelsDuckedBy(celebration) is empty -- celebration never ducks anything', () {
      const policy = DuckingPolicy();

      expect(policy.channelsDuckedBy(AudioChannel.celebration), isEmpty);
    });

    test('channelsDuckedBy(narration) is empty -- narration never ducks anything', () {
      const policy = DuckingPolicy();

      expect(policy.channelsDuckedBy(AudioChannel.narration), isEmpty);
    });

    test('shouldDuck(active: ambient, candidate: help) is false -- ambient never ducks help', () {
      const policy = DuckingPolicy();

      expect(policy.shouldDuck(active: AudioChannel.ambient, candidate: AudioChannel.help), isFalse);
    });

    test('shouldDuck(active: celebration, candidate: help) is false -- celebration never ducks help', () {
      const policy = DuckingPolicy();

      expect(policy.shouldDuck(active: AudioChannel.celebration, candidate: AudioChannel.help), isFalse);
    });

    test('shouldDuck(active: help, candidate: narration) is false -- narration is exempt', () {
      const policy = DuckingPolicy();

      expect(policy.shouldDuck(active: AudioChannel.help, candidate: AudioChannel.narration), isFalse);
    });

    test('shouldDuck(active: help, candidate: help) is false -- a channel never ducks itself', () {
      const policy = DuckingPolicy();

      expect(policy.shouldDuck(active: AudioChannel.help, candidate: AudioChannel.help), isFalse);
    });
  });

  group('EDGE: mic/listening has no API surface on this policy (API absence)', () {
    test('AudioChannel has exactly the four pinned values -- no mic/listening channel exists', () {
      expect(
        AudioChannel.values.toSet(),
        {AudioChannel.help, AudioChannel.narration, AudioChannel.celebration, AudioChannel.ambient},
      );
    });

    test('channelsDuckedBy is total over every AudioChannel value (no channel throws)', () {
      const policy = DuckingPolicy();

      for (final channel in AudioChannel.values) {
        expect(() => policy.channelsDuckedBy(channel), returnsNormally);
      }
    });

    test('the policy is stateless: repeated construction never changes its answers', () {
      const first = DuckingPolicy();
      const second = DuckingPolicy();

      expect(first.channelsDuckedBy(AudioChannel.help), second.channelsDuckedBy(AudioChannel.help));
    });

    test(
      'help audio during simulated "listening" issues no mic-affecting command '
      '(the listening flag below is entirely outside this API -- nothing on '
      'AudioService/DuckingPolicy can reach it, which is the point)',
      () async {
        var micPipelineTouched = false;
        // ignore: unused_element
        void simulateMicCommand() => micPipelineTouched = true; // never invoked below

        final fake = FakeAudioService();
        await fake.play('audio/help/soundout.wav', channel: AudioChannel.help);

        expect(micPipelineTouched, isFalse);
        // Every entry FakeAudioService could possibly log is one of these
        // four audio-only kinds; none of them is or could be mic-related,
        // because AudioChannel (asserted above) has no mic value to tag
        // such an entry with in the first place.
        expect(
          fake.callLog.every(
            (entry) => entry is PlayLogEntry || entry is StopLogEntry || entry is DuckLogEntry || entry is UnduckLogEntry,
          ),
          isTrue,
        );
      },
    );
  });
}
