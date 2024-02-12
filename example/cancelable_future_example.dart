import 'dart:async';

import 'package:cancelable_future/cancelable_future.dart';
import 'package:stack_trace/stack_trace.dart';

import '../test/gc.dart';

// const printStackTrace = true;
const printStackTrace = false;

Future<void> main() async {
  await Chain.capture(cancelableFutureTest);
}

Future<void> someOperation(int i) async {
  try {
    print('operation $i 0%');

    await Future<void>.delayed(const Duration(milliseconds: 100));
    print('operation $i 25%');

    await Future<void>.delayed(const Duration(milliseconds: 100));
    print('operation $i 50%');

    await Future<void>.delayed(const Duration(milliseconds: 100));
    print('operation $i 75%');

    await Future<void>.delayed(const Duration(milliseconds: 100));
    print('operation $i 100%');
  } finally {
    print('operation $i finally');
  }
}

Future<void> someLongOperation() async {
  try {
    print('operation 1');
    await someOperation(1);

    print('operation 2');
    await someOperation(2);

    print('operation 3');
    await someOperation(3);

    print('operation 4');
    await someOperation(4);
  } finally {
    print('operations finally');
  }
}

final class Resource {
  Resource() {
    print('create resource');
  }

  void dispose() {
    print('dispose resource');
  }
}

Future<void> cancelableFutureTest() async {
  // Example 1:
  // Cancel by timer.
  //
  // operation 1
  // operation 1 0%
  // operation 1 25%
  // operation 1 50%
  // operation 1 75%
  // operation 1 100%
  // operation 1 finally
  // operation 2
  // operation 2 0%
  // operation 2 25%
  // operation 2 50%
  // --- cancel ---
  // operation 2 75%     <- nearest Future
  // operation 2 finally
  // operations finally
  // main finally
  // result: null
  // result: canceled
  // exception: [AsyncCancelException] Async operation canceled
  print('\nExample 1. Cancel by timer');
  final f1 = CancelableFuture(() async {
    try {
      await someLongOperation();

      return 'result';
    } finally {
      print('main finally');
    }
  });

  Future<void>.delayed(
    const Duration(milliseconds: 650),
    () {
      print('--- cancel ---');
      f1.cancel();
    },
  );

  print('result: ${await f1.orNull}');
  print('result: ${await f1.onCancel(() => 'canceled')}');
  try {
    print(await f1);
  } on AsyncCancelException catch (error, stackTrace) {
    print('exception: [${error.runtimeType}] $error');
    if (printStackTrace) {
      print(Chain.forTrace(stackTrace).terse);
    }
  }

  // Example 2:
  // Cancel by timeout.
  //
  // operation 1
  // operation 1 0%
  // operation 1 25%
  // operation 1 50%
  // operation 1 75%
  // --- timeout ---
  // operation 1 100%
  // operation 1 finally
  // operation 2         <- function - don't stop, do the synchronized part
  // operation 2 0%      <- nearest Future
  // operation 2 finally
  // operations finally
  // main finally
  // result: timeout
  // result: null
  // result: canceled
  // exception: [AsyncCancelByTimeoutException]
  //   Async operation canceled by timeout: 0:00:00.350000
  print('\nExample 2. Cancel by timeout');
  final f2 = CancelableFuture(() async {
    try {
      await someLongOperation();

      return 'result';
    } finally {
      print('main finally');
    }
  });

  final f2t = f2.timeout(
    const Duration(milliseconds: 350),
    cancelOnTimeout: true,
    onTimeout: () {
      print('--- timeout ---');
      return 'timeout';
    },
  );
  print('result: ${await f2t}');
  print('result: ${await f2.orNull}');
  print('result: ${await f2.onCancel(() => 'canceled')}');
  try {
    print(await f2);
  } on AsyncCancelException catch (error, stackTrace) {
    print('exception: [${error.runtimeType}] $error');
    if (printStackTrace) {
      print(Chain.forTrace(stackTrace).terse);
    }
  }

  // Example 3:
  // Problem: If the code is not prepared to be canceled, resources may leak
  // out.
  //
  // create resource
  // safe async code without exceptions
  // --- cancel ---
  // exception: [AsyncCancelException] Async operation canceled
  print('\nExample 3. If the code is not prepared to be canceled,'
      ' resources may leak out');

  Future<void> safeAsyncCodeWhereNoExceptionsAreExpected() async {
    print('safe async code without exceptions');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Future<void> fairlyCommonThirdPartyCode() async {
    final resource = Resource();

    await safeAsyncCodeWhereNoExceptionsAreExpected();

    try {
      print('code that may have exceptions');
    } finally {
      resource.dispose();
    }
  }

  final f3 = CancelableFuture(() async {
    await fairlyCommonThirdPartyCode();
    return 'result';
  });

  Future<void>.delayed(
    const Duration(milliseconds: 50),
    () {
      print('--- cancel ---');
      f3.cancel();
    },
  );

  try {
    await f3;
  } on AsyncCancelException catch (error, stackTrace) {
    print('exception: [${error.runtimeType}] $error');
    if (printStackTrace) {
      print(Chain.forTrace(stackTrace).terse);
    }
  }

  await gc();
}
