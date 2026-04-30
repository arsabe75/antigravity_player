import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

/// Tabla genérica para sustituir SharedPreferences
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Tabla para el historial de videos recientes
class RecentVideos extends Table {
  TextColumn get path => text()();
  TextColumn get title => text().nullable()();
  BoolColumn get isNetwork => boolean().withDefault(const Constant(false))();
  BoolColumn get isTelegram => boolean().withDefault(const Constant(false))();
  DateTimeColumn get playedAt => dateTime()();
  IntColumn get lastPosition => integer().nullable()();

  // Telegram-specific identifiers
  IntColumn get telegramChatId => integer().nullable()();
  IntColumn get telegramMessageId => integer().nullable()();
  IntColumn get telegramFileSize => integer().nullable()();
  IntColumn get telegramTopicId => integer().nullable()();
  TextColumn get telegramTopicName => text().nullable()();

  @override
  Set<Column> get primaryKey => {path};
}

@DriftDatabase(tables: [AppSettings, RecentVideos])
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? e}) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(recentVideos);
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  // Inicialización de SQLite
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'antigravity_player', 'app_database.sqlite'));
    
    // Directorio contenedor
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    
    return NativeDatabase.createInBackground(file);
  });
}
