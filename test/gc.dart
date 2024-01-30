import 'dart:async';
import 'dart:developer';
import 'dart:isolate';

import 'package:vm_service/vm_service.dart' hide Isolate;
import 'package:vm_service/vm_service_io.dart';

/// Попробовать запустить GC.
///
/// Это возможно только в режиме отладки, т.к. приложение должно быть запущено
/// с параметром --observe:
///
/// ```
/// dart run --observe
/// ```
///
/// Не даётся никаких гарантий, что GC отработает.
Future<void> gc() => handleAllocationProfile(
      (vmService, profile) {
        // Garbage collection only.
      },
      gc: true,
    );

/// Найти информацию о классе в куче.
Future<ClassHeapStats?> findClass(String className) => handleAllocationProfile(
      (vmService, profile) {
        ClassHeapStats? classHeapStats;
        for (final m in profile.members!) {
          final ref = m.classRef;
          if (ref != null && ref.name == className) {
            classHeapStats = m;
            break;
          }
        }
        return classHeapStats;
      },
    );

/// Обработать профиль кучи.
Future<T> handleVmService<T>(
  FutureOr<T> Function(VmService vmService, String isolateId) cb,
) async {
  VmService? vmService;

  try {
    final serverUri = (await Service.getInfo()).serverWebSocketUri;
    if (serverUri == null) {
      throw Exception(
        'Please run the application with the --observe parameter!',
      );
    }

    final isolateId = Service.getIsolateId(Isolate.current)!;
    vmService = await vmServiceConnectUri(serverUri.toString());

    return await cb(vmService, isolateId);
  } finally {
    await vmService?.dispose();
  }
}

/// Обработать профиль кучи.
Future<T> handleAllocationProfile<T>(
  FutureOr<T> Function(VmService vmService, AllocationProfile profile) cb, {
  bool gc = false,
}) =>
    handleVmService((vmService, isolateId) async {
      final profile = await vmService.getAllocationProfile(isolateId, gc: gc);

      return await cb(vmService, profile);
    });
