# Attention

**Never use this package in production. This code has only academic purpose.**

## What is it?

This package shows the possibility of creating a cancelable future in Dart.
Yes, it can be done. But you don't have to. Read below.

## Background

There is a frequent task: to cancel `Future`'s execution. But `Future`'s
architecture assumes atomicity of the operation and does not assume the ability
to cancel code execution from outside. If a developer writes

```dart
Future<SomeClass> someMethod() async {
  ...
}
```

he must be sure that this code will not be arbitrarily interrupted anywhere.
If a developer writes:

```dart
await future;
```

he must be sure that future will either return the result or throw an exception.
This is architecture of the `Future`. It may not be the best option. Maybe it
would be better if the cancel method was added to architecture of the `Future`
right away. But to add the ability to cancel `Future` now is to introduce chaos
into all the existing code on Dart. In order to add cancel to the code, the
developer must agree to it. As if signing a contract. And that possibility
exists. It's an asynchronous `Stream`'s generator `async*`:

```dart
Stream<SomeClass> f() async* {
  try {
    yield someResult;
    ...
    yield await someFuture;
    ...
    yield* someStream;
  } finally {
    ..
  }
}
```

This code can be externally terminated on any `yield`. Before the value is
computed or after the value is computed. (But `await someFuture` will still be
an atomic indivisible operation.) The code will cancel and not proceed to the
next step. There will be no exception thrown. But the `finally` block will be
executed.

So Dart has everything you need to cancel asynchronous operations. But it so
happens that `Future` is much more clear and convenient to use than `Stream`.
Especially when we are talking about a single result, not a stream of results.
For this reason `CancelableOperation` appears. "An asynchronous operation that
can be canceled" - as it is written in the [documentation](https://pub.dev/documentation/async/latest/async/CancelableOperation-class.html). `CancelableOperation` is not named `CancelableFuture` as
a matter of principle, so as not to confuse the developer. `Future` cannot be
canceled, while some asynchronous operation as if it could.

But in fact no asynchronous operation can be cancelable unless it is
implemented within itself.

```dart
Future<SomeClass> f() async {
  await ....;
  await ....;
  await ....;
  await ....;
}
```

You can choose not to wait for code execution to complete and return a value
(such as `null`) or throw an exception before the code executes, giving the
illusion of canceling an asynchronous operation. But the specified code will
continue working although nobody will need its result anymore. It will still
continue to go to the network, parse JSON, save values to the storage and
create other side-effects. And the developer will be surprised by unexpected
behavior of his program or the fact that the application slows down for some
reason.

The important conclusion from all of this is that `Future` is atomic and cannot
be canceled from the outside. This is a fundamental architectural decision of
Dart's team. And no external decision can change that. Some people get used to
living with it. Someone switches to `async*`. Someone keeps dreaming about the
appearance of cancelable `Future` in Dart.

Cancellable `Future` cannot appear by adding a `cancel` method. But only if
there is some new architectural solution where the developer makes it clear
that his code is ready to cancel. For example, it could look like this (note
the new keyphrase `async cancelable` that I invented):

```dart
CancelableFuture<SomeClass> f() async cancelable {
  final SomeResource resource1 = ....;
  late final SomeResource resource2;

  await someOperation;

  try {
    resource2 = ....;
    await someFuture1;
    await someFuture2;
    await someFuture3;
  } catch (e,s) {
    ...
  }
  } finally {
    resource2.dispose();
  }
  resource1.dispose();
}
```

And in this case, the developer will have to be aware that the code may be
interrupted not only at `await someFuture1`, `await someFuture2` or
`await someFuture3`, but also at `await someOperation`. And then `resource1`
will never be disposed, there will be a resource leak. This is a developer's
mistake, but by the phrase `async cancelable` he signed a contract that he is
responsible for his mistakes. But if the developer writes normal `async` code,
he didn't sign up for this behavior - his code should definitely complete and
`resource1` should be disposed of.

Read about the issue of creating a cancelable future here:
<https://github.com/dart-lang/sdk/issues/1806>

## Then what does this package do?

This is a hack that adds a cancelable `Future` to Dart. With which you can try
playing around with a future that has a cancelable `Future` )

There is no `async cancelable` contract here, so you can now actually cancel
any `async` code on any `await`. This is done via the timer creation hook
available in `Zone`. This does not make it possible to cancel `await` in the
same way as it is done for `yield`. But you can actually abort code execution
by canceling all created timers, and call the `Future` completion handler
passed in the `then` method, which is implicitly called when you write `await`.
You can "complete" `Future` by passing a value to the `onValue` handler, or you
can "throw" an exception by calling the `onError` handler. But since we have
nowhere to get the ready value of the unknown class `T` for the generic
`Future<T>`, we only have to "throw" the exception `AsyncCancelException`. As
a result, we can cancel `await` at any level of asynchronous code nesting, but
the original `Future` itself will terminate with an exception when canceled.
If an exception is not what you need, you can use the `orNull` getter or the
`onCancel` method.

Since this is a hack in the truest sense of the word, no `try/catch/finally` in
your `async` code will work in case of cancel. The variables created inside the
scope of the method will be released by garbage collector, but the resources
created outside will not be disposed of, because the `finally` block will not
be called. You can still recycle resources, but only by creating a wrapper over
the resource class and freeing it with `Finalizer`. Use the
`CancelableResource` class for this purpose.

Even if you ever decide to use this package in your working project (**which I
do not agree to**), remember that you can only use your own `async` methods in
your `async` code. External `async` methods that you do not control will not
know anything about your experiments and will not be able to release the
resources they use when you cancel them.

**Use this package for academic purposes only!**

## Usage

```dart
Future<void> someLongOperation(int i) async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  print('operation $i');
}

final f = CancelableFuture(() async {
  await someLongOperation(1);
  await someLongOperation(2);
  await someLongOperation(3);
  await someLongOperation(4);

  return 'result';
});

Future<void>.delayed(const Duration(milliseconds: 250), f.cancel);

print(await f.orNull);

print(await f.onCancel(() => 'canceled'));

try {
  await f;
} on AsyncCancelException catch (error) {
  print(error);
}

```

It'll be taken out:

```text
operation 1
operation 2
null
canceled
Async operation canceled
```

See the `/example` and `/test` folders for other examples of usage.
