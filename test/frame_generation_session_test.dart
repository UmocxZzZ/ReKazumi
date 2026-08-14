import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/controller/player_frame_generation_session.dart';

void main() {
  test('session starts disabled and cannot probe a none backend', () {
    final session = FrameGenerationSession();

    expect(session.snapshot.state, FrameGenerationSessionState.disabled);
    expect(session.snapshot.canGenerate, isFalse);
    expect(session.beginProbe(FrameGenerationBackend.none), isFalse);
  });

  test('unavailable backend cannot become active', () {
    final session = FrameGenerationSession();

    expect(session.beginProbe(FrameGenerationBackend.vulkan), isTrue);
    session.markUnavailable('capability probe failed');

    expect(session.snapshot.state, FrameGenerationSessionState.unavailable);
    expect(session.snapshot.reason, 'capability probe failed');
    expect(session.markReady(), isFalse);
    expect(session.activate(), isFalse);
  });

  test('active session records generation and bypass counters', () {
    final session = FrameGenerationSession();

    expect(session.beginProbe(FrameGenerationBackend.vulkan), isTrue);
    expect(session.markReady(), isTrue);
    expect(session.activate(), isTrue);
    session.recordSourceFrame();
    session.recordGeneratedFrame(presented: true);
    session.recordGeneratedFrame(presented: false);
    session.recordDeadlineDrop();
    session.recordBypass(FrameGenerationBypassReason.duplicate);
    session.recordBypass(FrameGenerationBypassReason.sceneCut);

    final snapshot = session.snapshot;
    expect(snapshot.canGenerate, isTrue);
    expect(snapshot.sourceFrames, 1);
    expect(snapshot.generatedFrames, 2);
    expect(snapshot.generatedPresented, 1);
    expect(snapshot.deadlineDrops, 1);
    expect(snapshot.duplicateBypasses, 1);
    expect(snapshot.sceneCutBypasses, 1);
    expect(snapshot.toLogLine(), contains('generated-present=1'));
  });

  test('fault is sticky until the session is reset', () {
    final session = FrameGenerationSession();

    expect(session.beginProbe(FrameGenerationBackend.vulkan), isTrue);
    session.fault('VK_ERROR_DEVICE_LOST');

    expect(session.snapshot.state, FrameGenerationSessionState.faulted);
    expect(session.beginProbe(FrameGenerationBackend.vulkan), isFalse);
    session.markUnavailable('ignored');
    expect(session.snapshot.reason, 'VK_ERROR_DEVICE_LOST');

    session.reset();
    expect(session.snapshot.state, FrameGenerationSessionState.disabled);
    expect(session.beginProbe(FrameGenerationBackend.vulkan), isTrue);
  });

  test('debug status exposes the latest structured frame generation line', () {
    final debug = PlayerDebugController();
    final session = FrameGenerationSession();
    session.beginProbe(FrameGenerationBackend.vulkan);
    session.markUnavailable('no validated backend');

    debug.playerLog.add('unrelated');
    debug.playerLog.add(session.snapshot.toLogLine());

    expect(debug.frameGenerationStatus, startsWith('ReKazumi FG:'));
    expect(debug.frameGenerationStatus, contains('state=unavailable'));
    expect(
        debug.frameGenerationStatus, contains('reason=no_validated_backend'));
  });
}
