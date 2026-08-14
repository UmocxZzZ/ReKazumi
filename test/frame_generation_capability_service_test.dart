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

  test('a linked backend still waits for native extension validation',
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
      },
    );

    final capabilities = await service.probe();

    expect(capabilities.nativeBackendLinked, isTrue);
    expect(capabilities.unavailableReason, 'native_extension_probe_pending');
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
}
