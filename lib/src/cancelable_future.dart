import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

// const _printLog = true;
const _printLog = false;

const void Function(Object message) _log =
    _printLog ? _logEnabled : _logDisabled;

void _logDisabled(Object message) {}

void _logEnabled(Object message) {
  print('* ${message is Function ? message() : message}');
}

base class AsyncCancelException implements Exception {
  const AsyncCancelException();

  @override
  String toString() => 'Async operation canceled';
}

final class _InnerAsyncCancelException extends AsyncCancelException {
  const _InnerAsyncCancelException();
}

final class AsyncCancelByTimeoutException extends AsyncCancelException {
  final Duration timeout;

  const AsyncCancelByTimeoutException(this.timeout);

  @override
  String toString() => 'Async operation canceled by timeout: $timeout';
}

final class CancelableFuture<T> implements Future<T> {
  final Future<T> Function() computation;
  late final Future<T> _future;
  AsyncCancelException? _canceledToken;
  late final StackTrace _canceledStackTrace;
  final _onErrorCallbacks = Queue<Function>();
  final _timers = <Timer, void Function()>{};

  CancelableFuture(this.computation) {
    final zoneSpecification = ZoneSpecification(
      createTimer: (self, parent, zone, duration, f) {
        late final Timer timer;

        if (isCanceled) {
          throw const _InnerAsyncCancelException();
        }

        _log('createTimer');
        timer = parent.createTimer(zone, duration, () {
          _timers.remove(timer);
          f();
        });

        _timers[timer] = f;

        return timer;
      },
      createPeriodicTimer: (self, parent, zone, period, f) {
        _log('createPeriodicTimer');
        final timer = parent.createPeriodicTimer(zone, period, f);
        _timers[timer] = () => f(timer);

        return timer;
      },
    );

    runZonedGuarded(zoneSpecification: zoneSpecification, () {
      _future = computation();
    }, (error, stack) {
      if (error is! _InnerAsyncCancelException) {
        Error.throwWithStackTrace(error, stack);
      }
    });
  }

  @visibleForTesting
  Future<T> get $future => _future;

  bool get isCanceled => _canceledToken != null;

  bool get isCompleted => isDone && !isCanceled;

  bool get isDone => _timers.isEmpty;

  Future<void> cancel({
    AsyncCancelException token = const AsyncCancelException(),
  }) async {
    if (isDone) {
      return;
    }

    if (!isDone) {
      _log(() => 'cancel($token) timers=${_timers.length}');

      _canceledToken = token;
      final stackTrace = _canceledStackTrace = StackTrace.current;

      for (final MapEntry(key: timer, value: f) in _timers.entries.toList()) {
        final isActive = timer.isActive;
        timer.cancel();
        if (isActive) {
          f();
        }
      }
      _timers.clear();

      await _breakFuture(
        token: token,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _breakFuture({
    AsyncCancelException token = const AsyncCancelException(),
    required StackTrace stackTrace,
  }) async {
    _log(() => '_breakFuture($token) callbacks=${_onErrorCallbacks.length}');

    while (_onErrorCallbacks.isNotEmpty) {
      final onError = _onErrorCallbacks.removeFirst();
      await onError(token, stackTrace);
    }
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) async {
    _log('then');

    if (onError != null) {
      _onErrorCallbacks.add(onError);
    }

    if (isCanceled) {
      await _breakFuture(
        token: _canceledToken!,
        stackTrace: _canceledStackTrace,
      );
      return Completer<T>().future.then(onValue); // never completer
    }

    return _future.then(
      (value) {
        _onErrorCallbacks.remove(onError);
        return onValue(value);
      },
      onError: onError,
    );
  }

  @override
  Future<T> timeout(
    Duration timeLimit, {
    FutureOr<T> Function()? onTimeout,
    bool cancelOnTimeout = false,
  }) {
    if (!cancelOnTimeout) {
      return _future.timeout(timeLimit, onTimeout: onTimeout);
    }

    final completer = Completer<T>();
    void Function()? completerCallback;

    final timer = Timer(
      timeLimit,
      () {
        _log('timeout');

        final token = AsyncCancelByTimeoutException(timeLimit);

        if (onTimeout != null) {
          try {
            final result = onTimeout();
            completerCallback = () => completer.complete(result);
          } on Object catch (e, s) {
            completerCallback = () => completer.completeError(e, s);
          }
        } else {
          completerCallback =
              () => completer.completeError(token, StackTrace.current);
        }

        cancel(token: token);
      },
    );

    then<void>(
      (value) {
        timer.cancel();
        if (completerCallback != null) {
          completerCallback!();
        } else {
          completer.complete(value);
        }
      },
      // ignore: avoid_types_on_closure_parameters
      onError: (Object error, StackTrace stackTrace) {
        timer.cancel();
        if (completerCallback != null) {
          completerCallback!();
        } else {
          completer.completeError(error, stackTrace);
        }
      },
    );

    return completer.future;
  }

  Future<T?> get orNull async {
    try {
      return await this;
    } on AsyncCancelException {
      return null;
    }
  }

  Future<T> onCancel(FutureOr<T> Function() onCancel) async {
    try {
      return await this;
    } on AsyncCancelException {
      return onCancel();
    }
  }

  @override
  Stream<T> asStream() => _future.asStream();

  @override
  Future<T> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) =>
      _future.catchError(onError, test: test);

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);
}
