/// The production entrypoint (PRD §8 Unit 1; ticket `app-shell`).
///
/// `main()` does exactly one thing beyond `runApp`: it resolves the handful of
/// values that can only be known on a real device — the app's on-disk
/// directories, the bundled starter pack, the authored scope & sequence, and
/// the per-install UUID — and hands them to `ProviderScope` as overrides of
/// the seams declared in `lib/app/providers.dart`. Everything else the app is
/// composed of is already wired there, which is why the whole app is drivable
/// headlessly from `test/app/` with the same widget and a different set of
/// overrides.
///
/// ## Bundled content (A-9)
///
/// The demo starter pack + scope & sequence ship inside the binary as ONE
/// Flutter asset, `assets/starter_content.bin` (built by
/// `tool/bundle_content.dart`; format in
/// `lib/data/content/starter_archive.dart`). Before anything is loaded, boot
/// extracts that archive into the app-support directory — first run only, or
/// when the bundled content changed — per the coexistence rule pinned in
/// `lib/data/content/starter_content_installer.dart` (a sideloaded
/// `starter_pack/` always wins). Extraction, archive verification, and the
/// pack-manifest decode all run off the UI isolate via [Isolate.run]; only
/// the `rootBundle.load` of the asset bytes happens on the main isolate
/// (rootBundle requires it). Both loads still degrade rather than crash:
///
///  * **the bundled starter pack** — read from
///    `<app support>/starter_pack/manifest.json` when present, otherwise an
///    empty pack, so the app boots to the picker with an empty trail;
///  * **the scope & sequence (OQ-5)** — read from
///    `<app support>/scope_sequence.json` when present, otherwise an empty
///    ladder.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:learn_to_read/app/app.dart';
import 'package:learn_to_read/app/providers.dart';
import 'package:learn_to_read/design/builtin_story_stage.dart';
import 'package:learn_to_read/data/content/pack_installer.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/data/content/starter_content_installer.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/just_audio_service.dart';

/// Asset key of the bundled starter-content archive (see
/// `tool/bundle_content.dart`).
const String kStarterContentAssetKey = 'assets/starter_content.bin';

/// Directory name downloaded CDN packs are installed into.
const String kInstalledPacksDirectoryName = 'packs';

/// Directory name the offline analytics queue file lives in — deliberately
/// disjoint from the Drift user database.
const String kAnalyticsDirectoryName = 'analytics';

/// File name of the authored scope & sequence document.
const String kScopeSequenceFileName = 'scope_sequence.json';

/// File name the per-install UUID is persisted under.
const String kInstallIdFileName = 'install_id';

/// A scope & sequence with no levels and no stories.
///
/// The shape `loadPhonicsContent` expects, used when no authored document has
/// shipped yet: the app boots, the picker works, and the trail is empty.
const String kEmptyScopeSequenceJson = '{"levels":[],"stories":[]}';

void main() => unawaited(bootLearnToRead());

/// Resolves the device-only boot values and starts the app.
Future<void> bootLearnToRead() async {
  WidgetsFlutterBinding.ensureInitialized();
  List<Override> overrides;
  try {
    overrides = await buildBootOverrides();
  } on Object {
    // Boot must never strand the splash: if device-only resolution fails
    // for any reason, run the app on its headless-safe provider defaults
    // (empty content, fake audio) — alive and diagnosable beats frozen.
    overrides = const <Override>[];
  }
  runApp(ProviderScope(overrides: overrides, child: const LearnToReadApp()));
}

/// The production values for every seam that has no sensible default.
///
/// Kept separate from [bootLearnToRead] so a device/integration harness can
/// boot the real shell with a subset of these replaced.
Future<List<Override>> buildBootOverrides() async {
  final support = await getApplicationSupportDirectory();

  await _extractBundledStarterContent(support);

  final starterDirectory = _directory(support, kStarterPackDirectoryName);
  final packsDirectory = _directory(support, kInstalledPacksDirectoryName);
  final analyticsDirectory = _directory(support, kAnalyticsDirectoryName);

  final resolveAudioRef = _audioRefResolver(starterDirectory, packsDirectory);
  final celebrationLines = _presentRefs(resolveAudioRef, [
    for (var i = 4; i <= 10; i++)
      'celebrations/cheer_${i.toString().padLeft(2, '0')}.wav',
  ]);

  return <Override>[
    starterPackProvider
        .overrideWithValue(await _loadStarterPack(starterDirectory)),
    packInstallerProvider.overrideWithValue(
      PackInstaller(installedPacksDirectory: packsDirectory),
    ),
    phonicsContentProvider
        .overrideWithValue(await _loadPhonicsContent(support)),
    analyticsStorageDirectoryProvider.overrideWithValue(analyticsDirectory),
    installIdProvider.overrideWithValue(await _readOrCreateInstallId(support)),
    // Real device audio: the just_audio adapter over every content
    // directory known at boot. Everything below degrades to the headless
    // default (or the provider's placeholder ref) when the corresponding
    // content has not shipped/sideloaded yet, so a content-less install
    // still boots exactly as before.
    audioServiceProvider
        .overrideWithValue(JustAudioService(resolveRef: resolveAudioRef)),
    phonemeAudioRefsProvider
        .overrideWithValue(_phonemeRefs(resolveAudioRef)),
    if (resolveAudioRef('prompts/your_turn.wav') != null)
      yourTurnPromptAudioRefProvider.overrideWithValue('prompts/your_turn.wav'),
    if (resolveAudioRef('prompts/near_miss.wav') != null)
      nearMissPromptAudioRefProvider.overrideWithValue('prompts/near_miss.wav'),
    if (celebrationLines.isNotEmpty)
      celebrationVoiceLineRefsProvider.overrideWithValue(celebrationLines),
    // Visible story animation (owner: "getting basic animation running"):
    // on device every stage is the code-drawn BuiltInStoryStage, so the
    // idle/celebrate/collect beats actually show something alive. Scene
    // seeds increment per construction — time-free and deterministic within
    // a boot, so concurrently-live stages (reading route, each collection
    // tile) each get their own arrangement. The provider's headless default
    // stays FakeStoryStage (tests depend on it); per-story seeding would
    // need the story id plumbed into the factory — a future wiring change,
    // not forced here.
    storyStageFactoryProvider.overrideWith((ref) {
      var nextSceneSeed = 0;
      return () => BuiltInStoryStage(sceneSeed: nextSceneSeed++);
    }),
  ];
}

/// Maps a pack-relative [AudioRef] to an absolute file path, searching the
/// starter-pack directory first and then every installed pack directory.
/// The directory set is fixed at boot (packs installed mid-session are
/// picked up on next launch — acceptable for the POC).
String? Function(AudioRef ref) _audioRefResolver(
  Directory starterDirectory,
  Directory packsDirectory,
) {
  final searchDirectories = <Directory>[
    starterDirectory,
    ...packsDirectory.listSync().whereType<Directory>(),
  ];
  return (AudioRef ref) {
    for (final directory in searchDirectories) {
      final path = p.joinAll([directory.path, ...ref.split('/')]);
      if (File(path).existsSync()) return path;
    }
    return null;
  };
}

/// The refs from [candidates] that resolve to a shipped file.
List<AudioRef> _presentRefs(
  String? Function(AudioRef ref) resolveAudioRef,
  List<AudioRef> candidates,
) =>
    [for (final ref in candidates) if (resolveAudioRef(ref) != null) ref];

/// Phoneme id -> `phonemes/<id>.wav` for every one of the 44 clips actually
/// shipped (sound-out help and Sound Garden; empty entries simply fall back
/// to the app's silent default for that phoneme).
Map<String, AudioRef> _phonemeRefs(
  String? Function(AudioRef ref) resolveAudioRef,
) =>
    {
      for (final id in kEnglishPhonemeIds)
        if (resolveAudioRef('phonemes/$id.wav') != null)
          id: 'phonemes/$id.wav',
    };

Directory _directory(Directory parent, String name) =>
    Directory(p.join(parent.path, name))..createSync(recursive: true);

/// Materializes `assets/starter_content.bin` into `<support>/starter_pack`
/// (+ `<support>/scope_sequence.json`) when needed — see
/// `starter_content_installer.dart` for the exact first-run / update /
/// sideload-wins rule.
///
/// The asset bytes are loaded here (rootBundle only works on the main
/// isolate); checksum verification and extraction run in [Isolate.run] so
/// the first frame is never blocked on them. Any failure — asset not
/// bundled (tests, content-less builds), corrupt archive, IO error — is
/// swallowed: boot then proceeds against whatever is (or is not) on disk,
/// exactly the pre-existing degrade posture.
Future<void> _extractBundledStarterContent(Directory support) async {
  final Uint8List archiveBytes;
  try {
    archiveBytes =
        Uint8List.sublistView(await rootBundle.load(kStarterContentAssetKey));
  } on Object {
    return; // No bundled archive: nothing to extract.
  }
  final supportPath = support.path;
  try {
    await Isolate.run(
      () => syncBundledStarterContent(
        archiveBytes: archiveBytes,
        supportDirectory: Directory(supportPath),
      ),
    );
  } on Object {
    // Corrupt archive or IO failure: never strand the splash. The loaders
    // below fall back to whatever is on disk (possibly the empty pack).
  }
}

/// The pack that ships inside the binary (A-9), or an empty stand-in until
/// it does.
///
/// The manifest read + jsonDecode + model build run in [Isolate.run] so the
/// UI isolate never parses the (large) manifest before the first frame.
/// `loadPackFromDirectory` stays the single load path.
Future<LoadedPack> _loadStarterPack(Directory directory) async {
  final manifest = File(p.join(directory.path, kPackManifestFileName));
  if (manifest.existsSync()) {
    try {
      final directoryPath = directory.path;
      return await Isolate.run(
        () => loadPackFromDirectory(Directory(directoryPath)),
      );
    } on Object {
      // A corrupt/partial bundled pack (bad sideload, tampered files, any
      // parse or checksum failure) must not stop the app from opening; the
      // child sees an empty trail rather than a frozen splash.
    }
  }
  return LoadedPack(pack: _emptyPack(), directory: directory);
}

StoryPack _emptyPack() => StoryPack(
      id: 'pack.starter',
      version: '0.0.0',
      minAppVersion: kAppVersion,
      stories: const <Story>[],
      twisters: const <TongueTwister>[],
      vocabCards: const <VocabCard>[],
      collectibles: const <Collectible>[],
      graphemeSounds: const <GraphemeSound>[],
      assetRefs: const <String>[],
      checksum: '',
    );

/// The authored scope & sequence (PRD §8 Unit 2: "stored as data, not code"),
/// or an empty ladder until it ships.
Future<PhonicsContent> _loadPhonicsContent(Directory support) async {
  final file = File(p.join(support.path, kScopeSequenceFileName));
  if (file.existsSync()) {
    try {
      return loadPhonicsContent(await file.readAsString());
    } on Object {
      // Same posture as a corrupt pack: boot, then show nothing, rather than
      // failing to start at all.
    }
  }
  return loadPhonicsContent(kEmptyScopeSequenceJson);
}

/// The random per-install UUID stamped on every §5 analytics event.
///
/// Created once and persisted next to the app's own data. Never a device
/// identifier: uninstalling the app destroys it.
Future<String> _readOrCreateInstallId(Directory support) async {
  final file = File(p.join(support.path, kInstallIdFileName));
  if (file.existsSync()) {
    final existing = (await file.readAsString()).trim();
    if (_installIdPattern.hasMatch(existing)) return existing;
  }
  final created = generateInstallId(Random.secure());
  await file.writeAsString(created, flush: true);
  return created;
}

final RegExp _installIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}$',
);
