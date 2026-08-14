import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/logs/offscreen_validation_action.dart';
import 'package:kazumi/services/platform/frame_generation_capability_service.dart';

Map<Object?, Object?> _validResponse() => <Object?, Object?>{
      'validationMarker': 'ReKazumi Vulkan offscreen phase validation v1',
      'shaderSha256':
          'f85d4f123b2f29b864439c1488c6fdc2361be6456746119c7230c9ad0a510b49',
      'timeoutPolicyMarker': 'ReKazumi offscreen timeout quarantine v1',
      'validationComplete': true,
      'noSurface': true,
      'isolatedProcess': true,
      'isolatedProcessId': 42,
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
    };

void main() {
  testWidgets('offscreen validation requires explicit confirmation',
      (tester) async {
    var invocations = 0;
    final service = FrameGenerationOffscreenValidationService(
      invoke: () async {
        invocations++;
        return _validResponse();
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: OffscreenValidationAction(
            service: service,
            diagnosticWriter: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('运行离屏 GPU 验证'));
    await tester.pumpAndSettle();
    expect(invocations, 0);
    expect(find.text('运行离屏 GPU 验证？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(invocations, 0);
  });

  testWidgets('confirmed offscreen validation shows structured result',
      (tester) async {
    var invocations = 0;
    final service = FrameGenerationOffscreenValidationService(
      invoke: () async {
        invocations++;
        return _validResponse();
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: OffscreenValidationAction(
            service: service,
            diagnosticWriter: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('运行离屏 GPU 验证'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始验证'));
    await tester.pumpAndSettle();

    expect(invocations, 1);
    expect(find.text('离屏验证通过'), findsOneWidget);
    expect(find.textContaining('"transportBackendImplemented": false'),
        findsOneWidget);
  });
}
