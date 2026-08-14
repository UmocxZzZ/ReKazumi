import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/platform/frame_generation_capability_service.dart';

void main() {
  test('parses Android Vulkan feature version without enabling backend',
      () async {
    final service = FrameGenerationCapabilityService(
      invoke: () async => <Object?, Object?>{
        'androidSdk': 36,
        'vulkanVersion': 4206592,
        'vulkanMajor': 1,
        'vulkanMinor': 3,
        'vulkanPatch': 0,
        'vulkanHardwareLevel': 1,
        'hasVulkan11': true,
        'nativeBackendLinked': false,
      },
    );

    final capabilities = await service.probe();

    expect(capabilities.androidSdk, 36);
    expect(capabilities.vulkanMajor, 1);
    expect(capabilities.vulkanMinor, 3);
    expect(capabilities.hasVulkan11, isTrue);
    expect(capabilities.nativeBackendLinked, isFalse);
    expect(
      capabilities.unavailableReason,
      'native_backend_not_linked_vulkan_1_3_sdk_36',
    );
  });

  test('fails closed when Vulkan 1.1 is unavailable', () async {
    final service = FrameGenerationCapabilityService(
      invoke: () async => <Object?, Object?>{
        'androidSdk': 28,
        'vulkanVersion': 4194304,
        'vulkanMajor': 1,
        'vulkanMinor': 0,
        'vulkanPatch': 0,
        'vulkanHardwareLevel': 0,
        'hasVulkan11': false,
        'nativeBackendLinked': false,
      },
    );

    final capabilities = await service.probe();

    expect(capabilities.hasVulkan11, isFalse);
    expect(capabilities.unavailableReason, 'vulkan_1_1_unavailable_sdk_28');
  });

  test('validated native prerequisites still cannot enable transport',
      () async {
    final service = FrameGenerationCapabilityService(
      invoke: () async => <Object?, Object?>{
        'androidSdk': 36,
        'vulkanVersion': 4206592,
        'vulkanMajor': 1,
        'vulkanMinor': 3,
        'vulkanPatch': 0,
        'vulkanHardwareLevel': 1,
        'hasVulkan11': true,
        'nativeBackendLinked': true,
        'nativeExtensionProbeComplete': true,
        'nativeDeviceName': 'Adreno test device',
        'nativeDeviceApiMajor': 1,
        'nativeDeviceApiMinor': 3,
        'hasExternalMemoryAhb': true,
        'hasTimelineSemaphore': true,
        'nativePrerequisitesReady': true,
        'transportBackendImplemented': false,
        'nativeProbeError': '',
      },
    );

    final capabilities = await service.probe();

    expect(capabilities.nativeBackendLinked, isTrue);
    expect(capabilities.nativeDeviceName, 'Adreno test device');
    expect(
      capabilities.unavailableReason,
      'transport_backend_not_implemented_vulkan_1_3',
    );
  });

  test('native probe fails closed when required AHB transport is absent',
      () async {
    final service = FrameGenerationCapabilityService(
      invoke: () async => <Object?, Object?>{
        'androidSdk': 36,
        'vulkanMajor': 1,
        'vulkanMinor': 3,
        'hasVulkan11': true,
        'nativeBackendLinked': true,
        'nativeExtensionProbeComplete': true,
        'hasExternalMemoryAhb': false,
        'hasTimelineSemaphore': true,
        'nativePrerequisitesReady': false,
        'transportBackendImplemented': false,
        'nativeProbeError': '',
      },
    );

    final capabilities = await service.probe();

    expect(capabilities.unavailableReason, 'external_memory_ahb_unavailable');
  });

  test('fails closed on missing or malformed platform responses', () async {
    final missing = FrameGenerationCapabilityService(invoke: () async => null);
    final throwing = FrameGenerationCapabilityService(
      invoke: () async => throw StateError('channel failed'),
    );

    final missingResult = await missing.probe();
    final throwingResult = await throwing.probe();

    expect(
      missingResult.unavailableReason,
      'capability_probe_failed_FormatException',
    );
    expect(
      throwingResult.unavailableReason,
      'capability_probe_failed_StateError',
    );
  });

  test('times out and caches one native probe per controller', () async {
    var invocations = 0;
    final service = FrameGenerationCapabilityService(
      timeout: const Duration(milliseconds: 5),
      invoke: () async {
        invocations++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return <Object?, Object?>{};
      },
    );

    final first = await service.probe();
    final second = await service.probe();

    expect(first.unavailableReason, 'capability_probe_failed_TimeoutException');
    expect(identical(first, second), isTrue);
    expect(invocations, 1);
  });

  test('accepts a complete no-surface offscreen phase validation', () async {
    final service = FrameGenerationOffscreenValidationService(
      invoke: () async => <Object?, Object?>{
        'validationMarker': 'ReKazumi Vulkan offscreen phase validation v1',
        'shaderSha256':
            'f85d4f123b2f29b864439c1488c6fdc2361be6456746119c7230c9ad0a510b49',
        'validationComplete': true,
        'noSurface': true,
        'isolatedProcess': true,
        'rgba16fReady': true,
        'rg16fReady': true,
        'shaderExecuted': true,
        'phase13Valid': true,
        'phase23Valid': true,
        'resourcesQuarantined': false,
        'phase13GpuNs': 12000,
        'phase23GpuNs': 11000,
        'phase13Red': 1 / 3,
        'phase23Red': 2 / 3,
        'transportBackendImplemented': false,
        'error': '',
      },
    );

    final validation = await service.validate();

    expect(validation.passed, isTrue);
    expect(validation.phase13GpuNs, 12000);
    expect(validation.phase23GpuNs, 11000);
    expect(validation.transportBackendImplemented, isFalse);
  });

  test('offscreen validation fails closed on native mismatch', () async {
    final service = FrameGenerationOffscreenValidationService(
      invoke: () async => <Object?, Object?>{
        'validationComplete': false,
        'noSurface': true,
        'isolatedProcess': true,
        'shaderExecuted': true,
        'phase13Valid': false,
        'phase23Valid': true,
        'transportBackendImplemented': false,
        'error': 'offscreen_phase_output_mismatch',
      },
    );

    final validation = await service.validate();

    expect(validation.passed, isFalse);
    expect(validation.nativeError, 'offscreen_phase_output_mismatch');
  });

  test('offscreen validation rejects an unexpected shader identity', () async {
    final service = FrameGenerationOffscreenValidationService(
      invoke: () async => <Object?, Object?>{
        'validationMarker': 'ReKazumi Vulkan offscreen phase validation v1',
        'shaderSha256': 'unexpected',
        'validationComplete': true,
        'noSurface': true,
        'isolatedProcess': true,
        'rgba16fReady': true,
        'rg16fReady': true,
        'shaderExecuted': true,
        'phase13Valid': true,
        'phase23Valid': true,
        'resourcesQuarantined': false,
        'transportBackendImplemented': false,
        'error': '',
      },
    );

    expect((await service.validate()).passed, isFalse);
  });

  test('offscreen validation rejects zero GPU timestamp deltas', () async {
    final service = FrameGenerationOffscreenValidationService(
      invoke: () async => <Object?, Object?>{
        'validationMarker': 'ReKazumi Vulkan offscreen phase validation v1',
        'shaderSha256':
            'f85d4f123b2f29b864439c1488c6fdc2361be6456746119c7230c9ad0a510b49',
        'validationComplete': true,
        'noSurface': true,
        'isolatedProcess': true,
        'rgba16fReady': true,
        'rg16fReady': true,
        'shaderExecuted': true,
        'phase13Valid': true,
        'phase23Valid': true,
        'resourcesQuarantined': false,
        'phase13GpuNs': 0,
        'phase23GpuNs': 1,
        'transportBackendImplemented': false,
        'error': '',
      },
    );

    expect((await service.validate()).passed, isFalse);
  });

  test('offscreen validation rejects a non-isolated response', () async {
    final service = FrameGenerationOffscreenValidationService(
      invoke: () async => <Object?, Object?>{
        'validationMarker': 'ReKazumi Vulkan offscreen phase validation v1',
        'shaderSha256':
            'f85d4f123b2f29b864439c1488c6fdc2361be6456746119c7230c9ad0a510b49',
        'validationComplete': true,
        'noSurface': true,
        'isolatedProcess': false,
        'rgba16fReady': true,
        'rg16fReady': true,
        'shaderExecuted': true,
        'phase13Valid': true,
        'phase23Valid': true,
        'resourcesQuarantined': false,
        'phase13GpuNs': 1,
        'phase23GpuNs': 1,
        'transportBackendImplemented': false,
        'error': '',
      },
    );

    expect((await service.validate()).passed, isFalse);
  });

  test('offscreen validation times out and is invoked once', () async {
    var invocations = 0;
    final service = FrameGenerationOffscreenValidationService(
      timeout: const Duration(milliseconds: 5),
      invoke: () async {
        invocations++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return <Object?, Object?>{};
      },
    );

    final first = await service.validate();
    final second = await service.validate();

    expect(first.passed, isFalse);
    expect(first.invocationError, 'TimeoutException');
    expect(identical(first, second), isTrue);
    expect(invocations, 1);
  });
}
