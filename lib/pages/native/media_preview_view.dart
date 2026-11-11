import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlist_mobile/generated/l10n.dart';
import 'package:video_player/video_player.dart';

/// Native Android/iOS media playback backed by platform decoders.
class MediaPreviewView extends StatefulWidget {
  const MediaPreviewView({
    super.key,
    required this.url,
    required this.headers,
    required this.isVideo,
  });

  final String url;
  final Map<String, String> headers;
  final bool isVideo;

  @override
  State<MediaPreviewView> createState() => _MediaPreviewViewState();
}

class _MediaPreviewViewState extends State<MediaPreviewView> {
  late final VideoPlayerController _controller;
  Object? _error;

  // --- 手势控制相关变量 ---
  double _startY = 0.0;
  double _startVolume = 1.0;
  double _startBrightness = 1.0;
  bool _isDragging = false;
  bool _isLeftSide = false;
  String _overlayText = '';
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.headers,
    )..addListener(_onChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = StateError(S.current.mediaPlaybackUnavailable));
      }
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
  }

  Future<void> _openFullscreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _FullscreenMedia(controller: _controller),
      ),
    );
  }

  String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // --- 手势处理逻辑 ---
  void _onVerticalDragStart(DragStartDetails details) {
    _startY = details.globalPosition.dy;
    _startVolume = _controller.value.volume;
    _isDragging = true;
    
    final screenWidth = MediaQuery.of(context).size.width;
    _isLeftSide = details.globalPosition.dx < screenWidth / 2;
    _startBrightness = 1.0; 
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    
    final screenHeight = MediaQuery.of(context).size.height;
    final deltaY = (_startY - details.globalPosition.dy) / (screenHeight * 0.5);

    if (_isLeftSide) {
      // 调节亮度（通过增加/减少黑色遮罩的透明度来实现）
      double newBrightness = (_startBrightness + deltaY).clamp(0.0, 1.0);
      setState(() {
        _startBrightness = newBrightness;
        _overlayText = '亮度 ${(newBrightness * 100).toInt()}%';
        _showOverlay = true;
      });
    } else {
      // 调节音量
      double newVolume = (_startVolume + deltaY).clamp(0.0, 1.0);
      _controller.setVolume(newVolume);
      setState(() {
        _overlayText = '音量 ${(newVolume * 100).toInt()}%';
        _showOverlay = true;
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isDragging = false;
    setState(() {
      _showOverlay = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(S.current.mediaPlaybackUnavailable));
    }
    final value = _controller.value;
    if (!value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final durationMs = value.duration.inMilliseconds;
    final positionMs = value.position.inMilliseconds.clamp(0, durationMs);

    return Stack(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.isVideo)
              AspectRatio(
                aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                child: GestureDetector(
                  onVerticalDragStart: _onVerticalDragStart,
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: _onVerticalDragEnd,
                  // 使用 Stack 来叠加黑色半透明遮罩实现亮度调节
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPlayer(_controller),
                      IgnorePointer(
                        child: Container(
                          color: Colors.black.withOpacity(1.0 - _startBrightness),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const Icon(Icons.audio_file_outlined, size: 88),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: value.isPlaying ? S.current.pause : S.current.play,
                    onPressed: _togglePlayback,
                    icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                  Text(_time(value.position)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: durationMs > 0 ? durationMs.toDouble() : 1,
                      value: positionMs.toDouble().clamp(
                        0,
                        durationMs > 0 ? durationMs.toDouble() : 1,
                      ),
                      onChanged: durationMs <= 0
                          ? null
                          : (v) => _controller.seekTo(
                              Duration(milliseconds: v.round()),
                            ),
                    ),
                  ),
                  Text(_time(value.duration)),
                  if (widget.isVideo)
                    IconButton(
                      tooltip: S.current.fullscreen,
                      onPressed: _openFullscreen,
                      icon: const Icon(Icons.fullscreen),
                    ),
                ],
              ),
            ),
            if (value.isBuffering) const LinearProgressIndicator(),
            if (_controller.value.hasError)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(S.current.mediaPlaybackInterrupted),
              ),
          ],
        ),
        if (_showOverlay)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _overlayText,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ),
      ],
    );
  }
}

class _FullscreenMedia extends StatelessWidget {
  const _FullscreenMedia({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio > 0
              ? controller.value.aspectRatio
              : 16 / 9,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
