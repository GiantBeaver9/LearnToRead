// Pins the API of lib/pipeline/loudness_check.dart (PRD §8 Unit 3 pinned
// design + Unit 13 pinned: "all audio normalized to -16 LUFS integrated,
// checked in pack build"; §9 A-15 n/a here, loudness is unrelated to
// checksum integrity; ticket pack-build-cli accept entry 6: "the check
// implements integrated loudness per ITU-R BS.1770 over WAV input"). This
// suite is authored before the implementation exists, so it is EXPECTED to
// fail to compile until loudness_check.dart is written with exactly the
// shapes exercised below.
//
// Pinned API surface this suite requires:
//
//   /// BS.1770-style K-weighted integrated loudness (LUFS) of 16-bit PCM
//   /// WAV audio (mono or stereo). Throws ArgumentError on a non-PCM /
//   /// unrecognized WAV payload.
//   double measureIntegratedLoudnessLufs(Uint8List wavBytes);
//
//   /// Returns a new WAV (same sample rate / channel count / bit depth)
//   /// whose measured integrated loudness is `targetLufs`, achieved via a
//   /// single constant linear gain applied to every sample.
//   Uint8List normalizeToTargetLoudness(Uint8List wavBytes, {double targetLufs = -16.0});
//
//   class LoudnessCheckResult {
//     final String assetRef;
//     final double measuredLufs;
//     final bool passes; // true iff (measuredLufs - targetLufs).abs() <= toleranceLu
//   }
//   LoudnessCheckResult checkAssetLoudness(
//     Uint8List wavBytes, {
//     required String assetRef,
//     double targetLufs = -16.0,
//     double toleranceLu = 1.0,
//   });
//
// Contract this suite locks in (builder-mechanical -- the ticket pins the
// -16 LUFS *target* and the BS.1770 measurement basis, but not an exact
// tolerance number or exact-float expected measurements, since real
// K-weighting/gating math is implementation detail; this suite therefore
// pins RANGES and RELATIVE properties, never exact floats):
//  - A louder fixture (higher sine amplitude, same frequency/duration)
//    measures a HIGHER (less negative) LUFS value than a quieter one.
//  - Doubling a sine's linear amplitude (a fixed, frequency-independent
//    +6.02 dB change in signal power) changes measured LUFS by
//    approximately +6.02 dB -- pinned here as a [+5.0, +7.0] LU band, not an
//    exact float, since exact K-weighting coefficients are implementation
//    detail.
//  - normalizeToTargetLoudness's output, re-measured, lands within ±0.5 LU
//    of the requested target (the ticket's own pinned example tolerance for
//    the normalization round-trip).
//  - checkAssetLoudness with an explicit toleranceLu passes iff the measured
//    value is within that many LU of targetLufs; this suite only asserts
//    pass/fail for fixtures placed far outside any plausible tolerance
//    (>= 10 LU off target) to avoid coupling to an unpinned default
//    tolerance value.
//  - measureIntegratedLoudnessLufs does not throw on digital silence (all-
//    zero samples); the exact floor value it returns for that case is
//    unpinned (BS.1770's relative/absolute gating leaves this
//    implementation-defined), so this suite only asserts the result is a
//    very low finite number, not a specific one.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/pipeline/loudness_check.dart';

// ---------------------------------------------------------------------------
// WAV fixture generation (programmatic PCM16 sine waves, per ticket note:
// "audio fixtures are programmatically generated PCM WAVs").
// ---------------------------------------------------------------------------

Uint8List _pcm16Wav(Int16List interleavedSamples, {required int numChannels, int sampleRate = 44100}) {
  const bitsPerSample = 16;
  final dataLength = interleavedSamples.length * 2;
  final builder = BytesBuilder();

  void writeString(String s) => builder.add(ascii.encode(s));
  void writeU32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    builder.add(b.buffer.asUint8List());
  }

  void writeU16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    builder.add(b.buffer.asUint8List());
  }

  writeString('RIFF');
  writeU32(36 + dataLength);
  writeString('WAVE');
  writeString('fmt ');
  writeU32(16);
  writeU16(1); // PCM
  writeU16(numChannels);
  writeU32(sampleRate);
  writeU32(sampleRate * numChannels * bitsPerSample ~/ 8);
  writeU16(numChannels * bitsPerSample ~/ 8);
  writeU16(bitsPerSample);
  writeString('data');
  writeU32(dataLength);

  final sampleBytes = ByteData(dataLength);
  for (var i = 0; i < interleavedSamples.length; i++) {
    sampleBytes.setInt16(i * 2, interleavedSamples[i], Endian.little);
  }
  builder.add(sampleBytes.buffer.asUint8List());
  return builder.toBytes();
}

/// A mono sine wave at [amplitude] (fraction of full scale, 0.0-1.0),
/// [frequencyHz] (997 Hz default: close to unity gain in BS.1770 K-weighting,
/// avoiding the high-shelf's low/high extremes so amplitude changes map
/// predictably onto loudness changes), for [durationSeconds] -- long enough
/// to span several BS.1770 400ms gating blocks so the integrated measurement
/// stabilizes.
Uint8List _sineWavBytes({
  required double amplitude,
  double frequencyHz = 997,
  double durationSeconds = 2.0,
  int sampleRate = 44100,
}) {
  final n = (sampleRate * durationSeconds).round();
  final samples = Int16List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v = amplitude * math.sin(2 * math.pi * frequencyHz * t);
    samples[i] = (v * 32767).round().clamp(-32768, 32767);
  }
  return _pcm16Wav(samples, numChannels: 1, sampleRate: sampleRate);
}

Uint8List _stereoSineWavBytes({
  required double amplitude,
  double frequencyHz = 997,
  double durationSeconds = 2.0,
  int sampleRate = 44100,
}) {
  final n = (sampleRate * durationSeconds).round();
  final samples = Int16List(n * 2);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v = amplitude * math.sin(2 * math.pi * frequencyHz * t);
    final s = (v * 32767).round().clamp(-32768, 32767);
    samples[i * 2] = s;
    samples[i * 2 + 1] = s;
  }
  return _pcm16Wav(samples, numChannels: 2, sampleRate: sampleRate);
}

Uint8List _silenceWavBytes({double durationSeconds = 1.0, int sampleRate = 44100}) {
  final n = (sampleRate * durationSeconds).round();
  return _pcm16Wav(Int16List(n), numChannels: 1, sampleRate: sampleRate);
}

void main() {
  group('measureIntegratedLoudnessLufs (positive: monotonicity)', () {
    test('a louder sine measures a higher (less negative) LUFS than a quieter one', () {
      final quiet = measureIntegratedLoudnessLufs(_sineWavBytes(amplitude: 0.05));
      final loud = measureIntegratedLoudnessLufs(_sineWavBytes(amplitude: 0.5));
      expect(loud, greaterThan(quiet));
    });

    test('a near-silent sine measures well below a near-full-scale sine', () {
      final quiet = measureIntegratedLoudnessLufs(_sineWavBytes(amplitude: 0.01));
      final loud = measureIntegratedLoudnessLufs(_sineWavBytes(amplitude: 0.9));
      expect(loud - quiet, greaterThan(20));
    });
  });

  group('measureIntegratedLoudnessLufs (positive: amplitude-doubling ~ +6 LU)', () {
    test('doubling linear amplitude increases measured LUFS by roughly 6.02 dB', () {
      final base = measureIntegratedLoudnessLufs(_sineWavBytes(amplitude: 0.2));
      final doubled = measureIntegratedLoudnessLufs(_sineWavBytes(amplitude: 0.4));
      final delta = doubled - base;
      expect(delta, inInclusiveRange(5.0, 7.0));
    });
  });

  group('normalizeToTargetLoudness (positive, accept 6: round-trips within ±0.5 LU)', () {
    test('a quiet source normalized to -16 LUFS re-measures within ±0.5 LU of -16', () {
      final normalized = normalizeToTargetLoudness(_sineWavBytes(amplitude: 0.02), targetLufs: -16.0);
      final measured = measureIntegratedLoudnessLufs(normalized);
      expect(measured, inInclusiveRange(-16.5, -15.5));
    });

    test('a loud-but-below-full-scale source normalized to -16 LUFS re-measures within ±0.5 LU of -16', () {
      final normalized = normalizeToTargetLoudness(_sineWavBytes(amplitude: 0.6), targetLufs: -16.0);
      final measured = measureIntegratedLoudnessLufs(normalized);
      expect(measured, inInclusiveRange(-16.5, -15.5));
    });

    test('normalizing to a different target (-20 LUFS) round-trips within ±0.5 LU of that target', () {
      final normalized = normalizeToTargetLoudness(_sineWavBytes(amplitude: 0.3), targetLufs: -20.0);
      final measured = measureIntegratedLoudnessLufs(normalized);
      expect(measured, inInclusiveRange(-20.5, -19.5));
    });
  });

  group('checkAssetLoudness (positive, accept 6)', () {
    test('a sine normalized to -16 LUFS passes the check', () {
      final normalized = normalizeToTargetLoudness(_sineWavBytes(amplitude: 0.3), targetLufs: -16.0);
      final result = checkAssetLoudness(normalized, assetRef: 'audio/words/cat.wav', targetLufs: -16.0, toleranceLu: 1.0);
      expect(result.passes, isTrue);
      expect(result.assetRef, 'audio/words/cat.wav');
      expect(result.measuredLufs, inInclusiveRange(-17.0, -15.0));
    });
  });

  group('checkAssetLoudness (negative, accept 6: too quiet / too loud fail)', () {
    test('a very quiet sine (>=10 LU below target) fails the check', () {
      final tooQuiet = _sineWavBytes(amplitude: 0.005);
      final result = checkAssetLoudness(tooQuiet, assetRef: 'audio/words/quiet.wav', targetLufs: -16.0, toleranceLu: 1.0);
      expect(result.measuredLufs, lessThan(-26.0));
      expect(result.passes, isFalse);
    });

    test('a near-full-scale (loud) sine fails the check', () {
      final tooLoud = _sineWavBytes(amplitude: 0.98);
      final result = checkAssetLoudness(tooLoud, assetRef: 'audio/words/loud.wav', targetLufs: -16.0, toleranceLu: 1.0);
      // A near-full-scale sine's true-peak loudness is well above -16 LUFS
      // regardless of exact K-weighting coefficients (bounded above -10).
      expect(result.measuredLufs, greaterThan(-10.0));
      expect(result.passes, isFalse);
    });
  });

  group('WAV format coverage (edge: stereo input)', () {
    test('measureIntegratedLoudnessLufs accepts stereo WAV input without throwing', () {
      expect(() => measureIntegratedLoudnessLufs(_stereoSineWavBytes(amplitude: 0.3)), returnsNormally);
    });

    test('a dual-identical-channel stereo sine measures close to its mono equivalent', () {
      final mono = measureIntegratedLoudnessLufs(_sineWavBytes(amplitude: 0.3));
      final stereo = measureIntegratedLoudnessLufs(_stereoSineWavBytes(amplitude: 0.3));
      expect((stereo - mono).abs(), lessThan(1.0));
    });
  });

  group('measureIntegratedLoudnessLufs (edge: digital silence does not throw)', () {
    test('an all-zero-sample WAV measures a very low but finite value', () {
      final measured = measureIntegratedLoudnessLufs(_silenceWavBytes());
      expect(measured.isFinite, isTrue);
      expect(measured, lessThan(-40.0));
    });
  });
}
