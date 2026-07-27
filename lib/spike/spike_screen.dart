// Unit 0 recognition spike — bare-bones UI.
//
// DISPOSABLE spike code (PRD.md §8 Unit 0): "a bare-bones Flutter screen
// with a live microphone, one hardcoded sentence, and raw hypothesis
// logging from the platform on-device recognizer (A-10) with contextual
// biasing enabled." Not architected into the main app; see
// docs/spike/README.md for how the owner runs this on a device.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'hypothesis_log.dart';
import 'spike_channel.dart';

/// The single hardcoded sentence the child reads aloud during the spike.
///
/// Pinned design (PRD §8 Unit 0): the sentence never changes at runtime; it
/// is also the source of the contextual-biasing word list handed to the
/// platform recognizer via [spikeBiasingWordsFor].
const String kSpikeSentence = 'The quick fox runs to the big red barn.';

/// Splits [sentence] into the word list used for platform-recognizer
/// contextual biasing (iOS `SFSpeechRecognizer.contextualStrings`, Android
/// `SpeechRecognizer` biasing extras).
///
/// Collapses repeated whitespace and strips trailing sentence punctuation
/// from each word; a blank/empty sentence yields an empty list.
List<String> spikeBiasingWordsFor(String sentence) {
  final trimmed = sentence.trim();
  if (trimmed.isEmpty) {
    return const <String>[];
  }
  return trimmed
      .split(RegExp(r'\s+'))
      .map((word) => word.replaceAll(RegExp(r'''[.,!?;:'"]+$'''), ''))
      .where((word) => word.isNotEmpty)
      .toList();
}

/// Widget key for the hardcoded-sentence text.
const Key spikeSentenceTextKey = Key('spike-sentence-text');

/// Widget key for the mic start/stop control.
const Key spikeRecordButtonKey = Key('spike-record-button');

/// Widget key for the live scrolling raw-hypothesis view.
const Key spikeHypothesisListKey = Key('spike-hypothesis-list');

/// Bare-bones Unit 0 spike screen: shows [kSpikeSentence], a mic start/stop
/// control, and a live scrolling list of raw hypotheses streamed from the
/// platform recognizer via [SpikeChannel]. Each recording session's
/// hypotheses are also collected into a [SpikeSessionLog] (rotated per
/// start/stop cycle by [SpikeSessionLogRotator]) and best-effort persisted
/// to the app's documents directory as a JSON-lines file the owner can
/// pull off the device — see docs/spike/README.md.
class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  final SpikeChannel _channel = const SpikeChannel();
  final SpikeSessionLogRotator _rotator = SpikeSessionLogRotator();
  final List<HypothesisEvent> _hypotheses = <HypothesisEvent>[];
  StreamSubscription<HypothesisEvent>? _subscription;
  bool _recording = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _subscription = _channel.hypotheses().listen(_onHypothesis, onError: _onStreamError);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onHypothesis(HypothesisEvent event) {
    if (!mounted) return;
    setState(() => _hypotheses.add(event));

    final currentLog = _rotator.current;
    if (currentLog == null) return;
    currentLog.appendEvent(event);
    unawaited(_persistLog(currentLog));
  }

  void _onStreamError(Object error) {
    if (!mounted) return;
    setState(() {
      _errorMessage = error is SpikeChannelException
          ? '${error.code}: ${error.message ?? ''}'
          : error.toString();
    });
  }

  /// Best-effort write of the current session log to the app's documents
  /// directory (see docs/spike/README.md for where it lands). Swallows
  /// failures rather than crashing the spike session: e.g. there is no
  /// path_provider platform implementation under `flutter test`, and a
  /// real-device write can still fail transiently mid-session without
  /// losing the in-memory [SpikeSessionLog] the owner can still inspect.
  Future<void> _persistLog(SpikeSessionLog log) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, log.fileName));
      await file.writeAsString(log.toJsonLines());
    } catch (_) {
      // Best-effort only; see doc comment above.
    }
  }

  Future<void> _toggleRecording() async {
    final wasRecording = _recording;
    setState(() {
      _recording = !wasRecording;
      _errorMessage = null;
    });

    try {
      if (!wasRecording) {
        _rotator.startSession(
          sentence: kSpikeSentence,
          biasingWords: spikeBiasingWordsFor(kSpikeSentence),
        );
        await _channel.start(
          sentence: kSpikeSentence,
          biasingWords: spikeBiasingWordsFor(kSpikeSentence),
        );
      } else {
        await _channel.stop();
      }
    } on SpikeChannelException catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = wasRecording;
        _errorMessage = '${e.code}: ${e.message ?? ''}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLog = _rotator.current;
    return Scaffold(
      appBar: AppBar(title: const Text('ASR spike (Unit 0 — disposable)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kSpikeSentence,
              key: spikeSentenceTextKey,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              key: spikeRecordButtonKey,
              onPressed: _toggleRecording,
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(_recording ? 'Stop' : 'Start'),
            ),
            if (currentLog != null) ...[
              const SizedBox(height: 8),
              Text(
                'Session log: ${currentLog.fileName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            const Text('Raw hypotheses:'),
            Expanded(
              child: ListView.builder(
                key: spikeHypothesisListKey,
                itemCount: _hypotheses.length,
                itemBuilder: (context, index) {
                  final event = _hypotheses[index];
                  final marker = event.isFinal ? '[FINAL]' : '[partial]';
                  return Text('$marker ${event.text}');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
