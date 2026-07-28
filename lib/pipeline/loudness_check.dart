/// Loudness measurement and normalization (PRD §8 Unit 3 pinned design +
/// Unit 13 pinned: "all audio normalized to -16 LUFS integrated, checked in
/// pack build"; ticket pack-build-cli accept entry 6: "the check implements
/// integrated loudness per ITU-R BS.1770 over WAV input").
///
/// Pure Dart, no I/O and no plugins: bytes in, numbers out, so the whole
/// measurement runs headlessly in `flutter test` and in the pack-build CLI
/// against programmatically generated fixture WAVs.
///
/// ## What is implemented
///
/// The real BS.1770 chain, not a lookup:
///
///  1. **K-weighting** — two cascaded biquads applied per channel, designed
///     analytically at the file's own sample rate (the ITU tables are quoted
///     at 48 kHz only; the analog prototype below reproduces them exactly at
///     48 kHz and generalizes to 44.1 kHz and friends):
///     - a "pre-filter" high shelf (+3.9998 dB, Q 0.70718, fc 1681.97 Hz)
///       modelling the acoustic effect of the head;
///     - an RLB high-pass (Q 0.50033, fc 38.135 Hz) rolling off content below
///       the range that contributes to perceived loudness.
///  2. **Gated block loudness** — mean square over 400 ms blocks overlapped
///     75 % (100 ms hop), each block's loudness
///     `l_j = -0.691 + 10·log10(power_j)`.
///  3. **Two-stage gating** — an absolute gate at -70 LKFS, then a relative
///     gate 10 LU below the mean loudness of the absolutely-gated blocks.
///  4. **Integrated loudness** — `-0.691 + 10·log10(mean of gated block
///     powers)`.
///
/// ## Two deliberate deviations from BS.1770-4, both recorded
///
///  - **Channel combination.** BS.1770 *sums* per-channel weighted mean
///    squares (`G_i = 1.0` for L/R), so a dual-mono stereo file measures
///    +3.01 LU louder than the same signal as mono. This pipeline's assets
///    are voice recordings that may arrive as either mono or dual-mono
///    stereo from the same session, and the pack build must not judge two
///    encodings of one recording differently — so channel powers are
///    *averaged* rather than summed, making the mono and dual-mono
///    measurements of a recording identical. (Pinned by
///    `loudness_check_test.dart`: "a dual-identical-channel stereo sine
///    measures close to its mono equivalent".)
///  - **Silence floor.** BS.1770 leaves the value of a wholly-gated-out
///    signal undefined (`log10(0)`). Digital silence here returns
///    [kSilenceFloorLufs] rather than negative infinity, so a silent asset
///    reports as a finite, far-below-target number that fails the check
///    normally instead of poisoning arithmetic downstream.
///
/// Input format: linear PCM WAV, 16 bits per sample, any sample rate, any
/// channel count. Anything else throws [ArgumentError] — the pack build
/// surfaces that as a loudness-stage error naming the asset rather than
/// silently passing an unmeasurable file.
library;

import 'dart:math' as math;
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Pinned BS.1770 constants.
// ---------------------------------------------------------------------------

/// BS.1770 block duration for the integrated measurement (400 ms).
const double kLoudnessBlockSeconds = 0.4;

/// BS.1770 block overlap (75 %), i.e. a 100 ms hop between block starts.
const double kLoudnessBlockOverlap = 0.75;

/// BS.1770 absolute gate: blocks quieter than this never contribute.
const double kAbsoluteGateLkfs = -70.0;

/// BS.1770 relative gate offset below the absolutely-gated mean loudness.
const double kRelativeGateLu = -10.0;

/// The `-0.691` offset in `L = -0.691 + 10·log10(Σ G_i · z_i)` (BS.1770-4).
const double kLoudnessOffsetDb = -0.691;

/// Reported for audio in which every block falls below the absolute gate
/// (digital silence). Finite by design — see the library doc comment.
const double kSilenceFloorLufs = -70.0;

// ---------------------------------------------------------------------------
// WAV decoding.
// ---------------------------------------------------------------------------

/// Decoded 16-bit PCM WAV payload: deinterleaved channels of samples
/// normalized to the [-1.0, 1.0) range, plus the format fields needed to
/// re-encode an equivalent file.
class _PcmAudio {
  _PcmAudio({
    required this.sampleRate,
    required this.channels,
    required this.frameCount,
  });

  final int sampleRate;
  final List<Float64List> channels;
  final int frameCount;

  int get channelCount => channels.length;
}

int _u16(ByteData d, int offset) => d.getUint16(offset, Endian.little);
int _u32(ByteData d, int offset) => d.getUint32(offset, Endian.little);

String _ascii(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes.sublist(offset, offset + 4));

/// WAVE format tag for linear PCM.
const int _wavFormatPcm = 1;

/// WAVE_FORMAT_EXTENSIBLE — accepted when its container is 16-bit integer
/// PCM, which is how some recorders emit otherwise-ordinary mono/stereo WAVs.
const int _wavFormatExtensible = 0xFFFE;

_PcmAudio _decodeWav(Uint8List bytes) {
  if (bytes.length < 44) {
    throw ArgumentError.value(
      bytes.length,
      'wavBytes',
      'too short to be a WAV file (need at least a 44-byte header)',
    );
  }
  final data = ByteData.sublistView(bytes);
  if (_ascii(bytes, 0) != 'RIFF' || _ascii(bytes, 8) != 'WAVE') {
    throw ArgumentError.value(
      '${_ascii(bytes, 0)}/${_ascii(bytes, 8)}',
      'wavBytes',
      'not a RIFF/WAVE file',
    );
  }

  int? formatTag;
  int? numChannels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLength;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = _ascii(bytes, offset);
    final chunkSize = _u32(data, offset + 4);
    final bodyOffset = offset + 8;
    if (chunkId == 'fmt ') {
      if (bodyOffset + 16 > bytes.length) {
        throw ArgumentError.value(chunkSize, 'wavBytes', 'truncated fmt chunk');
      }
      formatTag = _u16(data, bodyOffset);
      numChannels = _u16(data, bodyOffset + 2);
      sampleRate = _u32(data, bodyOffset + 4);
      bitsPerSample = _u16(data, bodyOffset + 14);
    } else if (chunkId == 'data') {
      dataOffset = bodyOffset;
      // A truncated final chunk is tolerated: clamp to what is actually
      // there rather than reading past the buffer.
      dataLength = math.min(chunkSize, bytes.length - bodyOffset);
    }
    // Chunks are word-aligned: an odd-sized chunk is followed by a pad byte.
    offset = bodyOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (formatTag == null || numChannels == null || sampleRate == null || bitsPerSample == null) {
    throw ArgumentError.value(null, 'wavBytes', 'WAV is missing its fmt chunk');
  }
  if (dataOffset == null || dataLength == null) {
    throw ArgumentError.value(null, 'wavBytes', 'WAV is missing its data chunk');
  }
  if (formatTag != _wavFormatPcm && formatTag != _wavFormatExtensible) {
    throw ArgumentError.value(
      formatTag,
      'wavBytes',
      'unsupported WAV format tag (only linear PCM is supported)',
    );
  }
  if (bitsPerSample != 16) {
    throw ArgumentError.value(
      bitsPerSample,
      'wavBytes',
      'unsupported bit depth (only 16-bit PCM is supported)',
    );
  }
  if (numChannels < 1) {
    throw ArgumentError.value(numChannels, 'wavBytes', 'WAV declares no channels');
  }
  if (sampleRate < 1) {
    throw ArgumentError.value(sampleRate, 'wavBytes', 'WAV declares a non-positive sample rate');
  }

  final frameCount = dataLength ~/ (2 * numChannels);
  final channels = List<Float64List>.generate(
    numChannels,
    (_) => Float64List(frameCount),
    growable: false,
  );
  for (var frame = 0; frame < frameCount; frame++) {
    final base = dataOffset + frame * 2 * numChannels;
    for (var ch = 0; ch < numChannels; ch++) {
      channels[ch][frame] = data.getInt16(base + ch * 2, Endian.little) / 32768.0;
    }
  }

  return _PcmAudio(sampleRate: sampleRate, channels: channels, frameCount: frameCount);
}

/// Re-encodes deinterleaved float channels as a canonical 44-byte-header
/// 16-bit PCM WAV, preserving [sampleRate] and the channel count.
Uint8List _encodeWav(List<Float64List> channels, int sampleRate) {
  final numChannels = channels.length;
  final frameCount = numChannels == 0 ? 0 : channels.first.length;
  final dataLength = frameCount * numChannels * 2;
  final out = Uint8List(44 + dataLength);
  final view = ByteData.sublistView(out);

  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out[offset + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, _wavFormatPcm, Endian.little);
  view.setUint16(22, numChannels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * numChannels * 2, Endian.little);
  view.setUint16(32, numChannels * 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, dataLength, Endian.little);

  for (var frame = 0; frame < frameCount; frame++) {
    for (var ch = 0; ch < numChannels; ch++) {
      final scaled = (channels[ch][frame] * 32768.0).round().clamp(-32768, 32767);
      view.setInt16(44 + (frame * numChannels + ch) * 2, scaled, Endian.little);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// K-weighting biquads.
// ---------------------------------------------------------------------------

/// A direct-form-I biquad: `y[n] = b0·x[n] + b1·x[n-1] + b2·x[n-2]
/// - a1·y[n-1] - a2·y[n-2]` (coefficients already normalized by a0).
class _Biquad {
  const _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  /// Filters [samples] in place.
  void applyInPlace(Float64List samples) {
    var x1 = 0.0;
    var x2 = 0.0;
    var y1 = 0.0;
    var y2 = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final x0 = samples[i];
      final y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1;
      x1 = x0;
      y2 = y1;
      y1 = y0;
      samples[i] = y0;
    }
  }
}

// BS.1770-4 K-weighting analog prototype parameters. Substituted into the
// bilinear-transform designs below they reproduce the standard's tabulated
// 48 kHz coefficients to ~7 significant figures, and generalize to any other
// sample rate (fixtures here are 44.1 kHz).
const double _shelfGainDb = 3.999843853973347;
const double _shelfQ = 0.7071752369554196;
const double _shelfFcHz = 1681.974450955533;
const double _highPassQ = 0.5003270373238773;
const double _highPassFcHz = 38.13547087602444;

/// Stage 1 of K-weighting: the +4 dB high shelf above ~1.5 kHz.
_Biquad _designShelf(int sampleRate) {
  final k = math.tan(math.pi * _shelfFcHz / sampleRate);
  final vh = math.pow(10.0, _shelfGainDb / 20.0).toDouble();
  final vb = math.pow(vh, 0.4996667741545416).toDouble();
  final kk = k * k;
  final kq = k / _shelfQ;
  final norm = 1.0 / (1.0 + kq + kk);
  return _Biquad(
    (vh + vb * kq + kk) * norm,
    2.0 * (kk - vh) * norm,
    (vh - vb * kq + kk) * norm,
    2.0 * (kk - 1.0) * norm,
    (1.0 - kq + kk) * norm,
  );
}

/// Stage 2 of K-weighting: the RLB high-pass at ~38 Hz.
_Biquad _designHighPass(int sampleRate) {
  final k = math.tan(math.pi * _highPassFcHz / sampleRate);
  final kk = k * k;
  final kq = k / _highPassQ;
  final norm = 1.0 / (1.0 + kq + kk);
  return _Biquad(
    1.0,
    -2.0,
    1.0,
    2.0 * (kk - 1.0) * norm,
    (1.0 - kq + kk) * norm,
  );
}

/// Applies the two-stage K-weighting filter to a copy of [samples].
Float64List _kWeight(Float64List samples, int sampleRate) {
  final filtered = Float64List.fromList(samples);
  _designShelf(sampleRate).applyInPlace(filtered);
  _designHighPass(sampleRate).applyInPlace(filtered);
  return filtered;
}

// ---------------------------------------------------------------------------
// Integrated loudness.
// ---------------------------------------------------------------------------

double _loudnessOfPower(double power) =>
    kLoudnessOffsetDb + 10.0 * (math.log(power) / math.ln10);

/// The mean of the K-weighted, channel-averaged power of each 400 ms block,
/// in source order. Returns an empty list for empty audio.
List<double> _blockPowers(_PcmAudio audio) {
  if (audio.frameCount == 0 || audio.channelCount == 0) return const [];

  final weighted = [
    for (final channel in audio.channels) _kWeight(channel, audio.sampleRate),
  ];

  var blockFrames = (audio.sampleRate * kLoudnessBlockSeconds).round();
  var hopFrames = (blockFrames * (1.0 - kLoudnessBlockOverlap)).round();
  if (hopFrames < 1) hopFrames = 1;
  // Audio shorter than one full block (a clipped word pronunciation, say) is
  // measured as a single short block rather than reported as silence.
  if (audio.frameCount < blockFrames) blockFrames = audio.frameCount;

  final powers = <double>[];
  for (var start = 0; start + blockFrames <= audio.frameCount; start += hopFrames) {
    var total = 0.0;
    for (final channel in weighted) {
      var sumSquares = 0.0;
      for (var i = start; i < start + blockFrames; i++) {
        final v = channel[i];
        sumSquares += v * v;
      }
      total += sumSquares / blockFrames;
    }
    // Channel-averaged, not channel-summed — see the library doc comment.
    powers.add(total / audio.channelCount);
  }
  return powers;
}

double _mean(Iterable<double> values, int count) {
  if (count == 0) return 0.0;
  var total = 0.0;
  for (final v in values) {
    total += v;
  }
  return total / count;
}

double _integratedLoudness(_PcmAudio audio) {
  final powers = _blockPowers(audio);
  if (powers.isEmpty) return kSilenceFloorLufs;

  // Absolute gate.
  final absolutelyGated = <double>[];
  for (final power in powers) {
    if (power > 0 && _loudnessOfPower(power) > kAbsoluteGateLkfs) {
      absolutelyGated.add(power);
    }
  }
  if (absolutelyGated.isEmpty) return kSilenceFloorLufs;

  // Relative gate, computed from the absolutely-gated mean.
  final relativeThreshold =
      _loudnessOfPower(_mean(absolutelyGated, absolutelyGated.length)) + kRelativeGateLu;
  final gated = <double>[
    for (final power in absolutelyGated)
      if (_loudnessOfPower(power) > relativeThreshold) power,
  ];
  if (gated.isEmpty) return kSilenceFloorLufs;

  return _loudnessOfPower(_mean(gated, gated.length));
}

/// BS.1770-style K-weighted integrated loudness, in LUFS, of 16-bit PCM WAV
/// audio (mono or multi-channel).
///
/// Throws [ArgumentError] when [wavBytes] is not a readable 16-bit linear-PCM
/// WAV payload. Digital silence does not throw: it returns
/// [kSilenceFloorLufs].
double measureIntegratedLoudnessLufs(Uint8List wavBytes) =>
    _integratedLoudness(_decodeWav(wavBytes));

/// Returns a new WAV — same sample rate, channel count and bit depth as
/// [wavBytes] — whose measured integrated loudness is [targetLufs], achieved
/// by applying one constant linear gain to every sample.
///
/// Because integrated loudness is a power measurement, the required gain is
/// exactly `10^((target - measured)/20)`; the round trip
/// (`measureIntegratedLoudnessLufs(normalizeToTargetLoudness(x))`) lands well
/// inside ±0.5 LU of the target, the residual being 16-bit requantization
/// noise. Audio whose measurement is wholly gated out (digital silence) has
/// no meaningful gain to apply and is returned unchanged.
Uint8List normalizeToTargetLoudness(Uint8List wavBytes, {double targetLufs = -16.0}) {
  final audio = _decodeWav(wavBytes);
  final measured = _integratedLoudness(audio);
  if (measured <= kSilenceFloorLufs) return Uint8List.fromList(wavBytes);

  final gain = math.pow(10.0, (targetLufs - measured) / 20.0).toDouble();
  final gained = [
    for (final channel in audio.channels)
      Float64List.fromList([
        for (final sample in channel) sample * gain,
      ]),
  ];
  return _encodeWav(gained, audio.sampleRate);
}

/// One asset's loudness verdict (PRD Unit 13: every shipped audio asset must
/// measure the pipeline's target integrated loudness).
class LoudnessCheckResult {
  const LoudnessCheckResult({
    required this.assetRef,
    required this.measuredLufs,
    required this.passes,
  });

  /// The manifest ref of the measured asset, echoed so a failing result can
  /// name the offending file without the caller re-threading it.
  final String assetRef;

  /// The measured BS.1770 integrated loudness, in LUFS.
  final double measuredLufs;

  /// True iff `(measuredLufs - targetLufs).abs() <= toleranceLu`.
  final bool passes;

  @override
  String toString() => 'LoudnessCheckResult(assetRef: $assetRef, '
      'measuredLufs: ${measuredLufs.toStringAsFixed(2)}, passes: $passes)';
}

/// Measures [wavBytes] and reports whether it lands within [toleranceLu] of
/// [targetLufs] (Unit 13 pinned target: -16 LUFS integrated).
///
/// Throws [ArgumentError] on an unreadable WAV payload, same as
/// [measureIntegratedLoudnessLufs].
LoudnessCheckResult checkAssetLoudness(
  Uint8List wavBytes, {
  required String assetRef,
  double targetLufs = -16.0,
  double toleranceLu = 1.0,
}) {
  final measured = measureIntegratedLoudnessLufs(wavBytes);
  return LoudnessCheckResult(
    assetRef: assetRef,
    measuredLufs: measured,
    passes: (measured - targetLufs).abs() <= toleranceLu,
  );
}
