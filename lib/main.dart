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
/// ## Owner content this boot still waits on
///
/// Two of these values are owner/authored content that has not shipped into
/// the binary yet, so boot degrades rather than crashing:
///
///  * **the bundled starter pack (A-9)** — read from
///    `<app support>/starter_pack/manifest.json` when present, otherwise an
///    empty pack, so the app boots to the picker with an empty trail;
///  * **the scope & sequence (OQ-5)** — read from
///    `<app support>/scope_sequence.json` when present, otherwise an empty
///    ladder.
///
/// Bundling both as real Flutter assets is the content pipeline's ticket; the
/// seam they arrive through does not change.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:learn_to_read/app/app.dart';
import 'package:learn_to_read/app/providers.dart';
import 'package:learn_to_read/data/content/pack_installer.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';

/// Directory name of the bundled starter pack, under the app support
/// directory.
const String kStarterPackDirectoryName = 'starter_pack';

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
  final overrides = await buildBootOverrides();
  runApp(ProviderScope(overrides: overrides, child: const LearnToReadApp()));
}

/// The production values for every seam that has no sensible default.
///
/// Kept separate from [bootLearnToRead] so a device/integration harness can
/// boot the real shell with a subset of these replaced.
Future<List<Override>> buildBootOverrides() async {
  final support = await getApplicationSupportDirectory();

  final starterDirectory = _directory(support, kStarterPackDirectoryName);
  final packsDirectory = _directory(support, kInstalledPacksDirectoryName);
  final analyticsDirectory = _directory(support, kAnalyticsDirectoryName);

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
  ];
}

Directory _directory(Directory parent, String name) =>
    Directory(p.join(parent.path, name))..createSync(recursive: true);

/// The pack that ships inside the binary (A-9), or an empty stand-in until
/// it does.
Future<LoadedPack> _loadStarterPack(Directory directory) async {
  final manifest = File(p.join(directory.path, kPackManifestFileName));
  if (manifest.existsSync()) {
    try {
      return await loadPackFromDirectory(directory);
    } on PackLoadException {
      // A corrupt bundled pack must not stop the app from opening; the child
      // sees an empty trail rather than a crash.
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
    } on FormatException {
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
