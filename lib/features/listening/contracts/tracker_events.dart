/// The single tracker event stream contract (Unit 4, Unit 5, Unit 6).
///
/// The listening pipeline emits a single, typed event stream consumed by
/// Units 5–6: wordAccepted, wordAcceptedNearMiss, struggleDetected, silence,
/// and wordHelped (emitted by the scaffold controller, not the engine).
///
/// Engine choice is invisible above this interface; these events abstract
/// over on-device, cloud, and tap-fallback engines.
library;

import 'package:learn_to_read/domain/models/user_models.dart';

/// Base type for the tracker event stream.
abstract class TrackerEvent {
  const TrackerEvent();
}

/// Word read correctly: hypothesis is the target word or near-miss was
/// promoted to accepted (e.g., lookahead back-fill).
///
/// [index]: the word's position in the sentence (0-based).
/// Emitted after the word turns green in the reading screen.
class WordAccepted extends TrackerEvent {
  const WordAccepted({required this.index});

  /// The word's position in the sentence (0-based).
  final int index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordAccepted && other.index == index);

  @override
  int get hashCode => Object.hash(runtimeType, index);

  @override
  String toString() => 'WordAccepted(index: $index)';
}

/// Word accepted as close-enough phonetic match (e.g., "gat" for "cat").
///
/// [index]: the word's position in the sentence (0-based).
///
/// This event triggers the dedicated near-miss prompt path (Unit 6):
/// a brief, warm model of the correct word (pronunciation audio) that the
/// child may echo but is not required to. No Tier 1/2 help escalates from
/// near-miss; reading continues immediately.
class WordAcceptedNearMiss extends TrackerEvent {
  const WordAcceptedNearMiss({required this.index});

  /// The word's position in the sentence (0-based).
  final int index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordAcceptedNearMiss && other.index == index);

  @override
  int get hashCode => Object.hash(runtimeType, index);

  @override
  String toString() => 'WordAcceptedNearMiss(index: $index)';
}

/// Struggle detected: two consecutive failed hypothesis bursts or sustained
/// silence on the current word.
///
/// [index]: the word's position in the sentence (0-based).
/// Triggers Tier 1 stuck-word help (Unit 6 sound-out scaffold).
class StruggleDetected extends TrackerEvent {
  const StruggleDetected({required this.index});

  /// The word's position in the sentence (0-based).
  final int index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StruggleDetected && other.index == index);

  @override
  int get hashCode => Object.hash(runtimeType, index);

  @override
  String toString() => 'StruggleDetected(index: $index)';
}

/// Sustained silence duration exceeded threshold.
///
/// [duration]: the silence period detected.
/// May trigger struggle detection or other timeout logic.
class Silence extends TrackerEvent {
  const Silence({required this.duration});

  /// The duration of the silence period.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Silence && other.duration == duration);

  @override
  int get hashCode => Object.hash(runtimeType, duration);

  @override
  String toString() => 'Silence(duration: $duration)';
}

/// Word received help: Tier 1 sound-out or Tier 2 model.
///
/// [index]: the word's position in the sentence (0-based).
/// [tier]: the help level reached ([HelpLevel.soundOut] or [HelpLevel.modeled]).
///
/// Emitted by the stuck-word scaffold controller (Unit 6), not the engine.
/// The word still turns green (child is never told they were wrong), and the
/// fact is recorded invisibly in [WordHelpRecord] for learning analytics.
class WordHelped extends TrackerEvent {
  const WordHelped({required this.index, required this.tier});

  /// The word's position in the sentence (0-based).
  final int index;

  /// The help level: [HelpLevel.none], [HelpLevel.soundOut] (Tier 1),
  /// or [HelpLevel.modeled] (Tier 2).
  final HelpLevel tier;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordHelped &&
          other.index == index &&
          other.tier == tier);

  @override
  int get hashCode => Object.hash(runtimeType, index, tier);

  @override
  String toString() => 'WordHelped(index: $index, tier: ${tier.name})';
}

/// Extension to support whereType() on TrackerEvent streams.
///
/// Workaround for Dart analyzer compatibility with generic Stream extensions.
extension TrackerEventStreamExtension on Stream<TrackerEvent> {
  /// Filters this stream to only emit elements of type [T].
  Stream<T> whereType<T extends TrackerEvent>() =>
      where((event) => event is T).cast<T>();
}
