@Timeout(Duration(seconds: 5))
library;

import 'package:cancelable_future/cancelable_future.dart';
import 'package:test/test.dart';

import 'gc.dart';

const stepDuration = Duration(milliseconds: 100);
const stepsCount = 4;

final operationDuration = stepDuration * stepsCount;
const operationsCount = 4;

final class _MyTestClass {
  final String text;

  _MyTestClass(this.text);

  @override
  String toString() => '_MyTestClass($text)';
}

final _finalizer = Finalizer<Object>((value) {
  print('finalizer: $value');
});

void finalizerAttach(Object obj) {
  _finalizer.attach(obj, '${obj.runtimeType}@${obj.hashCode}');
}

void main() {
  group('Cancelable future', () {
    Future<int> someLongOperation(int i) async {
      // ignore: unused_local_variable
      final myTest = _MyTestClass('$i');

      for (var j = 1; j <= stepsCount; j++) {
        await Future<void>.delayed(stepDuration);

        final message = '$i.$j';
        // ignore: unused_local_variable
        final myTest = _MyTestClass(message);
        print(message);
      }

      return i;
    }

    tearDown(() async {
      print('tearDown: cleaning test');

      await gc();

      var classHeapStats = await findClass('_MyTestClass');
      expect(classHeapStats?.instancesCurrent, 0);

      classHeapStats = await findClass('CancelableFuture');
      expect(classHeapStats?.instancesCurrent, 0);
    });

    test('Without canceling', () async {
      var count = 0;

      final f = CancelableFuture(() async {
        for (var i = 1; i <= operationsCount; i++) {
          count = await someLongOperation(i);
          print('$i ok');
        }

        return 'abc';
      });

      finalizerAttach(f);
      finalizerAttach(f.$future);

      expect(f.isCompleted, isFalse);
      expect(f.isCanceled, isFalse);
      expect(f.isDone, isFalse);

      await Future.wait([f, f]);
      await expectLater(f, completion('abc'));

      expect(f.isCompleted, isTrue);
      expect(f.isCanceled, isFalse);
      expect(f.isDone, isTrue);

      expect(count, operationsCount);
    });

    test('Cancel computation', () async {
      var count = 0;

      final f = CancelableFuture(() async {
        for (var i = 1; i <= operationsCount; i++) {
          count = await someLongOperation(i);
          print('$i ok');
        }

        return 'abc';
      });

      finalizerAttach(f);
      finalizerAttach(f.$future);

      // Cancel Future at runtime.
      Future<void>.delayed(
        operationDuration * 2 + operationDuration ~/ 2,
        f.cancel,
      );

      expect(f.isCompleted, isFalse);
      expect(f.isCanceled, isFalse);
      expect(f.isDone, isFalse);

      try {
        await Future.wait([f, f]);
      } on AsyncCancelException {
        print('catch cancelation');
      }
      await expectLater(f, throwsA(isA<AsyncCancelException>()));
      // TODO(vi-k): It's not working.
      // await expectLater(
      //   Future(() async => await f),
      //   throwsA(isA<AsyncCancelException>()),
      // );

      expect(f.isCompleted, isFalse);
      expect(f.isCanceled, isTrue);
      expect(f.isDone, isTrue);

      expect(count, 2);
    });

    test('Cancel after done', () async {
      var count = 0;

      final f = CancelableFuture(() async {
        for (var i = 1; i <= 4; i++) {
          count = await someLongOperation(i);
          print('$i ok');
        }

        return 'abc';
      });

      finalizerAttach(f);
      finalizerAttach(f.$future);

      expect(f.isCompleted, isFalse);
      expect(f.isCanceled, isFalse);
      expect(f.isDone, isFalse);

      await Future.wait([f, f]);
      await expectLater(f, completion('abc'));

      // Attempt to cancel Future after completing it and returning a result.
      f.cancel();

      await expectLater(
        Future(() async => await f),
        completion('abc'),
      );

      expect(f.isCompleted, isTrue);
      expect(f.isCanceled, isFalse);
      expect(f.isDone, isTrue);

      expect(count, operationsCount);
    });

    test('Cancel after execution but before receiving the result', () async {
      var count = 0;

      final f = CancelableFuture(() async {
        for (var i = 1; i <= operationsCount; i++) {
          count = await someLongOperation(i);
          print('$i ok');
        }

        return 'abc';
      });

      finalizerAttach(f);
      finalizerAttach(f.$future);

      // Let Future work out without calling await/then (i.e. without taking
      // the result). Then try to cancel.
      await Future<void>.delayed(
        operationDuration * operationsCount + operationDuration,
      );

      expect(f.isCompleted, isTrue);
      expect(f.isCanceled, isFalse);
      expect(f.isDone, isTrue);

      f.cancel();

      await Future.wait([f, f]);
      await expectLater(f, completion('abc'));

      expect(f.isCompleted, isTrue);
      expect(f.isCanceled, isFalse);
      expect(f.isDone, isTrue);

      expect(count, 4);
    });
  });
}
