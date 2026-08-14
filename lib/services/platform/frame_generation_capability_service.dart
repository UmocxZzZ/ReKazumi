import 'package:flutter/services.dart';

typedef FrameGenerationCapabilityInvoker = Future<Object?> Function();
typedef FrameGenerationOffscreenInvoker = Future<Object?> Function();

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

final class FrameGenerationOffscreenValidation {
  static const expectedValidationMarker =
      'ReKazumi Vulkan offscreen phase validation v1';
  static const expectedShaderSha256 =
      'f85d4f123b2f29b864439c1488c6fdc2361be6456746119c7230c9ad0a510b49';

  const FrameGenerationOffscreenValidation({
    required this.validationMarker,
    required this.shaderSha256,
    required this.validationComplete,
    required this.noSurface,
    required this.rgba16fReady,
    required this.rg16fReady,
    required this.shaderExecuted,
    required this.phase13Valid,
    required this.phase23Valid,
    required this.resourcesQuarantined,
    required this.phase13GpuNs,
    required this.phase23GpuNs,
    required this.phase13Red,
    required this.phase23Red,
    required this.transportBackendImplemented,
    required this.nativeError,
    required this.invocationError,
  });

  factory FrameGenerationOffscreenValidation.fromMap(
    Map<Object?, Object?> values,
  ) {
    int readInt(String key) => values[key] is int ? values[key]! as int : 0;
    double readDouble(String key) =>
        values[key] is num ? (values[key]! as num).toDouble() : 0.0;
    bool readBool(String key) => values[key] == true;
    String readString(String key) =>
        values[key] is String ? values[key]! as String : '';

    return FrameGenerationOffscreenValidation(
      validationMarker: readString('validationMarker'),
      shaderSha256: readString('shaderSha256'),
      validationComplete: readBool('validationComplete'),
      noSurface: readBool('noSurface'),
      rgba16fReady: readBool('rgba16fReady'),
      rg16fReady: readBool('rg16fReady'),
      shaderExecuted: readBool('shaderExecuted'),
      phase13Valid: readBool('phase13Valid'),
      phase23Valid: readBool('phase23Valid'),
      resourcesQuarantined: readBool('resourcesQuarantined'),
      phase13GpuNs: readInt('phase13GpuNs'),
      phase23GpuNs: readInt('phase23GpuNs'),
      phase13Red: readDouble('phase13Red'),
      phase23Red: readDouble('phase23Red'),
      transportBackendImplemented: readBool('transportBackendImplemented'),
      nativeError: readString('error'),
      invocationError: '',
    );
  }

  factory FrameGenerationOffscreenValidation.failed(Object error) {
    return FrameGenerationOffscreenValidation(
      validationMarker: '',
      shaderSha256: '',
      validationComplete: false,
      noSurface: false,
      rgba16fReady: false,
      rg16fReady: false,
      shaderExecuted: false,
      phase13Valid: false,
      phase23Valid: false,
      resourcesQuarantined: false,
      phase13GpuNs: 0,
      phase23GpuNs: 0,
      phase13Red: 0,
      phase23Red: 0,
      transportBackendImplemented: false,
      nativeError: '',
      invocationError: error.runtimeType.toString(),
    );
  }

  final String validationMarker;
  final String shaderSha256;
  final bool validationComplete;
  final bool noSurface;
  final bool rgba16fReady;
  final bool rg16fReady;
  final bool shaderExecuted;
  final bool phase13Valid;
  final bool phase23Valid;
  final bool resourcesQuarantined;
  final int phase13GpuNs;
  final int phase23GpuNs;
  final double phase13Red;
  final double phase23Red;
  final bool transportBackendImplemented;
  final String nativeError;
  final String invocationError;

  bool get passed =>
      invocationError.isEmpty &&
      nativeError.isEmpty &&
      validationMarker == expectedValidationMarker &&
      shaderSha256 == expectedShaderSha256 &&
      validationComplete &&
      noSurface &&
      rgba16fReady &&
      rg16fReady &&
      shaderExecuted &&
      phase13Valid &&
      phase23Valid &&
      phase13GpuNs > 0 &&
      phase23GpuNs > 0 &&
      !resourcesQuarantined &&
      !transportBackendImplemented;
}

final class FrameGenerationOffscreenValidationService {
  FrameGenerationOffscreenValidationService({
    FrameGenerationOffscreenInvoker? invoke,
    this.timeout = const Duration(seconds: 8),
  }) : _invoke = invoke ?? _invokePlatform;

  static const MethodChannel _channel =
      MethodChannel('com.predidit.rekazumi/frame_generation');

  final FrameGenerationOffscreenInvoker _invoke;
  final Duration timeout;
  Future<FrameGenerationOffscreenValidation>? _cachedValidation;

  static Future<Object?> _invokePlatform() {
    return _channel.invokeMethod<Object?>('validateOffscreen');
  }

  Future<FrameGenerationOffscreenValidation> validate() {
    return _cachedValidation ??= _validateOnce();
  }

  Future<FrameGenerationOffscreenValidation> _validateOnce() async {
    try {
      final result = await _invoke().timeout(timeout);
      if (result is! Map) {
        return FrameGenerationOffscreenValidation.failed(
          const FormatException('invalid offscreen validation response'),
        );
      }
      return FrameGenerationOffscreenValidation.fromMap(
        result.cast<Object?, Object?>(),
      );
    } catch (error) {
      return FrameGenerationOffscreenValidation.failed(error);
    }
  }
}
