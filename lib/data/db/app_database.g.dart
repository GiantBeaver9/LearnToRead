// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles
    with TableInfo<$ProfilesTable, ProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AgeBand, int> ageBand =
      GeneratedColumn<int>(
        'age_band',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<AgeBand>($ProfilesTable.$converterageBand);
  static const VerificationMeta _currentLevelIdMeta = const VerificationMeta(
    'currentLevelId',
  );
  @override
  late final GeneratedColumn<String> currentLevelId = GeneratedColumn<String>(
    'current_level_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _micConsentMeta = const VerificationMeta(
    'micConsent',
  );
  @override
  late final GeneratedColumn<bool> micConsent = GeneratedColumn<bool>(
    'mic_consent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("mic_consent" IN (0, 1))',
    ),
  );
  static const VerificationMeta _cloudAsrConsentMeta = const VerificationMeta(
    'cloudAsrConsent',
  );
  @override
  late final GeneratedColumn<bool> cloudAsrConsent = GeneratedColumn<bool>(
    'cloud_asr_consent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("cloud_asr_consent" IN (0, 1))',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    displayName,
    ageBand,
    currentLevelId,
    micConsent,
    cloudAsrConsent,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('current_level_id')) {
      context.handle(
        _currentLevelIdMeta,
        currentLevelId.isAcceptableOrUnknown(
          data['current_level_id']!,
          _currentLevelIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentLevelIdMeta);
    }
    if (data.containsKey('mic_consent')) {
      context.handle(
        _micConsentMeta,
        micConsent.isAcceptableOrUnknown(data['mic_consent']!, _micConsentMeta),
      );
    } else if (isInserting) {
      context.missing(_micConsentMeta);
    }
    if (data.containsKey('cloud_asr_consent')) {
      context.handle(
        _cloudAsrConsentMeta,
        cloudAsrConsent.isAcceptableOrUnknown(
          data['cloud_asr_consent']!,
          _cloudAsrConsentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cloudAsrConsentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  ProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileRow(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      ageBand: $ProfilesTable.$converterageBand.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}age_band'],
        )!,
      ),
      currentLevelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_level_id'],
      )!,
      micConsent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}mic_consent'],
      )!,
      cloudAsrConsent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}cloud_asr_consent'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }

  static TypeConverter<AgeBand, int> $converterageBand =
      const AgeBandConverter();
}

class ProfileRow extends DataClass implements Insertable<ProfileRow> {
  final String localId;
  final String displayName;
  final AgeBand ageBand;
  final String currentLevelId;
  final bool micConsent;
  final bool cloudAsrConsent;
  final DateTime createdAt;
  const ProfileRow({
    required this.localId,
    required this.displayName,
    required this.ageBand,
    required this.currentLevelId,
    required this.micConsent,
    required this.cloudAsrConsent,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    map['display_name'] = Variable<String>(displayName);
    {
      map['age_band'] = Variable<int>(
        $ProfilesTable.$converterageBand.toSql(ageBand),
      );
    }
    map['current_level_id'] = Variable<String>(currentLevelId);
    map['mic_consent'] = Variable<bool>(micConsent);
    map['cloud_asr_consent'] = Variable<bool>(cloudAsrConsent);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      localId: Value(localId),
      displayName: Value(displayName),
      ageBand: Value(ageBand),
      currentLevelId: Value(currentLevelId),
      micConsent: Value(micConsent),
      cloudAsrConsent: Value(cloudAsrConsent),
      createdAt: Value(createdAt),
    );
  }

  factory ProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileRow(
      localId: serializer.fromJson<String>(json['localId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      ageBand: serializer.fromJson<AgeBand>(json['ageBand']),
      currentLevelId: serializer.fromJson<String>(json['currentLevelId']),
      micConsent: serializer.fromJson<bool>(json['micConsent']),
      cloudAsrConsent: serializer.fromJson<bool>(json['cloudAsrConsent']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'displayName': serializer.toJson<String>(displayName),
      'ageBand': serializer.toJson<AgeBand>(ageBand),
      'currentLevelId': serializer.toJson<String>(currentLevelId),
      'micConsent': serializer.toJson<bool>(micConsent),
      'cloudAsrConsent': serializer.toJson<bool>(cloudAsrConsent),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ProfileRow copyWith({
    String? localId,
    String? displayName,
    AgeBand? ageBand,
    String? currentLevelId,
    bool? micConsent,
    bool? cloudAsrConsent,
    DateTime? createdAt,
  }) => ProfileRow(
    localId: localId ?? this.localId,
    displayName: displayName ?? this.displayName,
    ageBand: ageBand ?? this.ageBand,
    currentLevelId: currentLevelId ?? this.currentLevelId,
    micConsent: micConsent ?? this.micConsent,
    cloudAsrConsent: cloudAsrConsent ?? this.cloudAsrConsent,
    createdAt: createdAt ?? this.createdAt,
  );
  ProfileRow copyWithCompanion(ProfilesCompanion data) {
    return ProfileRow(
      localId: data.localId.present ? data.localId.value : this.localId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      ageBand: data.ageBand.present ? data.ageBand.value : this.ageBand,
      currentLevelId: data.currentLevelId.present
          ? data.currentLevelId.value
          : this.currentLevelId,
      micConsent: data.micConsent.present
          ? data.micConsent.value
          : this.micConsent,
      cloudAsrConsent: data.cloudAsrConsent.present
          ? data.cloudAsrConsent.value
          : this.cloudAsrConsent,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileRow(')
          ..write('localId: $localId, ')
          ..write('displayName: $displayName, ')
          ..write('ageBand: $ageBand, ')
          ..write('currentLevelId: $currentLevelId, ')
          ..write('micConsent: $micConsent, ')
          ..write('cloudAsrConsent: $cloudAsrConsent, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    displayName,
    ageBand,
    currentLevelId,
    micConsent,
    cloudAsrConsent,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileRow &&
          other.localId == this.localId &&
          other.displayName == this.displayName &&
          other.ageBand == this.ageBand &&
          other.currentLevelId == this.currentLevelId &&
          other.micConsent == this.micConsent &&
          other.cloudAsrConsent == this.cloudAsrConsent &&
          other.createdAt == this.createdAt);
}

class ProfilesCompanion extends UpdateCompanion<ProfileRow> {
  final Value<String> localId;
  final Value<String> displayName;
  final Value<AgeBand> ageBand;
  final Value<String> currentLevelId;
  final Value<bool> micConsent;
  final Value<bool> cloudAsrConsent;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.localId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.ageBand = const Value.absent(),
    this.currentLevelId = const Value.absent(),
    this.micConsent = const Value.absent(),
    this.cloudAsrConsent = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String localId,
    required String displayName,
    required AgeBand ageBand,
    required String currentLevelId,
    required bool micConsent,
    required bool cloudAsrConsent,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       displayName = Value(displayName),
       ageBand = Value(ageBand),
       currentLevelId = Value(currentLevelId),
       micConsent = Value(micConsent),
       cloudAsrConsent = Value(cloudAsrConsent),
       createdAt = Value(createdAt);
  static Insertable<ProfileRow> custom({
    Expression<String>? localId,
    Expression<String>? displayName,
    Expression<int>? ageBand,
    Expression<String>? currentLevelId,
    Expression<bool>? micConsent,
    Expression<bool>? cloudAsrConsent,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (displayName != null) 'display_name': displayName,
      if (ageBand != null) 'age_band': ageBand,
      if (currentLevelId != null) 'current_level_id': currentLevelId,
      if (micConsent != null) 'mic_consent': micConsent,
      if (cloudAsrConsent != null) 'cloud_asr_consent': cloudAsrConsent,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith({
    Value<String>? localId,
    Value<String>? displayName,
    Value<AgeBand>? ageBand,
    Value<String>? currentLevelId,
    Value<bool>? micConsent,
    Value<bool>? cloudAsrConsent,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ProfilesCompanion(
      localId: localId ?? this.localId,
      displayName: displayName ?? this.displayName,
      ageBand: ageBand ?? this.ageBand,
      currentLevelId: currentLevelId ?? this.currentLevelId,
      micConsent: micConsent ?? this.micConsent,
      cloudAsrConsent: cloudAsrConsent ?? this.cloudAsrConsent,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (ageBand.present) {
      map['age_band'] = Variable<int>(
        $ProfilesTable.$converterageBand.toSql(ageBand.value),
      );
    }
    if (currentLevelId.present) {
      map['current_level_id'] = Variable<String>(currentLevelId.value);
    }
    if (micConsent.present) {
      map['mic_consent'] = Variable<bool>(micConsent.value);
    }
    if (cloudAsrConsent.present) {
      map['cloud_asr_consent'] = Variable<bool>(cloudAsrConsent.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('localId: $localId, ')
          ..write('displayName: $displayName, ')
          ..write('ageBand: $ageBand, ')
          ..write('currentLevelId: $currentLevelId, ')
          ..write('micConsent: $micConsent, ')
          ..write('cloudAsrConsent: $cloudAsrConsent, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoryProgressEntriesTable extends StoryProgressEntries
    with TableInfo<$StoryProgressEntriesTable, StoryProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoryProgressEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storyIdMeta = const VerificationMeta(
    'storyId',
  );
  @override
  late final GeneratedColumn<String> storyId = GeneratedColumn<String>(
    'story_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<StoryStatus, int> status =
      GeneratedColumn<int>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<StoryStatus>($StoryProgressEntriesTable.$converterstatus);
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timesReadMeta = const VerificationMeta(
    'timesRead',
  );
  @override
  late final GeneratedColumn<int> timesRead = GeneratedColumn<int>(
    'times_read',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    profileId,
    storyId,
    status,
    completedAt,
    timesRead,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'story_progress_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoryProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('story_id')) {
      context.handle(
        _storyIdMeta,
        storyId.isAcceptableOrUnknown(data['story_id']!, _storyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storyIdMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('times_read')) {
      context.handle(
        _timesReadMeta,
        timesRead.isAcceptableOrUnknown(data['times_read']!, _timesReadMeta),
      );
    } else if (isInserting) {
      context.missing(_timesReadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, storyId};
  @override
  StoryProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoryProgressRow(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      storyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}story_id'],
      )!,
      status: $StoryProgressEntriesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}status'],
        )!,
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      timesRead: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}times_read'],
      )!,
    );
  }

  @override
  $StoryProgressEntriesTable createAlias(String alias) {
    return $StoryProgressEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<StoryStatus, int> $converterstatus =
      const StoryStatusConverter();
}

class StoryProgressRow extends DataClass
    implements Insertable<StoryProgressRow> {
  final String profileId;
  final String storyId;
  final StoryStatus status;

  /// Null until the story is first completed; never moves after that.
  final DateTime? completedAt;
  final int timesRead;
  const StoryProgressRow({
    required this.profileId,
    required this.storyId,
    required this.status,
    this.completedAt,
    required this.timesRead,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['story_id'] = Variable<String>(storyId);
    {
      map['status'] = Variable<int>(
        $StoryProgressEntriesTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['times_read'] = Variable<int>(timesRead);
    return map;
  }

  StoryProgressEntriesCompanion toCompanion(bool nullToAbsent) {
    return StoryProgressEntriesCompanion(
      profileId: Value(profileId),
      storyId: Value(storyId),
      status: Value(status),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      timesRead: Value(timesRead),
    );
  }

  factory StoryProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoryProgressRow(
      profileId: serializer.fromJson<String>(json['profileId']),
      storyId: serializer.fromJson<String>(json['storyId']),
      status: serializer.fromJson<StoryStatus>(json['status']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      timesRead: serializer.fromJson<int>(json['timesRead']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'storyId': serializer.toJson<String>(storyId),
      'status': serializer.toJson<StoryStatus>(status),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'timesRead': serializer.toJson<int>(timesRead),
    };
  }

  StoryProgressRow copyWith({
    String? profileId,
    String? storyId,
    StoryStatus? status,
    Value<DateTime?> completedAt = const Value.absent(),
    int? timesRead,
  }) => StoryProgressRow(
    profileId: profileId ?? this.profileId,
    storyId: storyId ?? this.storyId,
    status: status ?? this.status,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    timesRead: timesRead ?? this.timesRead,
  );
  StoryProgressRow copyWithCompanion(StoryProgressEntriesCompanion data) {
    return StoryProgressRow(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      storyId: data.storyId.present ? data.storyId.value : this.storyId,
      status: data.status.present ? data.status.value : this.status,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      timesRead: data.timesRead.present ? data.timesRead.value : this.timesRead,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoryProgressRow(')
          ..write('profileId: $profileId, ')
          ..write('storyId: $storyId, ')
          ..write('status: $status, ')
          ..write('completedAt: $completedAt, ')
          ..write('timesRead: $timesRead')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(profileId, storyId, status, completedAt, timesRead);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoryProgressRow &&
          other.profileId == this.profileId &&
          other.storyId == this.storyId &&
          other.status == this.status &&
          other.completedAt == this.completedAt &&
          other.timesRead == this.timesRead);
}

class StoryProgressEntriesCompanion extends UpdateCompanion<StoryProgressRow> {
  final Value<String> profileId;
  final Value<String> storyId;
  final Value<StoryStatus> status;
  final Value<DateTime?> completedAt;
  final Value<int> timesRead;
  final Value<int> rowid;
  const StoryProgressEntriesCompanion({
    this.profileId = const Value.absent(),
    this.storyId = const Value.absent(),
    this.status = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.timesRead = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoryProgressEntriesCompanion.insert({
    required String profileId,
    required String storyId,
    required StoryStatus status,
    this.completedAt = const Value.absent(),
    required int timesRead,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       storyId = Value(storyId),
       status = Value(status),
       timesRead = Value(timesRead);
  static Insertable<StoryProgressRow> custom({
    Expression<String>? profileId,
    Expression<String>? storyId,
    Expression<int>? status,
    Expression<DateTime>? completedAt,
    Expression<int>? timesRead,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (storyId != null) 'story_id': storyId,
      if (status != null) 'status': status,
      if (completedAt != null) 'completed_at': completedAt,
      if (timesRead != null) 'times_read': timesRead,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoryProgressEntriesCompanion copyWith({
    Value<String>? profileId,
    Value<String>? storyId,
    Value<StoryStatus>? status,
    Value<DateTime?>? completedAt,
    Value<int>? timesRead,
    Value<int>? rowid,
  }) {
    return StoryProgressEntriesCompanion(
      profileId: profileId ?? this.profileId,
      storyId: storyId ?? this.storyId,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      timesRead: timesRead ?? this.timesRead,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (storyId.present) {
      map['story_id'] = Variable<String>(storyId.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(
        $StoryProgressEntriesTable.$converterstatus.toSql(status.value),
      );
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (timesRead.present) {
      map['times_read'] = Variable<int>(timesRead.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoryProgressEntriesCompanion(')
          ..write('profileId: $profileId, ')
          ..write('storyId: $storyId, ')
          ..write('status: $status, ')
          ..write('completedAt: $completedAt, ')
          ..write('timesRead: $timesRead, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WordHelpRecordsTable extends WordHelpRecords
    with TableInfo<$WordHelpRecordsTable, WordHelpRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WordHelpRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordTextMeta = const VerificationMeta(
    'wordText',
  );
  @override
  late final GeneratedColumn<String> wordText = GeneratedColumn<String>(
    'word_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encounterCountMeta = const VerificationMeta(
    'encounterCount',
  );
  @override
  late final GeneratedColumn<int> encounterCount = GeneratedColumn<int>(
    'encounter_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _helpCountMeta = const VerificationMeta(
    'helpCount',
  );
  @override
  late final GeneratedColumn<int> helpCount = GeneratedColumn<int>(
    'help_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<HelpLevel, int> lastHelpLevel =
      GeneratedColumn<int>(
        'last_help_level',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<HelpLevel>($WordHelpRecordsTable.$converterlastHelpLevel);
  @override
  List<GeneratedColumn> get $columns => [
    profileId,
    wordText,
    encounterCount,
    helpCount,
    lastHelpLevel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'word_help_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<WordHelpRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('word_text')) {
      context.handle(
        _wordTextMeta,
        wordText.isAcceptableOrUnknown(data['word_text']!, _wordTextMeta),
      );
    } else if (isInserting) {
      context.missing(_wordTextMeta);
    }
    if (data.containsKey('encounter_count')) {
      context.handle(
        _encounterCountMeta,
        encounterCount.isAcceptableOrUnknown(
          data['encounter_count']!,
          _encounterCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encounterCountMeta);
    }
    if (data.containsKey('help_count')) {
      context.handle(
        _helpCountMeta,
        helpCount.isAcceptableOrUnknown(data['help_count']!, _helpCountMeta),
      );
    } else if (isInserting) {
      context.missing(_helpCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, wordText};
  @override
  WordHelpRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WordHelpRow(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      wordText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_text'],
      )!,
      encounterCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}encounter_count'],
      )!,
      helpCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}help_count'],
      )!,
      lastHelpLevel: $WordHelpRecordsTable.$converterlastHelpLevel.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_help_level'],
        )!,
      ),
    );
  }

  @override
  $WordHelpRecordsTable createAlias(String alias) {
    return $WordHelpRecordsTable(attachedDatabase, alias);
  }

  static TypeConverter<HelpLevel, int> $converterlastHelpLevel =
      const HelpLevelConverter();
}

class WordHelpRow extends DataClass implements Insertable<WordHelpRow> {
  final String profileId;
  final String wordText;
  final int encounterCount;
  final int helpCount;
  final HelpLevel lastHelpLevel;
  const WordHelpRow({
    required this.profileId,
    required this.wordText,
    required this.encounterCount,
    required this.helpCount,
    required this.lastHelpLevel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['word_text'] = Variable<String>(wordText);
    map['encounter_count'] = Variable<int>(encounterCount);
    map['help_count'] = Variable<int>(helpCount);
    {
      map['last_help_level'] = Variable<int>(
        $WordHelpRecordsTable.$converterlastHelpLevel.toSql(lastHelpLevel),
      );
    }
    return map;
  }

  WordHelpRecordsCompanion toCompanion(bool nullToAbsent) {
    return WordHelpRecordsCompanion(
      profileId: Value(profileId),
      wordText: Value(wordText),
      encounterCount: Value(encounterCount),
      helpCount: Value(helpCount),
      lastHelpLevel: Value(lastHelpLevel),
    );
  }

  factory WordHelpRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WordHelpRow(
      profileId: serializer.fromJson<String>(json['profileId']),
      wordText: serializer.fromJson<String>(json['wordText']),
      encounterCount: serializer.fromJson<int>(json['encounterCount']),
      helpCount: serializer.fromJson<int>(json['helpCount']),
      lastHelpLevel: serializer.fromJson<HelpLevel>(json['lastHelpLevel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'wordText': serializer.toJson<String>(wordText),
      'encounterCount': serializer.toJson<int>(encounterCount),
      'helpCount': serializer.toJson<int>(helpCount),
      'lastHelpLevel': serializer.toJson<HelpLevel>(lastHelpLevel),
    };
  }

  WordHelpRow copyWith({
    String? profileId,
    String? wordText,
    int? encounterCount,
    int? helpCount,
    HelpLevel? lastHelpLevel,
  }) => WordHelpRow(
    profileId: profileId ?? this.profileId,
    wordText: wordText ?? this.wordText,
    encounterCount: encounterCount ?? this.encounterCount,
    helpCount: helpCount ?? this.helpCount,
    lastHelpLevel: lastHelpLevel ?? this.lastHelpLevel,
  );
  WordHelpRow copyWithCompanion(WordHelpRecordsCompanion data) {
    return WordHelpRow(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      wordText: data.wordText.present ? data.wordText.value : this.wordText,
      encounterCount: data.encounterCount.present
          ? data.encounterCount.value
          : this.encounterCount,
      helpCount: data.helpCount.present ? data.helpCount.value : this.helpCount,
      lastHelpLevel: data.lastHelpLevel.present
          ? data.lastHelpLevel.value
          : this.lastHelpLevel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WordHelpRow(')
          ..write('profileId: $profileId, ')
          ..write('wordText: $wordText, ')
          ..write('encounterCount: $encounterCount, ')
          ..write('helpCount: $helpCount, ')
          ..write('lastHelpLevel: $lastHelpLevel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    profileId,
    wordText,
    encounterCount,
    helpCount,
    lastHelpLevel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordHelpRow &&
          other.profileId == this.profileId &&
          other.wordText == this.wordText &&
          other.encounterCount == this.encounterCount &&
          other.helpCount == this.helpCount &&
          other.lastHelpLevel == this.lastHelpLevel);
}

class WordHelpRecordsCompanion extends UpdateCompanion<WordHelpRow> {
  final Value<String> profileId;
  final Value<String> wordText;
  final Value<int> encounterCount;
  final Value<int> helpCount;
  final Value<HelpLevel> lastHelpLevel;
  final Value<int> rowid;
  const WordHelpRecordsCompanion({
    this.profileId = const Value.absent(),
    this.wordText = const Value.absent(),
    this.encounterCount = const Value.absent(),
    this.helpCount = const Value.absent(),
    this.lastHelpLevel = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WordHelpRecordsCompanion.insert({
    required String profileId,
    required String wordText,
    required int encounterCount,
    required int helpCount,
    required HelpLevel lastHelpLevel,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       wordText = Value(wordText),
       encounterCount = Value(encounterCount),
       helpCount = Value(helpCount),
       lastHelpLevel = Value(lastHelpLevel);
  static Insertable<WordHelpRow> custom({
    Expression<String>? profileId,
    Expression<String>? wordText,
    Expression<int>? encounterCount,
    Expression<int>? helpCount,
    Expression<int>? lastHelpLevel,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (wordText != null) 'word_text': wordText,
      if (encounterCount != null) 'encounter_count': encounterCount,
      if (helpCount != null) 'help_count': helpCount,
      if (lastHelpLevel != null) 'last_help_level': lastHelpLevel,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WordHelpRecordsCompanion copyWith({
    Value<String>? profileId,
    Value<String>? wordText,
    Value<int>? encounterCount,
    Value<int>? helpCount,
    Value<HelpLevel>? lastHelpLevel,
    Value<int>? rowid,
  }) {
    return WordHelpRecordsCompanion(
      profileId: profileId ?? this.profileId,
      wordText: wordText ?? this.wordText,
      encounterCount: encounterCount ?? this.encounterCount,
      helpCount: helpCount ?? this.helpCount,
      lastHelpLevel: lastHelpLevel ?? this.lastHelpLevel,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (wordText.present) {
      map['word_text'] = Variable<String>(wordText.value);
    }
    if (encounterCount.present) {
      map['encounter_count'] = Variable<int>(encounterCount.value);
    }
    if (helpCount.present) {
      map['help_count'] = Variable<int>(helpCount.value);
    }
    if (lastHelpLevel.present) {
      map['last_help_level'] = Variable<int>(
        $WordHelpRecordsTable.$converterlastHelpLevel.toSql(
          lastHelpLevel.value,
        ),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WordHelpRecordsCompanion(')
          ..write('profileId: $profileId, ')
          ..write('wordText: $wordText, ')
          ..write('encounterCount: $encounterCount, ')
          ..write('helpCount: $helpCount, ')
          ..write('lastHelpLevel: $lastHelpLevel, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TwisterProgressEntriesTable extends TwisterProgressEntries
    with TableInfo<$TwisterProgressEntriesTable, TwisterProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TwisterProgressEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _twisterIdMeta = const VerificationMeta(
    'twisterId',
  );
  @override
  late final GeneratedColumn<String> twisterId = GeneratedColumn<String>(
    'twister_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timesCompletedMeta = const VerificationMeta(
    'timesCompleted',
  );
  @override
  late final GeneratedColumn<int> timesCompleted = GeneratedColumn<int>(
    'times_completed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [profileId, twisterId, timesCompleted];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'twister_progress_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<TwisterProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('twister_id')) {
      context.handle(
        _twisterIdMeta,
        twisterId.isAcceptableOrUnknown(data['twister_id']!, _twisterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_twisterIdMeta);
    }
    if (data.containsKey('times_completed')) {
      context.handle(
        _timesCompletedMeta,
        timesCompleted.isAcceptableOrUnknown(
          data['times_completed']!,
          _timesCompletedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timesCompletedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, twisterId};
  @override
  TwisterProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TwisterProgressRow(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      twisterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}twister_id'],
      )!,
      timesCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}times_completed'],
      )!,
    );
  }

  @override
  $TwisterProgressEntriesTable createAlias(String alias) {
    return $TwisterProgressEntriesTable(attachedDatabase, alias);
  }
}

class TwisterProgressRow extends DataClass
    implements Insertable<TwisterProgressRow> {
  final String profileId;
  final String twisterId;
  final int timesCompleted;
  const TwisterProgressRow({
    required this.profileId,
    required this.twisterId,
    required this.timesCompleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['twister_id'] = Variable<String>(twisterId);
    map['times_completed'] = Variable<int>(timesCompleted);
    return map;
  }

  TwisterProgressEntriesCompanion toCompanion(bool nullToAbsent) {
    return TwisterProgressEntriesCompanion(
      profileId: Value(profileId),
      twisterId: Value(twisterId),
      timesCompleted: Value(timesCompleted),
    );
  }

  factory TwisterProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TwisterProgressRow(
      profileId: serializer.fromJson<String>(json['profileId']),
      twisterId: serializer.fromJson<String>(json['twisterId']),
      timesCompleted: serializer.fromJson<int>(json['timesCompleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'twisterId': serializer.toJson<String>(twisterId),
      'timesCompleted': serializer.toJson<int>(timesCompleted),
    };
  }

  TwisterProgressRow copyWith({
    String? profileId,
    String? twisterId,
    int? timesCompleted,
  }) => TwisterProgressRow(
    profileId: profileId ?? this.profileId,
    twisterId: twisterId ?? this.twisterId,
    timesCompleted: timesCompleted ?? this.timesCompleted,
  );
  TwisterProgressRow copyWithCompanion(TwisterProgressEntriesCompanion data) {
    return TwisterProgressRow(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      twisterId: data.twisterId.present ? data.twisterId.value : this.twisterId,
      timesCompleted: data.timesCompleted.present
          ? data.timesCompleted.value
          : this.timesCompleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TwisterProgressRow(')
          ..write('profileId: $profileId, ')
          ..write('twisterId: $twisterId, ')
          ..write('timesCompleted: $timesCompleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(profileId, twisterId, timesCompleted);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TwisterProgressRow &&
          other.profileId == this.profileId &&
          other.twisterId == this.twisterId &&
          other.timesCompleted == this.timesCompleted);
}

class TwisterProgressEntriesCompanion
    extends UpdateCompanion<TwisterProgressRow> {
  final Value<String> profileId;
  final Value<String> twisterId;
  final Value<int> timesCompleted;
  final Value<int> rowid;
  const TwisterProgressEntriesCompanion({
    this.profileId = const Value.absent(),
    this.twisterId = const Value.absent(),
    this.timesCompleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TwisterProgressEntriesCompanion.insert({
    required String profileId,
    required String twisterId,
    required int timesCompleted,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       twisterId = Value(twisterId),
       timesCompleted = Value(timesCompleted);
  static Insertable<TwisterProgressRow> custom({
    Expression<String>? profileId,
    Expression<String>? twisterId,
    Expression<int>? timesCompleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (twisterId != null) 'twister_id': twisterId,
      if (timesCompleted != null) 'times_completed': timesCompleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TwisterProgressEntriesCompanion copyWith({
    Value<String>? profileId,
    Value<String>? twisterId,
    Value<int>? timesCompleted,
    Value<int>? rowid,
  }) {
    return TwisterProgressEntriesCompanion(
      profileId: profileId ?? this.profileId,
      twisterId: twisterId ?? this.twisterId,
      timesCompleted: timesCompleted ?? this.timesCompleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (twisterId.present) {
      map['twister_id'] = Variable<String>(twisterId.value);
    }
    if (timesCompleted.present) {
      map['times_completed'] = Variable<int>(timesCompleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TwisterProgressEntriesCompanion(')
          ..write('profileId: $profileId, ')
          ..write('twisterId: $twisterId, ')
          ..write('timesCompleted: $timesCompleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionEntriesTable extends CollectionEntries
    with TableInfo<$CollectionEntriesTable, CollectionEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _collectibleIdMeta = const VerificationMeta(
    'collectibleId',
  );
  @override
  late final GeneratedColumn<String> collectibleId = GeneratedColumn<String>(
    'collectible_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [profileId, collectibleId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collection_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('collectible_id')) {
      context.handle(
        _collectibleIdMeta,
        collectibleId.isAcceptableOrUnknown(
          data['collectible_id']!,
          _collectibleIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectibleIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, collectibleId};
  @override
  CollectionEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionEntryRow(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      collectibleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collectible_id'],
      )!,
    );
  }

  @override
  $CollectionEntriesTable createAlias(String alias) {
    return $CollectionEntriesTable(attachedDatabase, alias);
  }
}

class CollectionEntryRow extends DataClass
    implements Insertable<CollectionEntryRow> {
  final String profileId;
  final String collectibleId;
  const CollectionEntryRow({
    required this.profileId,
    required this.collectibleId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['collectible_id'] = Variable<String>(collectibleId);
    return map;
  }

  CollectionEntriesCompanion toCompanion(bool nullToAbsent) {
    return CollectionEntriesCompanion(
      profileId: Value(profileId),
      collectibleId: Value(collectibleId),
    );
  }

  factory CollectionEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionEntryRow(
      profileId: serializer.fromJson<String>(json['profileId']),
      collectibleId: serializer.fromJson<String>(json['collectibleId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'collectibleId': serializer.toJson<String>(collectibleId),
    };
  }

  CollectionEntryRow copyWith({String? profileId, String? collectibleId}) =>
      CollectionEntryRow(
        profileId: profileId ?? this.profileId,
        collectibleId: collectibleId ?? this.collectibleId,
      );
  CollectionEntryRow copyWithCompanion(CollectionEntriesCompanion data) {
    return CollectionEntryRow(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      collectibleId: data.collectibleId.present
          ? data.collectibleId.value
          : this.collectibleId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionEntryRow(')
          ..write('profileId: $profileId, ')
          ..write('collectibleId: $collectibleId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(profileId, collectibleId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionEntryRow &&
          other.profileId == this.profileId &&
          other.collectibleId == this.collectibleId);
}

class CollectionEntriesCompanion extends UpdateCompanion<CollectionEntryRow> {
  final Value<String> profileId;
  final Value<String> collectibleId;
  final Value<int> rowid;
  const CollectionEntriesCompanion({
    this.profileId = const Value.absent(),
    this.collectibleId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionEntriesCompanion.insert({
    required String profileId,
    required String collectibleId,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       collectibleId = Value(collectibleId);
  static Insertable<CollectionEntryRow> custom({
    Expression<String>? profileId,
    Expression<String>? collectibleId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (collectibleId != null) 'collectible_id': collectibleId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionEntriesCompanion copyWith({
    Value<String>? profileId,
    Value<String>? collectibleId,
    Value<int>? rowid,
  }) {
    return CollectionEntriesCompanion(
      profileId: profileId ?? this.profileId,
      collectibleId: collectibleId ?? this.collectibleId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (collectibleId.present) {
      map['collectible_id'] = Variable<String>(collectibleId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionEntriesCompanion(')
          ..write('profileId: $profileId, ')
          ..write('collectibleId: $collectibleId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $StoryProgressEntriesTable storyProgressEntries =
      $StoryProgressEntriesTable(this);
  late final $WordHelpRecordsTable wordHelpRecords = $WordHelpRecordsTable(
    this,
  );
  late final $TwisterProgressEntriesTable twisterProgressEntries =
      $TwisterProgressEntriesTable(this);
  late final $CollectionEntriesTable collectionEntries =
      $CollectionEntriesTable(this);
  late final ProfilesDao profilesDao = ProfilesDao(this as AppDatabase);
  late final StoryProgressDao storyProgressDao = StoryProgressDao(
    this as AppDatabase,
  );
  late final WordHelpDao wordHelpDao = WordHelpDao(this as AppDatabase);
  late final TwisterProgressDao twisterProgressDao = TwisterProgressDao(
    this as AppDatabase,
  );
  late final CollectionDao collectionDao = CollectionDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    profiles,
    storyProgressEntries,
    wordHelpRecords,
    twisterProgressEntries,
    collectionEntries,
  ];
}

typedef $$ProfilesTableCreateCompanionBuilder =
    ProfilesCompanion Function({
      required String localId,
      required String displayName,
      required AgeBand ageBand,
      required String currentLevelId,
      required bool micConsent,
      required bool cloudAsrConsent,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ProfilesTableUpdateCompanionBuilder =
    ProfilesCompanion Function({
      Value<String> localId,
      Value<String> displayName,
      Value<AgeBand> ageBand,
      Value<String> currentLevelId,
      Value<bool> micConsent,
      Value<bool> cloudAsrConsent,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AgeBand, AgeBand, int> get ageBand =>
      $composableBuilder(
        column: $table.ageBand,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get currentLevelId => $composableBuilder(
    column: $table.currentLevelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get micConsent => $composableBuilder(
    column: $table.micConsent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get cloudAsrConsent => $composableBuilder(
    column: $table.cloudAsrConsent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ageBand => $composableBuilder(
    column: $table.ageBand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentLevelId => $composableBuilder(
    column: $table.currentLevelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get micConsent => $composableBuilder(
    column: $table.micConsent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cloudAsrConsent => $composableBuilder(
    column: $table.cloudAsrConsent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<AgeBand, int> get ageBand =>
      $composableBuilder(column: $table.ageBand, builder: (column) => column);

  GeneratedColumn<String> get currentLevelId => $composableBuilder(
    column: $table.currentLevelId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get micConsent => $composableBuilder(
    column: $table.micConsent,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get cloudAsrConsent => $composableBuilder(
    column: $table.cloudAsrConsent,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfilesTable,
          ProfileRow,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (
            ProfileRow,
            BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>,
          ),
          ProfileRow,
          PrefetchHooks Function()
        > {
  $$ProfilesTableTableManager(_$AppDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<AgeBand> ageBand = const Value.absent(),
                Value<String> currentLevelId = const Value.absent(),
                Value<bool> micConsent = const Value.absent(),
                Value<bool> cloudAsrConsent = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion(
                localId: localId,
                displayName: displayName,
                ageBand: ageBand,
                currentLevelId: currentLevelId,
                micConsent: micConsent,
                cloudAsrConsent: cloudAsrConsent,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                required String displayName,
                required AgeBand ageBand,
                required String currentLevelId,
                required bool micConsent,
                required bool cloudAsrConsent,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion.insert(
                localId: localId,
                displayName: displayName,
                ageBand: ageBand,
                currentLevelId: currentLevelId,
                micConsent: micConsent,
                cloudAsrConsent: cloudAsrConsent,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfilesTable,
      ProfileRow,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (ProfileRow, BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>),
      ProfileRow,
      PrefetchHooks Function()
    >;
typedef $$StoryProgressEntriesTableCreateCompanionBuilder =
    StoryProgressEntriesCompanion Function({
      required String profileId,
      required String storyId,
      required StoryStatus status,
      Value<DateTime?> completedAt,
      required int timesRead,
      Value<int> rowid,
    });
typedef $$StoryProgressEntriesTableUpdateCompanionBuilder =
    StoryProgressEntriesCompanion Function({
      Value<String> profileId,
      Value<String> storyId,
      Value<StoryStatus> status,
      Value<DateTime?> completedAt,
      Value<int> timesRead,
      Value<int> rowid,
    });

class $$StoryProgressEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $StoryProgressEntriesTable> {
  $$StoryProgressEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storyId => $composableBuilder(
    column: $table.storyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<StoryStatus, StoryStatus, int> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timesRead => $composableBuilder(
    column: $table.timesRead,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoryProgressEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $StoryProgressEntriesTable> {
  $$StoryProgressEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storyId => $composableBuilder(
    column: $table.storyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timesRead => $composableBuilder(
    column: $table.timesRead,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoryProgressEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoryProgressEntriesTable> {
  $$StoryProgressEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get storyId =>
      $composableBuilder(column: $table.storyId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<StoryStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timesRead =>
      $composableBuilder(column: $table.timesRead, builder: (column) => column);
}

class $$StoryProgressEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StoryProgressEntriesTable,
          StoryProgressRow,
          $$StoryProgressEntriesTableFilterComposer,
          $$StoryProgressEntriesTableOrderingComposer,
          $$StoryProgressEntriesTableAnnotationComposer,
          $$StoryProgressEntriesTableCreateCompanionBuilder,
          $$StoryProgressEntriesTableUpdateCompanionBuilder,
          (
            StoryProgressRow,
            BaseReferences<
              _$AppDatabase,
              $StoryProgressEntriesTable,
              StoryProgressRow
            >,
          ),
          StoryProgressRow,
          PrefetchHooks Function()
        > {
  $$StoryProgressEntriesTableTableManager(
    _$AppDatabase db,
    $StoryProgressEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoryProgressEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoryProgressEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StoryProgressEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> storyId = const Value.absent(),
                Value<StoryStatus> status = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> timesRead = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoryProgressEntriesCompanion(
                profileId: profileId,
                storyId: storyId,
                status: status,
                completedAt: completedAt,
                timesRead: timesRead,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String storyId,
                required StoryStatus status,
                Value<DateTime?> completedAt = const Value.absent(),
                required int timesRead,
                Value<int> rowid = const Value.absent(),
              }) => StoryProgressEntriesCompanion.insert(
                profileId: profileId,
                storyId: storyId,
                status: status,
                completedAt: completedAt,
                timesRead: timesRead,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoryProgressEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StoryProgressEntriesTable,
      StoryProgressRow,
      $$StoryProgressEntriesTableFilterComposer,
      $$StoryProgressEntriesTableOrderingComposer,
      $$StoryProgressEntriesTableAnnotationComposer,
      $$StoryProgressEntriesTableCreateCompanionBuilder,
      $$StoryProgressEntriesTableUpdateCompanionBuilder,
      (
        StoryProgressRow,
        BaseReferences<
          _$AppDatabase,
          $StoryProgressEntriesTable,
          StoryProgressRow
        >,
      ),
      StoryProgressRow,
      PrefetchHooks Function()
    >;
typedef $$WordHelpRecordsTableCreateCompanionBuilder =
    WordHelpRecordsCompanion Function({
      required String profileId,
      required String wordText,
      required int encounterCount,
      required int helpCount,
      required HelpLevel lastHelpLevel,
      Value<int> rowid,
    });
typedef $$WordHelpRecordsTableUpdateCompanionBuilder =
    WordHelpRecordsCompanion Function({
      Value<String> profileId,
      Value<String> wordText,
      Value<int> encounterCount,
      Value<int> helpCount,
      Value<HelpLevel> lastHelpLevel,
      Value<int> rowid,
    });

class $$WordHelpRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $WordHelpRecordsTable> {
  $$WordHelpRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordText => $composableBuilder(
    column: $table.wordText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get encounterCount => $composableBuilder(
    column: $table.encounterCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get helpCount => $composableBuilder(
    column: $table.helpCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<HelpLevel, HelpLevel, int> get lastHelpLevel =>
      $composableBuilder(
        column: $table.lastHelpLevel,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$WordHelpRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $WordHelpRecordsTable> {
  $$WordHelpRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordText => $composableBuilder(
    column: $table.wordText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get encounterCount => $composableBuilder(
    column: $table.encounterCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get helpCount => $composableBuilder(
    column: $table.helpCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastHelpLevel => $composableBuilder(
    column: $table.lastHelpLevel,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WordHelpRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WordHelpRecordsTable> {
  $$WordHelpRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get wordText =>
      $composableBuilder(column: $table.wordText, builder: (column) => column);

  GeneratedColumn<int> get encounterCount => $composableBuilder(
    column: $table.encounterCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get helpCount =>
      $composableBuilder(column: $table.helpCount, builder: (column) => column);

  GeneratedColumnWithTypeConverter<HelpLevel, int> get lastHelpLevel =>
      $composableBuilder(
        column: $table.lastHelpLevel,
        builder: (column) => column,
      );
}

class $$WordHelpRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WordHelpRecordsTable,
          WordHelpRow,
          $$WordHelpRecordsTableFilterComposer,
          $$WordHelpRecordsTableOrderingComposer,
          $$WordHelpRecordsTableAnnotationComposer,
          $$WordHelpRecordsTableCreateCompanionBuilder,
          $$WordHelpRecordsTableUpdateCompanionBuilder,
          (
            WordHelpRow,
            BaseReferences<_$AppDatabase, $WordHelpRecordsTable, WordHelpRow>,
          ),
          WordHelpRow,
          PrefetchHooks Function()
        > {
  $$WordHelpRecordsTableTableManager(
    _$AppDatabase db,
    $WordHelpRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WordHelpRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WordHelpRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WordHelpRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> wordText = const Value.absent(),
                Value<int> encounterCount = const Value.absent(),
                Value<int> helpCount = const Value.absent(),
                Value<HelpLevel> lastHelpLevel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WordHelpRecordsCompanion(
                profileId: profileId,
                wordText: wordText,
                encounterCount: encounterCount,
                helpCount: helpCount,
                lastHelpLevel: lastHelpLevel,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String wordText,
                required int encounterCount,
                required int helpCount,
                required HelpLevel lastHelpLevel,
                Value<int> rowid = const Value.absent(),
              }) => WordHelpRecordsCompanion.insert(
                profileId: profileId,
                wordText: wordText,
                encounterCount: encounterCount,
                helpCount: helpCount,
                lastHelpLevel: lastHelpLevel,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WordHelpRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WordHelpRecordsTable,
      WordHelpRow,
      $$WordHelpRecordsTableFilterComposer,
      $$WordHelpRecordsTableOrderingComposer,
      $$WordHelpRecordsTableAnnotationComposer,
      $$WordHelpRecordsTableCreateCompanionBuilder,
      $$WordHelpRecordsTableUpdateCompanionBuilder,
      (
        WordHelpRow,
        BaseReferences<_$AppDatabase, $WordHelpRecordsTable, WordHelpRow>,
      ),
      WordHelpRow,
      PrefetchHooks Function()
    >;
typedef $$TwisterProgressEntriesTableCreateCompanionBuilder =
    TwisterProgressEntriesCompanion Function({
      required String profileId,
      required String twisterId,
      required int timesCompleted,
      Value<int> rowid,
    });
typedef $$TwisterProgressEntriesTableUpdateCompanionBuilder =
    TwisterProgressEntriesCompanion Function({
      Value<String> profileId,
      Value<String> twisterId,
      Value<int> timesCompleted,
      Value<int> rowid,
    });

class $$TwisterProgressEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $TwisterProgressEntriesTable> {
  $$TwisterProgressEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get twisterId => $composableBuilder(
    column: $table.twisterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timesCompleted => $composableBuilder(
    column: $table.timesCompleted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TwisterProgressEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $TwisterProgressEntriesTable> {
  $$TwisterProgressEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get twisterId => $composableBuilder(
    column: $table.twisterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timesCompleted => $composableBuilder(
    column: $table.timesCompleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TwisterProgressEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TwisterProgressEntriesTable> {
  $$TwisterProgressEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get twisterId =>
      $composableBuilder(column: $table.twisterId, builder: (column) => column);

  GeneratedColumn<int> get timesCompleted => $composableBuilder(
    column: $table.timesCompleted,
    builder: (column) => column,
  );
}

class $$TwisterProgressEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TwisterProgressEntriesTable,
          TwisterProgressRow,
          $$TwisterProgressEntriesTableFilterComposer,
          $$TwisterProgressEntriesTableOrderingComposer,
          $$TwisterProgressEntriesTableAnnotationComposer,
          $$TwisterProgressEntriesTableCreateCompanionBuilder,
          $$TwisterProgressEntriesTableUpdateCompanionBuilder,
          (
            TwisterProgressRow,
            BaseReferences<
              _$AppDatabase,
              $TwisterProgressEntriesTable,
              TwisterProgressRow
            >,
          ),
          TwisterProgressRow,
          PrefetchHooks Function()
        > {
  $$TwisterProgressEntriesTableTableManager(
    _$AppDatabase db,
    $TwisterProgressEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TwisterProgressEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$TwisterProgressEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TwisterProgressEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> twisterId = const Value.absent(),
                Value<int> timesCompleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TwisterProgressEntriesCompanion(
                profileId: profileId,
                twisterId: twisterId,
                timesCompleted: timesCompleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String twisterId,
                required int timesCompleted,
                Value<int> rowid = const Value.absent(),
              }) => TwisterProgressEntriesCompanion.insert(
                profileId: profileId,
                twisterId: twisterId,
                timesCompleted: timesCompleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TwisterProgressEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TwisterProgressEntriesTable,
      TwisterProgressRow,
      $$TwisterProgressEntriesTableFilterComposer,
      $$TwisterProgressEntriesTableOrderingComposer,
      $$TwisterProgressEntriesTableAnnotationComposer,
      $$TwisterProgressEntriesTableCreateCompanionBuilder,
      $$TwisterProgressEntriesTableUpdateCompanionBuilder,
      (
        TwisterProgressRow,
        BaseReferences<
          _$AppDatabase,
          $TwisterProgressEntriesTable,
          TwisterProgressRow
        >,
      ),
      TwisterProgressRow,
      PrefetchHooks Function()
    >;
typedef $$CollectionEntriesTableCreateCompanionBuilder =
    CollectionEntriesCompanion Function({
      required String profileId,
      required String collectibleId,
      Value<int> rowid,
    });
typedef $$CollectionEntriesTableUpdateCompanionBuilder =
    CollectionEntriesCompanion Function({
      Value<String> profileId,
      Value<String> collectibleId,
      Value<int> rowid,
    });

class $$CollectionEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionEntriesTable> {
  $$CollectionEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectibleId => $composableBuilder(
    column: $table.collectibleId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CollectionEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionEntriesTable> {
  $$CollectionEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectibleId => $composableBuilder(
    column: $table.collectibleId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionEntriesTable> {
  $$CollectionEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get collectibleId => $composableBuilder(
    column: $table.collectibleId,
    builder: (column) => column,
  );
}

class $$CollectionEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionEntriesTable,
          CollectionEntryRow,
          $$CollectionEntriesTableFilterComposer,
          $$CollectionEntriesTableOrderingComposer,
          $$CollectionEntriesTableAnnotationComposer,
          $$CollectionEntriesTableCreateCompanionBuilder,
          $$CollectionEntriesTableUpdateCompanionBuilder,
          (
            CollectionEntryRow,
            BaseReferences<
              _$AppDatabase,
              $CollectionEntriesTable,
              CollectionEntryRow
            >,
          ),
          CollectionEntryRow,
          PrefetchHooks Function()
        > {
  $$CollectionEntriesTableTableManager(
    _$AppDatabase db,
    $CollectionEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> collectibleId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionEntriesCompanion(
                profileId: profileId,
                collectibleId: collectibleId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String collectibleId,
                Value<int> rowid = const Value.absent(),
              }) => CollectionEntriesCompanion.insert(
                profileId: profileId,
                collectibleId: collectibleId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CollectionEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionEntriesTable,
      CollectionEntryRow,
      $$CollectionEntriesTableFilterComposer,
      $$CollectionEntriesTableOrderingComposer,
      $$CollectionEntriesTableAnnotationComposer,
      $$CollectionEntriesTableCreateCompanionBuilder,
      $$CollectionEntriesTableUpdateCompanionBuilder,
      (
        CollectionEntryRow,
        BaseReferences<
          _$AppDatabase,
          $CollectionEntriesTable,
          CollectionEntryRow
        >,
      ),
      CollectionEntryRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$StoryProgressEntriesTableTableManager get storyProgressEntries =>
      $$StoryProgressEntriesTableTableManager(_db, _db.storyProgressEntries);
  $$WordHelpRecordsTableTableManager get wordHelpRecords =>
      $$WordHelpRecordsTableTableManager(_db, _db.wordHelpRecords);
  $$TwisterProgressEntriesTableTableManager get twisterProgressEntries =>
      $$TwisterProgressEntriesTableTableManager(
        _db,
        _db.twisterProgressEntries,
      );
  $$CollectionEntriesTableTableManager get collectionEntries =>
      $$CollectionEntriesTableTableManager(_db, _db.collectionEntries);
}
