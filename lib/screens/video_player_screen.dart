import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:nexus/services/playback_position_store.dart';
import 'package:nexus/theme/nexus_theme.dart';

/// Integrierter NEXUS-Player (Master-Prompt Kapitel 26).
/// Enthält: Play/Pause, Seek, Geschwindigkeit, Lautstärke, Vollbild,
/// Fortschrittsanzeige, Wiedergabeposition speichern + Resume-Prompt.
///
/// (Noch NICHT enthalten: Picture-in-Picture, Untertitel, mehrere
/// Audiospuren, Kapitel — siehe README/Statusnotiz. `video_player` bietet
/// dafür keine native Unterstützung; das bräuchte eigene Zusatzpakete.)
class NexusVideoPlayerScreen extends StatefulWidget {
  final String path;
  final String title;

  const NexusVideoPlayerScreen({super.key, required this.path, required this.title});

  @override
  State<NexusVideoPlayerScreen> createState() => _NexusVideoPlayerScreenState();
}

class _NexusVideoPlayerScreenState extends State<NexusVideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _ready = false;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  bool _muted = false;
  double _lastVolume = 1.0;
  double _speed = 1.0;
  Timer? _hideTimer;
  Timer? _saveTimer;

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      _controller.addListener(_onTick);
      setState(() => _ready = true);

      final saved = await PlaybackPositionStore.load(widget.path);
      final duration = _controller.value.duration;
      if (saved != null &&
          saved > const Duration(seconds: 5) &&
          duration - saved > const Duration(seconds: 5) &&
          mounted) {
        final resume = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: NexusColors.raised,
            title: const Text('Weiterschauen?'),
            content: Text('Bei ${_fmt(saved)} fortsetzen?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Von vorne')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fortsetzen')),
            ],
          ),
        );
        if (resume == true) {
          await _controller.seekTo(saved);
        }
      }
      await _controller.play();
      _resetHideTimer();
      _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _persistPosition());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Wiedergabe fehlgeschlagen: $e')));
      }
    }
  }

  void _onTick() {
    if (!mounted) return;
    final value = _controller.value;
    if (value.position >= value.duration && value.duration > Duration.zero) {
      PlaybackPositionStore.clear(widget.path);
    }
    setState(() {});
  }

  Future<void> _persistPosition() async {
    if (!_controller.value.isInitialized) return;
    final pos = _controller.value.position;
    final dur = _controller.value.duration;
    if (dur - pos < const Duration(seconds: 3)) {
      await PlaybackPositionStore.clear(widget.path);
    } else {
      await PlaybackPositionStore.save(widget.path, pos);
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) setState(() => _controlsVisible = false);
    });
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      _persistPosition();
    } else {
      _controller.play();
    }
    _resetHideTimer();
  }

  void _seekRelative(int seconds) {
    final target = _controller.value.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _controller.value.duration ? _controller.value.duration : target);
    _controller.seekTo(clamped);
    _resetHideTimer();
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _controller.setVolume(_muted ? 0 : _lastVolume);
    });
  }

  void _cycleSpeed() {
    final idx = _speeds.indexOf(_speed);
    final next = _speeds[(idx + 1) % _speeds.length];
    setState(() => _speed = next);
    _controller.setPlaybackSpeed(next);
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _persistPosition();
    _controller.removeListener(_onTick);
    _controller.dispose();
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: !_ready
            ? const Center(child: CircularProgressIndicator(color: NexusColors.accent))
            : GestureDetector(
                onTap: () => _controlsVisible ? setState(() => _controlsVisible = false) : _resetHideTimer(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: _controller.value.size.width > 0
                          ? AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller))
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.audiotrack_rounded, size: 64, color: NexusColors.accent),
                              ],
                            ),
                    ),
                    if (_controlsVisible) _buildControls(context),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final value = _controller.value;
    final pos = value.position;
    final dur = value.duration;
    final maxMs = dur.inMilliseconds.toDouble();
    final posMs = pos.inMilliseconds.toDouble().clamp(0, maxMs == 0 ? 1 : maxMs);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.55), Colors.transparent, Colors.black.withOpacity(0.75)],
          stops: const [0, 0.4, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  Expanded(
                    child: Text(widget.title, style: NexusFonts.ui(size: 13, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    onPressed: _cycleSpeed,
                    child: Text('${_speed}x', style: NexusFonts.monoAccent(size: 13)),
                  ),
                  IconButton(
                    icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                    onPressed: _toggleMute,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
                  onPressed: () => _seekRelative(-10),
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: Icon(value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: NexusColors.accent, size: 56),
                  onPressed: _togglePlay,
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
                  onPressed: () => _seekRelative(10),
                ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(_fmt(pos), style: NexusFonts.mono(size: 11, color: Colors.white)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: NexusColors.accent,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: NexusColors.accent,
                        trackHeight: 2.5,
                      ),
                      child: Slider(
                        value: maxMs > 0 ? posMs.toDouble() : 0,
                        max: maxMs > 0 ? maxMs : 1,
                        onChangeStart: (_) => _hideTimer?.cancel(),
                        onChanged: (v) => setState(() {}),
                        onChangeEnd: (v) {
                          _controller.seekTo(Duration(milliseconds: v.round()));
                          _resetHideTimer();
                        },
                      ),
                    ),
                  ),
                  Text(_fmt(dur), style: NexusFonts.mono(size: 11, color: Colors.white)),
                  IconButton(
                    icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
