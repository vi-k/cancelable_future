import 'dart:async';

import 'package:cancelable_future/cancelable_future.dart';
import 'package:cancelable_future/src/cancelable_resource.dart';
import 'package:stack_trace/stack_trace.dart';

import '../test/gc.dart';

// const printStackTrace = true;
const printStackTrace = false;

Future<void> someOperation(int i) async {
  print('operation $i 0%');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  print('operation $i 25%');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  print('operation $i 50%');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  print('operation $i 75%');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  print('operation $i 100%');
}

Future<void> someLongOperation() async {
  await someOperation(1);
  await someOperation(2);
  await someOperation(3);
  await someOperation(4);
}

final class Resource {
  Resource._();

  static Future<Resource> getResource() async {
    final resource = Resource._();
    print('create resource @${resource.hashCode}');

    return resource;
  }

  void dispose() {
    print('dispose resource @$hashCode');
  }
}

Future<void> main() async {
  await Chain.capture(cancelableFutureTest);
}

Future<void> cancelableFutureTest() async {
  // Example 1:
  // Cancel by timer.
  //
  // operation 1 0%
  // operation 1 25%
  // operation 1 50%
  // operation 1 75%
  // operation 1 100%
  // operation 2 0%
  // operation 2 25%
  // operation 2 50%
  // canceled: AsyncCancelException
  // null
  // no result
  print('\nExample 1. Cancel by timer');
  final f1 = CancelableFuture(() async {
    await someLongOperation();

    return 'result';
  });

  Future<void>.delayed(const Duration(milliseconds: 650), f1.cancel);

  try {
    print(await f1);
  } on AsyncCancelException catch (error, stackTrace) {
    print('canceled: ${error.runtimeType}');
    if (printStackTrace) {
      print('\n${Chain.forTrace(stackTrace).terse}');
    }
  }
  print(await f1.orNull);
  print(await f1.onCancel(() => 'no result'));

  // Example 2:
  // Cancel by timeout.
  //
  // operation 1 0%
  // operation 1 25%
  // operation 1 50%
  // operation 1 75%
  // canceled: AsyncCancelByTimeoutException
  // canceled: AsyncCancelException
  // null
  // no result
  print('\nExample 2. Cancel by timeout');
  final f2 = CancelableFuture(() async {
    await someLongOperation();

    return 'result';
  });

  try {
    await f2.timeout(
      const Duration(milliseconds: 350),
      cancelOnTimeout: true,
    );
  } on AsyncCancelException catch (error, stackTrace) {
    print('canceled: ${error.runtimeType}');
    if (printStackTrace) {
      print('\n${Chain.forTrace(stackTrace).terse}');
    }
  }

  try {
    print(await f2);
  } on AsyncCancelException catch (error, stackTrace) {
    print('canceled: ${error.runtimeType}');
    if (printStackTrace) {
      print('\n${Chain.forTrace(stackTrace).terse}');
    }
  }
  print(await f2.orNull);
  print(await f2.onCancel(() => 'no result'));

  // Example 3:
  // Problem: the finally block is not executed, the resource is not being
  // disposed.
  //
  // create resource @...
  // operation 1 0%
  // operation 1 25%
  // canceled: AsyncCancelException
  print('\nExample 3. Problem: the finally block is not executed,'
      ' the resource is not being disposed.');
  final f3 = CancelableFuture(() async {
    final resource = await Resource.getResource();
    try {
      await someLongOperation();

      return 'result';
    } finally {
      print('finally');
      resource.dispose();
    }
  });

  Future<void>.delayed(const Duration(milliseconds: 150), f3.cancel);

  try {
    print(await f3);
  } on AsyncCancelException catch (error, stackTrace) {
    print('canceled: ${error.runtimeType}');
    if (printStackTrace) {
      print('\n${Chain.forTrace(stackTrace).terse}');
    }
  }

  // Example 4:
  // Solution: resource disposed with `Finalizer`.
  //
  // create resource @...
  // operation 1 0%
  // operation 1 25%
  // canceled: AsyncCancelException
  // finalize resource @...
  // dispose resource @...
  print('\nExample 4. Solution: resource disposed with `Finalizer`');
  final f4 = CancelableFuture(() async {
    final resource = await CancelableResource.create(
      Resource.getResource,
      onDispose: (value) => value.dispose(),
    );

    try {
      await someLongOperation();

      return 'result';
    } finally {
      print('finally');
      await resource.dispose();
    }
  });

  Future<void>.delayed(const Duration(milliseconds: 150), f4.cancel);

  try {
    print(await f4);
  } on AsyncCancelException catch (error, stackTrace) {
    print('canceled: ${error.runtimeType}');
    if (printStackTrace) {
      print('\n${Chain.forTrace(stackTrace).terse}');
    }
  }

  await gc();
}
