# Drift: Context & Developer Guide

**Drift** is a reactive persistence library for Dart and Flutter applications, primarily built on top of SQLite (with experimental support for PostgreSQL/MariaDB). It provides type-safe SQL, auto-updating stream queries, migrations, and cross-platform support (Mobile, Desktop, Web).

## 1. Setup & Code Generation

Drift relies heavily on code generation. You define your schema and queries, and Drift generates the boilerplate.

**Dependencies (`pubspec.yaml`):**
```yaml
dependencies:
  drift: ^latest
  drift_flutter: ^latest # For Flutter apps (handles sqlite3 bundling)
  path_provider: ^latest

dev_dependencies:
  drift_dev: ^latest
  build_runner: ^latest
```

**Code Generation Command:**
```bash
dart run build_runner build --delete-conflicting-outputs
# Or use `watch` during development
```

## 2. Defining the Schema (Dart API)

Tables are defined as Dart classes extending `Table`. Columns are defined using `late final` getters.

```dart
import 'package:drift/drift.dart';

// Generates a data class called `TodoItem` and a companion `TodoItemsCompanion`
class TodoItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 6, max: 32)();
  TextColumn get content => text().named('body')(); // Custom SQL name
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get description => text()();
}
```

**Column Types & Modifiers:**
*   **Types:** `integer()`, `int64()` (BigInt), `text()`, `boolean()`, `real()` (double), `blob()` (Uint8List), `dateTime()`.
*   **Modifiers:** `.nullable()`, `.autoIncrement()`, `.withDefault()`, `.clientDefault()`, `.references()`, `.unique()`, `.check()`.

## 3. The Database Class

The central hub for your database. It ties tables together and configures the connection.

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart'; // Generated file

@DriftDatabase(tables: [TodoItems, Categories])
class AppDatabase extends _$AppDatabase {
  // Use drift_flutter's helper to open the database in a background isolate
  AppDatabase() : super(driftDatabase(name: 'my_database'));

  @override
  int get schemaVersion => 1;
}
```

## 4. Querying Data

Drift provides three main ways to query data: The **Manager API** (easiest), the **Core Dart API** (flexible), and the **SQL API** (raw SQL).

### A. The Manager API (Recommended for standard CRUD)
Drift automatically generates a `managers` getter on your database class for simplified querying.

```dart
// SELECT
final allTodos = await db.managers.todoItems.get();
final pendingTodos = await db.managers.todoItems.filter((f) => f.isDone(false)).get();

// WATCH (Reactive Stream)
Stream<List<TodoItem>> watchTodos = db.managers.todoItems.watch();

// INSERT
final newId = await db.managers.todoItems.create(
  (o) => o(title: 'Buy milk', content: '2% milk'),
);

// UPDATE
await db.managers.todoItems.filter((f) => f.id(1)).update((o) => o(isDone: Value(true)));

// DELETE
await db.managers.todoItems.filter((f) => f.id(1)).delete();

// RELATIONS (Prefetching)
final todosWithCategories = await db.managers.todoItems.withReferences((pref) => pref.category);
```

### B. Core Dart API & Companions
For more complex queries (Joins, Group By) or when you need explicit control.

**Companions:** Used for Inserts and Updates. They wrap values in `Value<T>` to distinguish between `NULL` (set to null) and `Value.absent()` (do not update / use default).

```dart
// INSERT
await db.into(db.todoItems).insert(
  TodoItemsCompanion.insert(
    title: 'Learn Drift',
    content: 'Read the docs',
    // id and createdAt are absent by default (auto-generated)
  ),
);

// UPDATE
await (db.update(db.todoItems)..where((t) => t.id.equals(1)))
    .write(const TodoItemsCompanion(isDone: Value(true)));

// SELECT with JOIN
final query = db.select(db.todoItems).join([
  leftOuterJoin(db.categories, db.categories.id.equalsExp(db.todoItems.categoryId)),
]);
final results = await query.map((row) {
  return TodoWithCategory(
    todo: row.readTable(db.todoItems),
    category: row.readTableOrNull(db.categories),
  );
}).get();
```

### C. SQL API (`.drift` files)
You can write pure SQL in `.drift` files. Drift analyzes it at compile time and generates type-safe Dart methods.

```sql
-- tables.drift
CREATE TABLE users (
    id INTEGER NOT NULL PRIMARY KEY,
    name TEXT NOT NULL
);

-- Named query: Drift generates a method `findUsers(String name)`
findUsers: SELECT * FROM users WHERE name LIKE ?;
```
Include it in your database: `@DriftDatabase(include: {'tables.drift'})`.

## 5. Migrations

Drift has powerful migration tooling. Never write manual `ALTER TABLE` statements if you can avoid it.

**1. Generate Migrations:**
When you change your schema, bump `schemaVersion` and run:
```bash
dart run drift_dev make-migrations
```
This generates a `database.steps.dart` file containing snapshots of your schema.

**2. Apply Migrations:**
Use the generated `stepByStep` helper in your database class:

```dart
import 'database.steps.dart';

@override
MigrationStrategy get migration {
  return MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.addColumn(schema.todoItems, schema.todoItems.dueDate);
      },
      from2To3: (m, schema) async {
        // Complex migrations (e.g., changing column types)
        await m.alterTable(TableMigration(schema.todoItems));
      }
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
```

## 6. Type Converters

Store complex Dart objects (like JSON, Enums, or custom classes) in standard SQL columns.

```dart
// 1. Define the converter (Use JsonTypeConverter2 for JSON serialization support)
class PreferencesConverter extends TypeConverter<Preferences, String> {
  const PreferencesConverter();
  @override
  Preferences fromSql(String fromDb) => Preferences.fromJson(json.decode(fromDb));
  @override
  String toSql(Preferences value) => json.encode(value.toJson());
}

// 2. Apply to a column
TextColumn get preferences => text().map(const PreferencesConverter())();

// Built-in Enum Converter:
IntColumn get status => intEnum<TaskStatus>()(); // Stores enum as integer index
TextColumn get statusName => textEnum<TaskStatus>()(); // Stores enum as string
```

## 7. Advanced Features

### Isolates (Background Execution)
SQLite is synchronous. To prevent UI jank, Drift can run the database in a background isolate.
*   **Flutter:** `driftDatabase(name: 'db')` from `drift_flutter` handles this automatically.
*   **Dart/Native:** Use `NativeDatabase.createInBackground(file)`.

### Web Support (WASM)
Drift supports the web via a custom SQLite WASM build, utilizing OPFS (Origin-Private File System) or IndexedDB.
1.  Place `sqlite3.wasm` and `drift_worker.dart.js` in your `web/` directory.
2.  Serve with COOP/COEP headers for maximum performance (OPFS).
3.  Use `WasmDatabase.open()` to connect.

### Transactions & Batches
```dart
// Transaction (Atomic)
await db.transaction(() async {
  await db.into(db.categories).insert(cat);
  await db.into(db.todoItems).insert(todo);
});

// Batch (Optimized bulk inserts/updates)
await db.batch((batch) {
  batch.insertAll(db.todoItems, [companion1, companion2]);
});
```

### Custom Row Classes
By default, Drift generates data classes (e.g., `TodoItem`). You can use your own classes or Dart Records:
```dart
@UseRowClass(MyCustomClass)
TextColumn get title => text()();

@UseRowClass(Record, constructor: 'fromDb') // Use a specific constructor
```

## 8. Common Pitfalls & Rules

1.  **Always `await` inside transactions:** Failing to `await` a query inside a `db.transaction()` block will cause it to execute outside the transaction or crash.
2.  **Companions vs. Data Classes:** Use Data Classes (e.g., `TodoItem`) for *reading* data. Use Companions (e.g., `TodoItemsCompanion`) for *inserting/updating* data.
3.  **Value.absent() vs Value(null):** In a Companion, `Value.absent()` means "do not touch this column" (useful for defaults or partial updates). `Value(null)` means "explicitly set this column to SQL NULL".
4.  **Stream Behavior:** Any query ending in `.watch()` or `.watchSingle()` returns a `Stream` that automatically emits new data whenever the underlying tables change.
5.  **DateTime Storage:** By default, Drift stores `DateTime` as Unix timestamps (integers). It is highly recommended to set `store_date_time_values_as_text: true` in `build.yaml` to store them as ISO-8601 strings for better timezone support.
