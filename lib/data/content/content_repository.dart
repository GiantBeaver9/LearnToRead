/// The app's single read surface over all available content
/// (PRD §8 Unit 11 "starter pack always present from the binary"; §8 Unit 15
/// grapheme inventory; §6 Offline; §9 A-9; ticket `content-delivery` accept
/// entries 2 and 9).
///
/// One repository merges the bundled starter pack — which ships inside the
/// binary and is therefore *always* present — with whatever CDN packs have
/// been installed, and hands features a single list of stories, twisters,
/// vocab cards, collectibles, and grapheme cards.
///
/// ## Why there is no network dependency here
///
/// [ContentRepository]'s constructor takes a loaded starter pack and a
/// [PackInstaller]. There is no fetcher, no catalog client, no connectivity
/// probe — not as a matter of discipline but as a matter of type: reading
/// content *cannot* touch the network, because this class holds nothing that
/// could. A fresh install in airplane mode therefore serves the full starter
/// experience with no special offline mode, no cache warming, and no
/// first-run fetch to fail. `catalog_client.dart`'s silent-failure contract
/// is what keeps a launch-time catalog check from disturbing any of it.
///
/// ## Merge order
///
/// Starter first, then installed packs ordered by id. Deterministic order
/// matters beyond tidiness: it decides which pack wins a collision, and a
/// child seeing a card reorder itself between launches is a bug even when
/// the content is identical.
///
/// ## Unit 15: the grapheme inventory
///
/// The grapheme-sound inventory is fixed and ships in the binary — the
/// starter pack owns the id set, and an installed pack can only *extend* an
/// existing card's example words, never introduce a new card. That keeps the
/// Sound Garden's shape a property of the app build (so the phonics
/// progression cannot be reshaped by a content drop) while still letting
/// packs enrich it.
///
/// Example words are filtered to those whose audio actually resolves inside
/// the contributing pack's own directory. A pack may ship a manifest that
/// lists more than the bytes present — an optional asset, a partially
/// installed bundle — and a word with no local audio is silently dropped
/// rather than offered as a card that would fail to speak when tapped
/// ("shows only words it has audio for").
library;

import 'package:learn_to_read/data/content/pack_installer.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';

/// Reads merged content out of the bundled starter pack plus every installed
/// CDN pack.
class ContentRepository {
  ContentRepository({
    required LoadedPack starterPack,
    required PackInstaller installer,
  }) : _starterPack = starterPack,
       _installer = installer;

  /// The pack that ships in the binary (A-9: ~8 stories covering all three
  /// age-band starting levels). Never absent, never downloaded.
  final LoadedPack _starterPack;

  final PackInstaller _installer;

  /// Every story: the starter pack's first, then each installed pack's,
  /// installed packs ordered by id.
  Future<List<Story>> stories() => _collect((pack) => pack.stories);

  /// Every tongue twister, in the same merge order as [stories].
  Future<List<TongueTwister>> twisters() => _collect((pack) => pack.twisters);

  /// Every vocab card, in the same merge order as [stories].
  Future<List<VocabCard>> vocabCards() => _collect((pack) => pack.vocabCards);

  /// Every collectible, in the same merge order as [stories].
  Future<List<Collectible>> collectibles() =>
      _collect((pack) => pack.collectibles);

  /// The Unit 15 grapheme inventory: one entry per starter-pack
  /// `GraphemeSound` id, in starter order, each carrying the example words
  /// available for it right now.
  ///
  /// For each id, example words are gathered from every contributing pack in
  /// merge order (starter, then installed packs by id), keeping only entries
  /// whose `pronunciationAudioRef` resolves to a real file *within that
  /// contributing pack's own directory*, then deduped by `wordText` keeping
  /// the first survivor — so the starter's own recording wins a collision
  /// with an installed pack's, and the same word never appears twice on a
  /// card.
  ///
  /// Installed packs that declare a `GraphemeSound` id the starter does not
  /// have are ignored entirely: the inventory's shape belongs to the binary.
  Future<List<GraphemeSound>> graphemeInventory() async {
    final packs = await _packsInMergeOrder();

    final merged = <GraphemeSound>[];
    for (final starterSound in _starterPack.pack.graphemeSounds) {
      final words =
          <
            ({String wordText, String pronunciationAudioRef, String minLevelId})
          >[];
      final seenWords = <String>{};
      for (final pack in packs) {
        for (final sound in pack.pack.graphemeSounds) {
          if (sound.id != starterSound.id) continue;
          for (final word in sound.exampleWords) {
            if (!pack.hasAsset(word.pronunciationAudioRef)) continue;
            if (!seenWords.add(word.wordText)) continue;
            words.add(word);
          }
        }
      }
      merged.add(
        GraphemeSound(
          id: starterSound.id,
          grapheme: starterSound.grapheme,
          phonemeIds: starterSound.phonemeIds,
          introducedAtLevelId: starterSound.introducedAtLevelId,
          exampleWords: words,
        ),
      );
    }
    return List.unmodifiable(merged);
  }

  Future<List<T>> _collect<T>(List<T> Function(StoryPack) select) async {
    final packs = await _packsInMergeOrder();
    return List.unmodifiable([for (final pack in packs) ...select(pack.pack)]);
  }

  /// The starter pack, then every installed pack ordered by id. Installed
  /// packs are re-read on each call rather than cached: an install that
  /// lands while the app is running must become visible without a restart,
  /// and a pack directory is a handful of small reads.
  Future<List<LoadedPack>> _packsInMergeOrder() async {
    final infos = List<InstalledPackInfo>.of(await _installer.installedPacks())
      ..sort((a, b) => a.id.compareTo(b.id));
    final packs = <LoadedPack>[_starterPack];
    for (final info in infos) {
      final loaded = await _installer.loadInstalled(info.id);
      if (loaded != null) packs.add(loaded);
    }
    return packs;
  }
}
