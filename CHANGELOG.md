# cancelable_future

## 0.1.0

- Publish the first working version.

## 0.2.0

- The previous version had a limitation: the `finally` block was not executed
  after canceling. Fix it.

## 0.3.0

- Change `void cancel()` to `Future<void> cancel()`.
