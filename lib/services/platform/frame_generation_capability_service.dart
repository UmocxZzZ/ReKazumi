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
    required this.probeError,
  });

  factory FrameGenerationCapabilities.fromMap(Map<Object?, Object?> values) {
    int readInt(String key) => values[key] is int ? values[key]! as int : 0;
    bool readBool(String key) => values[key] == true;

    return FrameGenerationCapabilities(
      androidSdk: readInt('androidSdk'),
      vulkanVersion: readInt('vulkanVersion'),
      vulkanMajor: readInt('vulkanMajor'),
      vulkanMinor: readInt('vulkanMinor'),
      vulkanPatch: readInt('vulkanPatch'),
      vulkanHardwareLevel: readInt('vulkanHardwareLevel'),
      hasVulkan11: readBool('hasVulkan11'),
      nativeBackendLinked: readBool('nativeBackendLinked'),
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
  final String probeError;

  String get unavailableReason {
    if (probeError.isNotEmpty) return 'capability_probe_failed_$probeError';
    if (!hasVulkan11) return 'vulkan_1_1_unavailable_sdk_$androidSdk';
    if (!nativeBackendLinked) {
      return 'native_backend_not_linked_vulkan_'
          '${vulkanMajor}_${vulkanMinor}_sdk_$androidSdk';
    }
    return 'native_extension_probe_pending';
  }
}

final class FrameGenerationCapabilityService {
  FrameGenerationCapabilityService({
    FrameGenerationCapabilityInvoker? invoke,
  }) : _invoke = invoke ?? _invokePlatform;

  static const MethodChannel _channel =
      MethodChannel('com.predidit.rekazumi/frame_generation');

  final FrameGenerationCapabilityInvoker _invoke;

  static Future<Object?> _invokePlatform() {
    return _channel.invokeMethod<Object?>('probeVulkan');
  }

  Future<FrameGenerationCapabilities> probe() async {
    try {
      final result = await _invoke();
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
