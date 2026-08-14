enum FrameGenerationBackend {
  none,
  vulkan,
}

enum FrameGenerationSessionState {
  disabled,
  probing,
  ready,
  active,
  unavailable,
  bypassed,
  faulted,
}

enum FrameGenerationBypassReason {
  duplicate,
  sceneCut,
}

final class FrameGenerationSnapshot {
  const FrameGenerationSnapshot({
    required this.backend,
    required this.state,
    required this.reason,
    required this.sourceFrames,
    required this.generatedFrames,
    required this.generatedPresented,
    required this.deadlineDrops,
    required this.duplicateBypasses,
    required this.sceneCutBypasses,
  });

  final FrameGenerationBackend backend;
  final FrameGenerationSessionState state;
  final String reason;
  final int sourceFrames;
  final int generatedFrames;
  final int generatedPresented;
  final int deadlineDrops;
  final int duplicateBypasses;
  final int sceneCutBypasses;

  bool get canGenerate => state == FrameGenerationSessionState.active;

  String toLogLine() {
    final safeReason =
        reason.isEmpty ? '-' : reason.replaceAll(RegExp(r'\s+'), '_');
    return 'ReKazumi FG: backend=${backend.name} state=${state.name} '
        'reason=$safeReason source=$sourceFrames generated=$generatedFrames '
        'generated-present=$generatedPresented deadline-drop=$deadlineDrops '
        'bypass-duplicate=$duplicateBypasses bypass-cut=$sceneCutBypasses';
  }
}

final class FrameGenerationSession {
  FrameGenerationBackend _backend = FrameGenerationBackend.none;
  FrameGenerationSessionState _state = FrameGenerationSessionState.disabled;
  String _reason = '';
  int _sourceFrames = 0;
  int _generatedFrames = 0;
  int _generatedPresented = 0;
  int _deadlineDrops = 0;
  int _duplicateBypasses = 0;
  int _sceneCutBypasses = 0;

  FrameGenerationSnapshot get snapshot => FrameGenerationSnapshot(
        backend: _backend,
        state: _state,
        reason: _reason,
        sourceFrames: _sourceFrames,
        generatedFrames: _generatedFrames,
        generatedPresented: _generatedPresented,
        deadlineDrops: _deadlineDrops,
        duplicateBypasses: _duplicateBypasses,
        sceneCutBypasses: _sceneCutBypasses,
      );

  void reset() {
    _backend = FrameGenerationBackend.none;
    _state = FrameGenerationSessionState.disabled;
    _reason = '';
    _sourceFrames = 0;
    _generatedFrames = 0;
    _generatedPresented = 0;
    _deadlineDrops = 0;
    _duplicateBypasses = 0;
    _sceneCutBypasses = 0;
  }

  bool beginProbe(FrameGenerationBackend backend) {
    if (backend == FrameGenerationBackend.none ||
        _state == FrameGenerationSessionState.faulted) {
      return false;
    }
    _backend = backend;
    _state = FrameGenerationSessionState.probing;
    _reason = '';
    return true;
  }

  bool markReady() {
    if (_state != FrameGenerationSessionState.probing) return false;
    _state = FrameGenerationSessionState.ready;
    _reason = '';
    return true;
  }

  bool activate() {
    if (_state != FrameGenerationSessionState.ready) return false;
    _state = FrameGenerationSessionState.active;
    _reason = '';
    return true;
  }

  void markUnavailable(String reason) {
    if (_state == FrameGenerationSessionState.faulted) return;
    _state = FrameGenerationSessionState.unavailable;
    _reason = reason;
  }

  void recordSourceFrame() {
    if (_state == FrameGenerationSessionState.active) _sourceFrames++;
  }

  void recordGeneratedFrame({required bool presented}) {
    if (_state != FrameGenerationSessionState.active) return;
    _generatedFrames++;
    if (presented) _generatedPresented++;
  }

  void recordDeadlineDrop() {
    if (_state == FrameGenerationSessionState.active) _deadlineDrops++;
  }

  void recordBypass(FrameGenerationBypassReason reason) {
    if (_state != FrameGenerationSessionState.active) return;
    switch (reason) {
      case FrameGenerationBypassReason.duplicate:
        _duplicateBypasses++;
      case FrameGenerationBypassReason.sceneCut:
        _sceneCutBypasses++;
    }
  }

  void bypass(String reason) {
    if (_state == FrameGenerationSessionState.faulted) return;
    _state = FrameGenerationSessionState.bypassed;
    _reason = reason;
  }

  void fault(String reason) {
    _state = FrameGenerationSessionState.faulted;
    _reason = reason;
  }
}
