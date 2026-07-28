/// The seam that wires the real vocab card into a real `ReadingScreen`
/// (PRD §8 Unit 7; ticket vocab-cards accept entries 4, 5).
///
/// `ReadingScreen` (lib/features/reading/reading_screen.dart, frozen) only
/// ever sees `ReadingScreen.vocabCardOpener`'s
/// `Future<void> Function(String vocabCardId)` shape (`VocabCardOpener`,
/// defined there) -- it has no idea a real popover, real audio, or real
/// analytics exist behind it. [VocabCardHost] is the concrete
/// implementation of that seam this ticket owns: it wraps the reading
/// screen (or any child) in a `Stack`, and [VocabCardHostState.open] is
/// bound to `vocabCardOpener` via a `GlobalKey`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:learn_to_read/domain/models/content_models.dart' show VocabCard;
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/vocab/vocab_card.dart';

/// Wraps [child] (typically `ReadingScreen`) with the real vocab-card
/// overlay seam.
///
/// [cardsById] resolves a `WordToken.vocabCardId` to its authored
/// [VocabCard]; [pronunciationAudioRefsById] resolves the same id to the
/// originating word's own `WordToken.pronunciationAudioRef` -- plumbed in
/// separately because [VocabCard] itself carries no pronunciation ref, only
/// `VocabCard.definitionAudioRef`. [installId], [profileOrdinal],
/// [levelOrdinal] and the optional [storyId] are the §5 analytics base
/// fields stamped on every `vocab_card_opened` event this host records.
class VocabCardHost extends StatefulWidget {
  const VocabCardHost({
    super.key,
    required this.cardsById,
    this.pronunciationAudioRefsById = const <String, String>{},
    required this.audioService,
    required this.analytics,
    required this.installId,
    required this.profileOrdinal,
    required this.levelOrdinal,
    this.storyId,
    required this.child,
  });

  /// Every vocab card this host can open, keyed by `VocabCard.id`.
  final Map<String, VocabCard> cardsById;

  /// The originating word's pronunciation ref, keyed by the same
  /// `vocabCardId`.
  final Map<String, String> pronunciationAudioRefsById;

  /// Where every card's audio (definition autoplay/replay, word
  /// pronunciation) plays.
  final AudioService audioService;

  /// Where `vocab_card_opened` is recorded.
  final AnalyticsClient analytics;

  /// The random per-install UUID (§5 base field).
  final String installId;

  /// Which on-device profile is reading (ordinal 1-4).
  final int profileOrdinal;

  /// The profile's current level ordinal.
  final int levelOrdinal;

  /// The story currently being read, when there is one. Omitted from the
  /// payload entirely when null (§5: `vocab_card_opened`'s `storyId` is
  /// optional).
  final String? storyId;

  /// The widget this host overlays a vocab card on top of.
  final Widget child;

  @override
  State<VocabCardHost> createState() => VocabCardHostState();
}

class VocabCardHostState extends State<VocabCardHost> {
  VocabCard? _openCard;
  String? _openPronunciationAudioRef;
  Completer<void>? _closeCompleter;

  /// Opens the card for [vocabCardId], logs `vocab_card_opened`, and
  /// returns a future that completes only when the card closes (tap-outside
  /// or the close affordance) -- never when its audio finishes.
  ///
  /// An unresolvable [vocabCardId] (not in [VocabCardHost.cardsById]) is a
  /// content-integrity no-op: nothing is shown, nothing is logged, and the
  /// returned future completes immediately -- a corrupt pack must never
  /// strand a paused child waiting on a card that can never open.
  Future<void> open(String vocabCardId) {
    final card = widget.cardsById[vocabCardId];
    if (card == null) {
      return Future<void>.value();
    }

    // Fire-and-forget, exactly like `ReadingController._track` -- analytics
    // is background I/O and must never make card-opening wait on a file
    // write. Handed to `Zone.root` for the same reason: it must drain on
    // the real event loop independent of whatever zone this call happens
    // to run in.
    Zone.root.run(
      () => unawaited(
        widget.analytics.track(
          AnalyticsEvent(
            name: AnalyticsEventName.vocabCardOpened,
            timestamp: systemClock(),
            installId: widget.installId,
            profileOrdinal: widget.profileOrdinal,
            levelOrdinal: widget.levelOrdinal,
            storyId: widget.storyId,
          ),
        ),
      ),
    );

    final completer = Completer<void>();
    _closeCompleter = completer;
    setState(() {
      _openCard = card;
      _openPronunciationAudioRef =
          widget.pronunciationAudioRefsById[vocabCardId];
    });
    return completer.future;
  }

  void _handleClosed() {
    setState(() {
      _openCard = null;
      _openPronunciationAudioRef = null;
    });
    final completer = _closeCompleter;
    _closeCompleter = null;
    completer?.complete();
  }

  @override
  Widget build(BuildContext context) {
    final card = _openCard;
    return Stack(
      children: <Widget>[
        widget.child,
        if (card != null)
          VocabCardPopover(
            key: ValueKey<String>('vocab-card-host-popover-${card.id}'),
            card: card,
            audioService: widget.audioService,
            pronunciationAudioRef: _openPronunciationAudioRef,
            onClosed: _handleClosed,
          ),
      ],
    );
  }
}
