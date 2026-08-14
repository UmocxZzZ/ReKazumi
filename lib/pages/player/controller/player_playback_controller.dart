// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/controller/player_frame_interpolation.dart';
import 'package:kazumi/pages/player/controller/player_frame_generation_session.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/player/playback_cache_policy.dart';
import 'package:kazumi/services/player/player_screenshot_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/media.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';

part 'player_playback_controller.g.dart';

class PlayerPlaybackController = _PlayerPlaybackController
    with _$PlayerPlaybackController;

final class _OwnedPlayer {
  _OwnedPlayer(this.player);

  final Player player;
  Future<void>? _disposeFuture;

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    try {
      await player.dispose();
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'PlayerPlaybackController: failed to dispose media player',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        await player.stop();
      } catch (_) {}
    }
  }
}

abstract class _PlayerPlaybackController with Store {
  _PlayerPlaybackController({
    required this.shaderAssetService,
    required this.debug,
    required this.videoUrl,
    required this.isLocalPlayback,
  });

  final ShaderAssetService shaderAssetService;
  final PlayerDebugController debug;
  final String Function() videoUrl;
  final bool Function() isLocalPlayback;
  final PlayerScreenshotService screenshotService =
      const PlayerScreenshotService();
  final FrameGenerationSession frameGeneration = FrameGenerationSession();
  late final PlaybackCachePolicy cachePolicy = PlaybackCachePolicy(
    isLocalPlayback: isLocalPlayback,
    currentPlayer: () => mediaPlayer,
  );

  _OwnedPlayer? _ownedPlayer;
  Player? get mediaPlayer => _ownedPlayer?.player;
  VideoController? videoController;

  bool hAenable = true;
  late String hardwareDecoder;
  bool androidEnableOpenSLES = true;
  bool autoPlay = true;
  bool playerDebugMode = false;
  int buttonSkipTime = 80;
  int arrowKeySkipTime = 10;

  /// 历史记录传入的 offset
  int startOffset = 0;

  /// 当前超分辨率模式
  @observable
  SuperResolutionMode superResolutionMode = SuperResolutionMode.off;

  FrameInterpolationMode frameInterpolationMode = FrameInterpolationMode.off;

  @observable
  double volume = -1;

  /// 手势调节时的精确音量，避免 UI 节流导致累计误差
  double preciseVolume = -1;

  @observable
  bool loading = true;
  @observable
  bool playing = false;
  @observable
  bool isBuffering = true;
  @observable
  bool completed = false;
  @observable
  Duration currentPosition = Duration.zero;
  @observable
  Duration buffer = Duration.zero;
  @observable
  Duration duration = Duration.zero;
  @observable
  double playerSpeed = 1.0;

  bool isCurrentPlayer(Player player) {
    return identical(mediaPlayer, player);
  }

  Future<Player?> _discardIfNotCurrent(_OwnedPlayer candidate) async {
    if (identical(_ownedPlayer, candidate)) {
      return candidate.player;
    }
    await candidate.dispose();
    return null;
  }

  Future<void> _cancelDebugInfo() async {
    try {
      await debug.cancel();
    } catch (_) {}
  }

  @action
  void resetForInit() {
    frameGeneration.reset();
    playing = false;
    loading = true;
    isBuffering = true;
    currentPosition = Duration.zero;
    buffer = Duration.zero;
    duration = Duration.zero;
    completed = false;
    startOffset = 0;
  }

  /// 本次会话是否从距结尾 [nearEndWatchedThreshold] 以内的位置起播。
  /// 这样的"播放完成"并非真正看完，应从头重播而非切下一集
  bool get resumedNearEnd {
    if (startOffset <= 0 || duration <= Duration.zero) {
      return false;
    }
    return Duration(seconds: startOffset) >= duration - nearEndWatchedThreshold;
  }

  /// 从头重播当前视频。[startOffset] 在重播落地后才归零，
  /// 避免自动连播在此期间抢先触发
  Future<void> restartFromBeginning() async {
    final player = mediaPlayer;
    if (player == null) {
      return;
    }
    try {
      await player.seek(Duration.zero);
      if (!isCurrentPlayer(player)) {
        return;
      }
      await player.play();
      startOffset = 0;
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to restart from beginning', error: e);
    }
  }

  bool get playerPlaying {
    try {
      return mediaPlayer?.state.playing ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerBuffering {
    try {
      return mediaPlayer?.state.buffering ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerCompleted {
    try {
      return mediaPlayer?.state.completed ?? false;
    } catch (_) {
      return false;
    }
  }

  double get playerVolume {
    try {
      return mediaPlayer?.state.volume ?? volume;
    } catch (_) {
      return volume;
    }
  }

  Duration get playerPosition {
    try {
      return mediaPlayer?.state.position ?? currentPosition;
    } catch (_) {
      return currentPosition;
    }
  }

  Duration get playerBuffer {
    try {
      return mediaPlayer?.state.buffer ?? buffer;
    } catch (_) {
      return buffer;
    }
  }

  Duration get playerDuration {
    try {
      return mediaPlayer?.state.duration ?? duration;
    } catch (_) {
      return duration;
    }
  }

  Future<Player?> createVideoController(
    Map<String, String> httpHeaders,
    bool adBlockerEnabled, {
    required bool Function() canInstall,
    int offset = 0,
  }) async {
    startOffset = offset;
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
    );
    final storedFrameInterpolationMode =
        GStorage.getSetting<int>(SettingsKeys.defaultFrameInterpolationMode);
    frameInterpolationMode = FrameInterpolationMode.fromStorageValue(
      storedFrameInterpolationMode,
    );
    if (frameInterpolationMode.enabled && !frameInterpolationMode.available) {
      frameGeneration.beginProbe(FrameGenerationBackend.vulkan);
      frameGeneration.markUnavailable('no validated Vulkan backend');
      await GStorage.putSetting<int>(
        SettingsKeys.defaultFrameInterpolationMode,
        FrameInterpolationMode.off.storageValue,
      );
      frameInterpolationMode = FrameInterpolationMode.off;
      KazumiLogger().w(
        'PlayerController: disabled persisted 3x frame generation after '
        'device-level GPU instability; using original-frame playback',
        forceLog: true,
      );
    }
    KazumiLogger().i(
      'PlayerController: frame interpolation setting '
      'stored=$storedFrameInterpolationMode resolved=${frameInterpolationMode.name}',
      forceLog: true,
    );
    hAenable = GStorage.getSetting(SettingsKeys.hAenable);
    androidEnableOpenSLES =
        GStorage.getSetting(SettingsKeys.androidEnableOpenSLES);
    hardwareDecoder = GStorage.getSetting(SettingsKeys.hardwareDecoder);
    autoPlay = GStorage.getSetting(SettingsKeys.autoPlay);
    playerDebugMode = GStorage.getSetting(SettingsKeys.playerDebugMode);

    if (!canInstall()) {
      return null;
    }
    final candidate = _OwnedPlayer(
      Player(
        configuration: PlayerConfiguration(
          bufferSize: cachePolicy.bufferSize,
          osc: false,
          logLevel: MPVLogLevel.values[debug.playerLogLevel],
          adBlocker: adBlockerEnabled,
        ),
      ),
    );
    final player = candidate.player;
    if (!canInstall()) {
      await candidate.dispose();
      return null;
    }
    _ownedPlayer = candidate;
    cachePolicy.startWatching();

    try {
      debug.playerLog.clear();
      await debug.setup(
        player,
        isCurrentPlayer: isCurrentPlayer,
        playerDebugMode: playerDebugMode,
      );
      debug.reportFrameGeneration(frameGeneration.snapshot);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      var pp = player.platform as NativePlayer;
      // media-kit 默认启用硬盘作为双重缓存，这可以维持大缓存的前提下减轻内存压力
      // media-kit 内部硬盘缓存目录按照 Linux 配置，这导致该功能在其他平台上被损坏
      // 该设置可以在所有平台上正确启用双重缓存
      await pp.setProperty("demuxer-cache-dir", await getPlayerTempPath());
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await cachePolicy.apply();
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await pp.setProperty("af", "scaletempo2=max-speed=8");
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      if (Platform.isAndroid) {
        await pp.setProperty("volume-max", "100");
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        if (androidEnableOpenSLES) {
          await pp.setProperty("ao", "opensles");
        } else {
          await pp.setProperty("ao", "audiotrack");
        }
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      final bool proxyEnable = GStorage.getSetting(SettingsKeys.proxyEnable);
      if (proxyEnable) {
        final String proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
        final formattedProxy = ProxyUtils.getFormattedProxyUrl(proxyUrl);
        if (formattedProxy != null) {
          await pp.setProperty("http-proxy", formattedProxy);
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          KazumiLogger().i('Player: HTTP 代理设置成功 $formattedProxy');
        }
      } else if (SystemProxyService.isActive) {
        final proxy = SystemProxyService.proxyFor('https');
        if (proxy != null) {
          await pp.setProperty("http-proxy", 'http://${proxy.$1}:${proxy.$2}');
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          KazumiLogger().i('Player: 跟随系统代理 http://${proxy.$1}:${proxy.$2}');
        }
      }

      await player.setAudioTrack(
        AudioTrack.auto(),
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      String? videoRenderer;
      if (Platform.isAndroid) {
        final String androidVideoRenderer =
            GStorage.getSetting(SettingsKeys.androidVideoRenderer);

        if (androidVideoRenderer == 'auto') {
          // Android 14 及以上使用基于 Vulkan 的 MPV GPU-NEXT 视频输出，着色器性能更好
          // GPU-NEXT 需要 Vulkan 1.2 支持
          // 避免 Android 13 及以下设备上部分机型 Vulkan 支持不佳导致的黑屏问题
          final int androidSdkVersion =
              await PlatformEnvironmentService.getAndroidSdkVersion();
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          if (androidSdkVersion >= 34) {
            videoRenderer = 'gpu-next';
          } else {
            videoRenderer = 'gpu';
          }
        } else {
          videoRenderer = androidVideoRenderer;
        }
      }

      if (Platform.isAndroid && frameInterpolationMode.enabled) {
        // AFME is an OpenGL ES driver feature. Keep hardware decoding, but
        // force mpv's GPU renderer onto the Android EGL context.
        videoRenderer = 'gpu';
      }

      if (videoRenderer == 'mediacodec_embed') {
        hAenable = true;
        hardwareDecoder = 'mediacodec';
        superResolutionMode = SuperResolutionMode.off;
        frameInterpolationMode = FrameInterpolationMode.off;
      }

      videoController ??= VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: videoRenderer,
          enableHardwareAcceleration: hAenable,
          enableAndroidSurfaceProducer: false,
          hwdec: hAenable ? hardwareDecoder : 'no',
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );
      await pp.waitForVideoControllerInitializationIfAttached;
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      // Select the EGL backend before media is opened. AndroidVideoController
      // will still recreate --vo once its Surface becomes available, so AFME
      // itself is deliberately enabled after the first frame below.
      if (frameInterpolationMode.enabled) {
        await _setMpvOption(pp, 'gpu-api', 'opengl');
        await _setMpvOption(pp, 'gpu-context', 'android');
        if (!await setFrameInterpolation(
          frameInterpolationMode,
          player: player,
        )) {
          throw StateError('Failed to configure Adreno AFME before media open');
        }
      }
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      player.setPlaylistMode(PlaylistMode.none);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      bool showPlayerError = GStorage.getSetting(SettingsKeys.showPlayerError);
      player.stream.error.listen((event) {
        if (showPlayerError) {
          if (!isCurrentPlayer(player)) {
            return;
          }
          if (event.toString().contains('Failed to open') && playerBuffering) {
            KazumiDialog.showToast(
                message: '加载失败, 请尝试更换其他视频来源', showActionButton: true);
          } else {
            KazumiDialog.showToast(
                message: '播放器内部错误 ${event.toString()} ${videoUrl()}',
                duration: const Duration(seconds: 5),
                showActionButton: true);
          }
        }
        KazumiLogger().e('PlayerController: Player intent error ${videoUrl()}',
            error: event);
      });

      if (superResolutionMode != SuperResolutionMode.off) {
        await setShader(superResolutionMode, player: player);
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      await player.open(
        Media(videoUrl(),
            start: Duration(seconds: offset), httpHeaders: httpHeaders),
        play: autoPlay,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      if (frameInterpolationMode.enabled) {
        // Do not await this here: the Video widget is mounted only after this
        // method returns and loading is cleared by PlayerController. Waiting
        // synchronously would prevent the Android Surface (and first frame)
        // from ever existing.
        unawaited(_enableFrameInterpolationOnLiveVideoOutput(
          frameInterpolationMode,
          player,
          videoController!,
        ));
      }

      if (cachePolicy.networkForced) {
        KazumiDialog.showToast(message: '正在使用移动数据，已临时启用低内存模式以减少缓存');
      }

      return player;
    } catch (error, stackTrace) {
      if (identical(_ownedPlayer, candidate)) {
        cachePolicy.stopWatching();
        _ownedPlayer = null;
        videoController = null;
      }
      await candidate.dispose();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    final currentPlayer = player ?? mediaPlayer;
    if (currentPlayer == null) return;
    try {
      var pp = currentPlayer.platform as NativePlayer;
      await pp.waitForPlayerInitialization;
      await pp.waitForVideoControllerInitializationIfAttached;
      if (!identical(mediaPlayer, currentPlayer)) {
        return;
      }
      switch (mode) {
        case SuperResolutionMode.efficiency:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShadersLite,
            ),
          ]);
          break;
        case SuperResolutionMode.quality:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShaders,
            ),
          ]);
          break;
        case SuperResolutionMode.off:
          await pp.command(['change-list', 'glsl-shaders', 'clr', '']);
          break;
      }
      superResolutionMode = mode;
    } catch (e) {
      KazumiLogger().w('PlayerController: failed to set shader', error: e);
    }
  }

  Future<bool> setFrameInterpolation(
    FrameInterpolationMode mode, {
    Player? player,
  }) async {
    final currentPlayer = player ?? mediaPlayer;
    if (currentPlayer == null) return false;

    try {
      final pp = currentPlayer.platform as NativePlayer;
      await pp.waitForPlayerInitialization;
      await pp.waitForVideoControllerInitializationIfAttached;
      if (!identical(mediaPlayer, currentPlayer)) return false;

      if (!mode.enabled) {
        await _setMpvOption(pp, 'adreno-frame-generation', 'no');
        await _setMpvOption(pp, 'interpolation', 'no');
        await _setMpvOption(pp, 'video-sync', 'audio');
        await _setMpvOption(pp, 'display-fps-override', '0');
        frameInterpolationMode = FrameInterpolationMode.off;
        frameGeneration.reset();
        debug.reportFrameGeneration(frameGeneration.snapshot);
        return true;
      }

      if (!mode.available) {
        frameGeneration.beginProbe(FrameGenerationBackend.vulkan);
        frameGeneration.markUnavailable('no validated Vulkan backend');
        debug.reportFrameGeneration(frameGeneration.snapshot);
        return false;
      }

      if (!Platform.isAndroid) {
        throw UnsupportedError('Adreno AFME is only available on Android');
      }

      // Keep mpv's source/audio clock untouched. The patched VO submits the
      // original, 1/3 and 2/3 phases inside each source frame's PTS window.
      await _setMpvOption(pp, 'display-fps-override', '0');
      await _setMpvOption(pp, 'video-sync', 'audio');
      await _setMpvOption(pp, 'interpolation', 'no');
      await _setMpvOption(pp, 'adreno-frame-generation', 'yes');
      final applied = await pp.getProperty(
        'options/adreno-frame-generation',
      );
      if (applied != 'yes') {
        throw StateError(
          'mpv rejected adreno-frame-generation=yes (readback=$applied)',
        );
      }
      frameInterpolationMode = mode;
      KazumiLogger().i(
        'PlayerController: live VO source-timed 3x AFME readback=$applied; '
        'video-sync=audio, interpolation=no, display-fps-override=0',
        forceLog: true,
      );
      return true;
    } catch (error, stackTrace) {
      frameInterpolationMode = FrameInterpolationMode.off;
      frameGeneration.fault(error.toString());
      debug.reportFrameGeneration(frameGeneration.snapshot);
      KazumiLogger().e(
        'PlayerController: failed to enable fixed 3x Adreno AFME frame generation',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _setMpvOption(
    NativePlayer player,
    String name,
    String value,
  ) async {
    // Use mpv's explicit option namespace. A bare property normally bridges to
    // an option with the same name, but media_kit discards the native return
    // code of mpv_set_property_string. The command path plus options/ prefix
    // makes the intended global option write unambiguous.
    await player.command(['set', 'options/$name', value]);
    final applied = await player.getProperty('options/$name');
    final matches =
        applied == value || (value == '0' && double.tryParse(applied) == 0.0);
    if (!matches) {
      throw StateError('mpv option $name=$value read back as $applied');
    }
  }

  Future<void> _enableFrameInterpolationOnLiveVideoOutput(
    FrameInterpolationMode mode,
    Player player,
    VideoController controller,
  ) async {
    try {
      // AndroidVideoController changes vo to null and back to gpu when its
      // Surface is attached. This signal arrives after the Video widget has a
      // real size, so the option update targets the VO actually presenting.
      await controller.waitUntilFirstFrameRendered;
      if (!isCurrentPlayer(player) || !identical(videoController, controller)) {
        return;
      }
      if (!await setFrameInterpolation(mode, player: player)) {
        throw StateError('Failed to configure Adreno AFME on the live VO');
      }
    } catch (error, stackTrace) {
      if (!isCurrentPlayer(player)) return;
      KazumiLogger().e(
        'PlayerController: failed to apply AFME after Android Surface attach',
        error: error,
        stackTrace: stackTrace,
        forceLog: true,
      );
    }
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    this.playerSpeed = playerSpeed;
    try {
      mediaPlayer!.setRate(playerSpeed);
    } catch (e) {
      KazumiLogger()
          .e('PlayerController: failed to set playback speed', error: e);
    }
  }

  Future<void> setVolume(double value) async {
    updateVolume(value);
    await syncVolumeToDevice(preciseVolume >= 0 ? preciseVolume : volume);
  }

  @action
  void updateVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = value;
    if (volume.toInt() == value.toInt()) {
      return;
    }
    volume = value;
  }

  /// 外部来源（硬件键、系统面板等）变更音量时同步，并清除手势缓存
  @action
  void applyExternalVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = -1;
    volume = value;
  }

  void invalidatePreciseVolume() {
    preciseVolume = -1;
  }

  Future<void> syncVolumeToDevice([double? value]) async {
    final vol = (value ?? volume).clamp(0.0, 100.0);
    try {
      if (isDesktop()) {
        await mediaPlayer!.setVolume(vol);
      } else {
        await FlutterVolumeController.setVolume(vol / 100);
      }
    } catch (_) {}
  }

  @action
  void syncPlaybackState() {
    final player = mediaPlayer;
    if (player == null) return;

    final PlayerState state;
    try {
      state = player.state;
    } catch (_) {
      return;
    }
    if (playing != state.playing) {
      playing = state.playing;
    }
    if (isBuffering != state.buffering) {
      isBuffering = state.buffering;
    }
    if (currentPosition != state.position) {
      currentPosition = state.position;
    }
    if (buffer != state.buffer) {
      buffer = state.buffer;
    }
    if (duration != state.duration) {
      duration = state.duration;
    }
    if (completed != state.completed) {
      completed = state.completed;
    }
  }

  Future<void> playOrPause({
    required Future<void> Function() pause,
    required Future<void> Function() play,
  }) async {
    if (playerPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    cachePolicy.stopWatching();
    final ownedPlayer = _ownedPlayer;
    _ownedPlayer = null;
    videoController = null;
    playing = false;
    loading = true;
    // media_kit stops playback as part of disposal before releasing native
    // resources. Debug subscriptions can be cancelled concurrently.
    await Future.wait([
      ownedPlayer?.dispose() ?? Future<void>.value(),
      _cancelDebugInfo(),
    ]);
  }

  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async {
    return await mediaPlayer!.screenshot(format: format);
  }

  Future<Uint8List?> screenshotPng() async {
    final player = mediaPlayer;
    if (player == null) {
      return null;
    }
    return await screenshotService.capturePng(player);
  }
}
