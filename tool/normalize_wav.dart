// Loudness-normalizes WAV clips to the Unit 13 pinned -16 LUFS target using
// the app's OWN BS.1770 implementation (lib/pipeline/loudness_check.dart) --
// the same code the pack builder gates with, so a clip this tool passes can
// never fail the build.
//
// Usage:
//   dart run tool/normalize_wav.dart <content-dir> [--target=-16.0]
//
// Walks every .wav under <content-dir>, measures integrated loudness, and
// linearly rescales 16-bit PCM until |measured - target| <= 0.25 LU (max 5
// iterations; clips whose required gain would clip peaks are limited and
// reported). Files already within tolerance are untouched.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:learn_to_read/pipeline/loudness_check.dart';

/// Applies [gain] with tanh soft-clipping: samples that would exceed full
/// scale saturate smoothly instead of hard-clipping (speech tolerates a few
/// dB of soft saturation inaudibly; the measure-adjust loop compensates for
/// the loudness the saturation absorbs).
Uint8List _rescaled(Uint8List wav, double gain) {
  final out = Uint8List.fromList(wav);
  final bytes = ByteData.sublistView(out);
  // Locate the 'data' chunk (44-byte canonical header is not guaranteed).
  var offset = 12;
  while (offset + 8 <= out.length) {
    final id = String.fromCharCodes(out.sublist(offset, offset + 4));
    final size = bytes.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      final start = offset + 8;
      final end = (start + size).clamp(0, out.length);
      for (var i = start; i + 1 < end; i += 2) {
        final sample = bytes.getInt16(i, Endian.little);
        final x = sample * gain / 32767.0;
        final soft = x.abs() <= 0.5 ? x : _softClip(x);
        bytes.setInt16(i, (soft * 32767.0).round().clamp(-32768, 32767), Endian.little);
      }
      return out;
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw FormatException('no data chunk');
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length != 1) {
    print('usage: dart run tool/normalize_wav.dart <content-dir> [--target=-16.0]');
    exitCode = 2;
    return;
  }
  final target = double.tryParse(
        args.firstWhere((a) => a.startsWith('--target='), orElse: () => '')
            .replaceFirst('--target=', ''),
      ) ??
      -16.0;

  var adjusted = 0, ok = 0, limited = 0;
  final files = Directory(positional[0])
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.wav'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    var wav = await file.readAsBytes();
    var result = checkAssetLoudness(wav, assetRef: file.path, targetLufs: target, toleranceLu: 0.25);
    if (result.passes) {
      ok++;
      continue;
    }
    for (var i = 0; i < 8 && !result.passes; i++) {
      wav = _rescaled(wav, _dbToLinear(target - result.measuredLufs));
      result = checkAssetLoudness(wav, assetRef: file.path, targetLufs: target, toleranceLu: 0.25);
    }
    await file.writeAsBytes(wav);
    if (!result.passes) {
      limited++;
      print('STILL OFF ${file.path}: ${result.measuredLufs.toStringAsFixed(2)} LUFS after soft-clip loop');
    } else {
      adjusted++;
    }
  }
  print('normalized: $adjusted adjusted, $ok already in tolerance, $limited peak-limited');
}

double _dbToLinear(double db) => math.pow(10, db / 20).toDouble();

/// Smooth saturation: linear below half scale, tanh-shaped above, C1-
/// continuous at the knee, asymptote at full scale.
double _softClip(double x) {
  final sign = x.isNegative ? -1.0 : 1.0;
  final a = x.abs();
  return sign * (0.5 + 0.5 * _tanh(2.0 * (a - 0.5)));
}

double _tanh(double x) {
  final e2x = math.exp(2 * x);
  return (e2x - 1) / (e2x + 1);
}

double _peakOf(Uint8List wav) {
  final bytes = ByteData.sublistView(wav);
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(offset, offset + 4));
    final size = bytes.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      var peak = 1.0;
      final start = offset + 8;
      final end = (start + size).clamp(0, wav.length);
      for (var i = start; i + 1 < end; i += 2) {
        final v = bytes.getInt16(i, Endian.little).abs().toDouble();
        if (v > peak) peak = v;
      }
      return peak;
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('no data chunk');
}
