import 'dart:async';

final _finalizers = <dynamic, Finalizer<dynamic>>{};

final class CancelableResource<T> {
  final T value;
  final FutureOr<void> Function(T resource) _onDispose;

  CancelableResource._(this.value, this._onDispose);

  static Future<CancelableResource<T>> create<T>(
    FutureOr<T> Function() create, {
    required void Function(T value) onDispose,
  }) async {
    final futureOr = create();
    final value = futureOr is Future<T> ? await futureOr : futureOr;
    final resource = CancelableResource._(value, onDispose);

    final finalizer = Finalizer<T>((value) {
      print('finalize resource @${value.hashCode}');
      onDispose(value);
      _finalizers.remove(value);
    })
      ..attach(resource, value, detach: resource);
    _finalizers[value] = finalizer;

    return resource;
  }

  Future<void> dispose() async {
    _onDispose(value);
    final finalizer = _finalizers[value];
    finalizer?.detach(this);
  }
}
