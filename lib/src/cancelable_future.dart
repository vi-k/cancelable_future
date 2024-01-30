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

final class AsyncCancelByTimeoutException extends AsyncCancelException {
  final Duration timeout;

  const AsyncCancelByTimeoutException(this.timeout);

  @override
  String toString() => 'Async operation canceled by timeout: $timeout';
}

final class CancelableFuture<T> implements Future<T> {
  final Future<T> Function() computation;
  late final Future<T> _future;
  var _isCanceled = false;
  late final StackTrace _canceledStackTrace;
  final _onErrorCallbacks = Queue<Function>();
  final _timers = <Timer>{};

  CancelableFuture(this.computation) {
    final zoneSpecification = ZoneSpecification(
      createTimer: (self, parent, zone, duration, f) {
        late final Timer timer;

        timer = parent.createTimer(self, duration, () {
          _timers.remove(timer);
          f();
        });

        _timers.add(timer);

        return timer;
      },
      createPeriodicTimer: (self, parent, zone, period, f) {
        final timer = parent.createPeriodicTimer(self, period, f);
        _timers.add(timer);

        return timer;
      },
    );

    runZoned(
      zoneSpecification: zoneSpecification,
      () {
        _future = computation();
      },
    );
  }

  @visibleForTesting
  Future<T> get $future => _future;

  bool get isCanceled => _isCanceled;

  bool get isCompleted => isDone && !_isCanceled;

  bool get isDone => _timers.isEmpty;

  void cancel({
    AsyncCancelException token = const AsyncCancelException(),
  }) {
    if (isDone) {
      return;
    }

    if (!isDone) {
      _log(() => 'cancel() timers=${_timers.length}');

      _isCanceled = true;
      final stackTrace = _canceledStackTrace = StackTrace.current;

      for (final timer in _timers) {
        timer.cancel();
      }
      _timers.clear();

      _breakFuture(
        token: token,
        stackTrace: stackTrace,
      );
    }
  }

  void _breakFuture({
    AsyncCancelException token = const AsyncCancelException(),
    required StackTrace stackTrace,
  }) {
    _log(() => '_breakFuture() callbacks=${_onErrorCallbacks.length}');

    while (_onErrorCallbacks.isNotEmpty) {
      final onError = _onErrorCallbacks.removeFirst();
      onError(token, stackTrace);
    }
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    _log('then');

    if (onError != null) {
      _onErrorCallbacks.add(onError);
    }

    if (_isCanceled) {
      _breakFuture(stackTrace: _canceledStackTrace);
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

    assert(
      onTimeout == null,
      'When cancelOnTimeout is set to true, onTimeout must be null',
    );

    final completer = Completer<T>();
    final timer = Timer(
      timeLimit,
      () {
        cancel(token: AsyncCancelByTimeoutException(timeLimit));
      },
    );

    then<void>(
      (value) {
        timer.cancel();
        completer.complete(value);
      },
      // ignore: avoid_types_on_closure_parameters
      onError: (Object error, StackTrace stackTrace) {
        timer.cancel();
        completer.completeError(error, stackTrace);
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
