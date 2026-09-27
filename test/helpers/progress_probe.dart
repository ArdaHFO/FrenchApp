import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One-shot gate BEFORE SQL submission. No SQLite transaction is held or
/// bypassed; all real transactions and their executors remain the delegate's.
class OperationGate {
  final Completer<void> entered = Completer<void>();
  final Completer<void> released = Completer<void>();
  bool _used = false;

  Future<void> wait() async {
    if (_used) return;
    _used = true;
    entered.complete();
    await released.future;
  }

  void release() {
    if (!released.isCompleted) released.complete();
  }
}

class ProbeDatabase implements Database {
  ProbeDatabase(this.delegate);
  final Database delegate;
  String? gatedInsertTable;
  OperationGate? insertGate;
  OperationGate? transactionGate;
  void Function(String table)? onInsertCommitted;
  void Function()? onTransactionCommitted;
  bool rejectReads = false;
  Future<void> Function(String table)? afterTransactionRead;
  String? failTransactionReadTable;
  final List<String> events = <String>[];

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == gatedInsertTable && insertGate != null) {
      events.add('$table.before_dispatch');
      await insertGate!.wait();
    }
    final int result = await delegate.insert(table, values,
        nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
    events.add('$table.committed');
    onInsertCommitted?.call(table);
    return result;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) async {
    if (transactionGate != null) {
      events.add('transaction.before_begin');
      await transactionGate!.wait();
    }
    // Pass the REAL transaction executor, including SQLite serialization,
    // rollback and commit. Never dispatch transaction statements via Database.
    final T result = await delegate.transaction((txn) => action(
        afterTransactionRead == null && failTransactionReadTable == null
            ? txn : ReadProbeTransaction(txn, afterTransactionRead, failTransactionReadTable)), exclusive: exclusive);
    events.add('transaction.committed');
    onTransactionCommitted?.call();
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    if (rejectReads) throw StateError('UNEXPECTED_POST_COMMIT_READ');
    return delegate.query(table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? arguments]) =>
      delegate.rawQuery(sql, arguments);
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      delegate.execute(sql, arguments);
  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      delegate.update(table, values,
          where: where,
          whereArgs: whereArgs,
          conflictAlgorithm: conflictAlgorithm);
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      delegate.delete(table, where: where, whereArgs: whereArgs);
  @override
  String get path => delegate.path;
  @override
  bool get isOpen => delegate.isOpen;
  @override
  Database get database => this;
  @override
  Future<void> close() async {
    events.add('close.begin');
    await delegate.close();
    events.add('close.done');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// All SQL still goes through the real SQLite transaction. The observation
/// happens after a read and may delay return, never release the transaction.
class ReadProbeTransaction implements Transaction {
  ReadProbeTransaction(this.delegate, this.afterRead, this.failTable);
  final Transaction delegate;
  final Future<void> Function(String)? afterRead;
  final String? failTable;

  @override
  Future<List<Map<String, Object?>>> query(String table, {
    bool? distinct, List<String>? columns, String? where,
    List<Object?>? whereArgs, String? groupBy, String? having,
    String? orderBy, int? limit, int? offset,
  }) async {
    if (table == failTable) {
      // A genuine SQLite DatabaseException on the same transaction executor.
      return delegate.rawQuery('SELECT * FROM fa006c_injected_missing_table');
    }
    final rows = await delegate.query(table, distinct: distinct,
        columns: columns, where: where, whereArgs: whereArgs,
        groupBy: groupBy, having: having, orderBy: orderBy,
        limit: limit, offset: offset);
    await afterRead?.call(table);
    return rows;
  }

  @override
  Database get database => delegate.database;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
