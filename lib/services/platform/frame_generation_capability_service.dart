import 'package:flutter/services.dart';

typedef FrameGenerationCapabilityInvoker = Future<Object?> Function();

final class FrameGenerationCapabilities {
  const FrameGenerationCapabilities({
    required this.androidSdk,
    required this.vulkanVersion,
    required this.vulkanMajor,
    required this.vulkanMinor,
    required this.vulkanPatch,
    required this.vulkanHardwareLevel,
    required this.hasVulkan11,
    required this.nativeBackendLinked,
    required this.nativeExtensionProbeComplete,
    required this.nativeDeviceName,
    required this.nativeDeviceApiMajor,
    required this.nativeDeviceApiMinor,
    required this.hasExternalMemoryAhb,
    required this.hasTimelineSemaphore,
    required this.nativePrerequisitesReady,
    required this.transportBackendImplemented,
    required this.nativeProbeError,
    required this.probeError,
  });

  factory FrameGenerationCapabilities.fromMap(Map<Object?, Object?> values) {
    int readInt(String key) => values[key] is int ? values[key]! as int : 0;
    bool readBool(String key) => values[key] == true;
    String readString(String key) =>
        values[key] is String ? values[key]! as String : '';

    return FrameGenerationCapabilities(
      androidSdk: readInt('androidSdk'),
      vulkanVersion: readInt('vulkanVersion'),
      vulkanMajor: readInt('vulkanMajor'),
      vulkanMinor: readInt('vulkanMinor'),
      vulkanPatch: readInt('vulkanPatch'),
      vulkanHardwareLevel: readInt('vulkanHardwareLevel'),
      hasVulkan11: readBool('hasVulkan11'),
      nativeBackendLinked: readBool('nativeBackendLinked'),
      nativeExtensionProbeComplete: readBool('nativeExtensionProbeComplete'),
      nativeDeviceName: readString('nativeDeviceName'),
      nativeDeviceApiMajor: readInt('nativeDeviceApiMajor'),
      nativeDeviceApiMinor: readInt('nativeDeviceApiMinor'),
      hasExternalMemoryAhb: readBool('hasExternalMemoryAhb'),
      hasTimelineSemaphore: readBool('hasTimelineSemaphore'),
      nativePrerequisitesReady: readBool('nativePrerequisitesReady'),
      transportBackendImplemented: readBool('transportBackendImplemented'),
      nativeProbeError: readString('nativeProbeError'),
      probeError: '',
    );
  }

  factory FrameGenerationCapabilities.failed(Object error) {
    return FrameGenerationCapabilities(
      androidSdk: 0,
      vulkanVersion: 0,
      vulkanMajor: 0,
      vulkanMinor: 0,
      vulkanPatch: 0,
      vulkanHardwareLevel: 0,
      hasVulkan11: false,
      nativeBackendLinked: false,
      nativeExtensionProbeComplete: false,
      nativeDeviceName: '',
      nativeDeviceApiMajor: 0,
      nativeDeviceApiMinor: 0,
      hasExternalMemoryAhb: false,
      hasTimelineSemaphore: false,
      nativePrerequisitesReady: false,
      transportBackendImplemented: false,
      nativeProbeError: '',
      probeError: error.runtimeType.toString(),
    );
  }

  final int androidSdk;
  final int vulkanVersion;
  final int vulkanMajor;
  final int vulkanMinor;
  final int vulkanPatch;
  final int vulkanHardwareLevel;
  final bool hasVulkan11;
  final bool nativeBackendLinked;
  final bool nativeExtensionProbeComplete;
  final String nativeDeviceName;
  final int nativeDeviceApiMajor;
  final int nativeDeviceApiMinor;
  final bool hasExternalMemoryAhb;
  final bool hasTimelineSemaphore;
  final bool nativePrerequisitesReady;
  final bool transportBackendImplemented;
  final String nativeProbeError;
  final String probeError;

  String get unavailableReason {
    if (probeError.isNotEmpty) return 'capability_probe_failed_$probeError';
    if (!hasVulkan11) return 'vulkan_1_1_unavailable_sdk_$androidSdk';
    if (!nativeBackendLinked) {
      if (nativeProbeError.isNotEmpty) {
        return 'native_library_unavailable_$nativeProbeError';
      }
      return 'native_backend_not_linked_vulkan_'
          '${vulkanMajor}_${vulkanMinor}_sdk_$androidSdk';
    }
    if (nativeProbeError.isNotEmpty) {
      return 'native_probe_failed_$nativeProbeError';
    }
    if (!nativeExtensionProbeComplete) return 'native_extension_probe_pending';
    if (!hasExternalMemoryAhb) return 'external_memory_ahb_unavailable';
    if (!hasTimelineSemaphore) return 'timeline_semaphore_unavailable';
    if (!nativePrerequisitesReady) return 'native_prerequisites_incomplete';
    if (!transportBackendImplemented) {
      return 'transport_backend_not_implemented_vulkan_'
          '${nativeDeviceApiMajor}_$nativeDeviceApiMinor';
    }
    return 'frame_generation_algorithm_not_configured';
  }
}

final class FrameGenerationCapabilityService {
  FrameGenerationCapabilityService({
    FrameGenerationCapabilityInvoker? invoke,
    this.timeout = const Duration(milliseconds: 500),
  }) : _invoke = invoke ?? _invokePlatform;

  static const MethodChannel _channel =
      MethodChannel('com.predidit.rekazumi/frame_generation');

  final FrameGenerationCapabilityInvoker _invoke;
  final Duration timeout;
  Future<FrameGenerationCapabilities>? _cachedProbe;

  static Future<Object?> _invokePlatform() {
    return _channel.invokeMethod<Object?>('probeVulkan');
  }

  Future<FrameGenerationCapabilities> probe() {
    return _cachedProbe ??= _probeOnce();
  }

  Future<FrameGenerationCapabilities> _probeOnce() async {
    try {
      final result = await _invoke().timeout(timeout);
      if (result is! Map) {
        return FrameGenerationCapabilities.failed(
          const FormatException('invalid capability response'),
        );
      }
      return FrameGenerationCapabilities.fromMap(
          result.cast<Object?, Object?>());
    } catch (error) {
      return FrameGenerationCapabilities.failed(error);
    }
  }
}
