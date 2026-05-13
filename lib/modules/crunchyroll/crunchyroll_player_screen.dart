import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:windyomi/main.dart';
import 'package:windyomi/utils/global_style.dart';
import 'package:windyomi/utils/system_ui.dart';

class CrunchyrollPlayerScreen extends StatefulWidget {
  final String? initialUrl;
  final String? title;
  final String? episodeTitle;
  final int? episodeNumber;
  final int? episodeCount;

  const CrunchyrollPlayerScreen({
    super.key,
    this.initialUrl,
    this.title,
    this.episodeTitle,
    this.episodeNumber,
    this.episodeCount,
  });

  @override
  State<CrunchyrollPlayerScreen> createState() =>
      _CrunchyrollPlayerScreenState();
}

class _CrunchyrollPlayerScreenState extends State<CrunchyrollPlayerScreen> {
  static final WebUri _homeUrl = WebUri('https://www.crunchyroll.com/');

  InAppWebViewController? _controller;
  Timer? _hideControlsTimer;
  Timer? _videoStateTimer;

  double _progress = 0;
  String _url = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _isPlaying = false;
  bool _hasVideoElement = false;
  double _playbackSpeed = 1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late int? _episodeNumber = widget.episodeNumber;
  late String? _episodeTitle = widget.episodeTitle;

  String get _seriesTitle => widget.title?.trim().isNotEmpty == true
      ? widget.title!.trim()
      : 'Crunchyroll';

  String get _episodeLabel {
    if (_episodeTitle?.trim().isNotEmpty == true) {
      return _episodeTitle!.trim();
    }
    if (_episodeNumber != null) return 'Episodio $_episodeNumber';
    return 'Crunchyroll';
  }

  WebUri get _initialUrl {
    final value = widget.initialUrl;
    if (value == null || value.trim().isEmpty) return _homeUrl;
    return WebUri(value.trim());
  }

  @override
  void initState() {
    super.initState();
    _url = _initialUrl.toString();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _scheduleControlsHide();
    _videoStateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshVideoState(),
    );
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _videoStateTimer?.cancel();
    restoreSystemUI();
    super.dispose();
  }

  void _showControls() {
    if (!mounted) return;
    setState(() {
      _controlsVisible = true;
    });
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  Future<void> _refreshState(InAppWebViewController controller) async {
    final currentUrl = await controller.getUrl();
    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();

    if (!mounted) return;
    setState(() {
      _url = currentUrl?.toString() ?? _url;
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
    await _refreshVideoState();
  }

  Future<void> _refreshVideoState() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      final result = await controller.evaluateJavascript(
        source: '''
(() => {
  const video = document.querySelector('video');
  if (!video) return null;
  return JSON.stringify({
    paused: video.paused,
    currentTime: Number.isFinite(video.currentTime) ? video.currentTime : 0,
    duration: Number.isFinite(video.duration) ? video.duration : 0,
    rate: video.playbackRate || 1
  });
})();
''',
      );

      if (!mounted) return;
      if (result is! String || result == 'null') {
        setState(() {
          _hasVideoElement = false;
          _isPlaying = false;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
        return;
      }

      final data = jsonDecode(result) as Map<String, dynamic>;
      setState(() {
        _hasVideoElement = true;
        _isPlaying = data['paused'] != true;
        _position = Duration(
          milliseconds: (((data['currentTime'] as num?) ?? 0) * 1000).round(),
        );
        _duration = Duration(
          milliseconds: (((data['duration'] as num?) ?? 0) * 1000).round(),
        );
        _playbackSpeed = ((data['rate'] as num?) ?? 1).toDouble();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasVideoElement = false;
      });
    }
  }

  Future<void> _runVideoCommand(String source) async {
    _showControls();
    await _controller?.evaluateJavascript(source: source);
    await _refreshVideoState();
  }

  Future<void> _togglePlayback() async {
    await _runVideoCommand('''
(() => {
  const video = document.querySelector('video');
  if (!video) return false;
  if (video.paused) {
    video.play();
  } else {
    video.pause();
  }
  return true;
})();
''');
  }

  Future<void> _seekBy(int seconds) async {
    await _runVideoCommand('''
(() => {
  const video = document.querySelector('video');
  if (!video || !Number.isFinite(video.duration)) return false;
  video.currentTime = Math.max(0, Math.min(video.duration, video.currentTime + $seconds));
  return true;
})();
''');
  }

  Future<void> _seekTo(Duration value) async {
    final seconds = value.inMilliseconds / 1000;
    await _runVideoCommand('''
(() => {
  const video = document.querySelector('video');
  if (!video || !Number.isFinite(video.duration)) return false;
  video.currentTime = Math.max(0, Math.min(video.duration, $seconds));
  return true;
})();
''');
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    setState(() {
      _playbackSpeed = speed;
    });
    await _runVideoCommand('''
(() => {
  const video = document.querySelector('video');
  if (!video) return false;
  video.playbackRate = $speed;
  return true;
})();
''');
  }

  Future<void> _requestVideoFullscreen() async {
    await _runVideoCommand('''
(() => {
  const video = document.querySelector('video');
  if (!video) return false;
  if (video.webkitEnterFullscreen) {
    video.webkitEnterFullscreen();
    return true;
  }
  if (video.requestFullscreen) {
    video.requestFullscreen();
    return true;
  }
  return false;
})();
''');
  }

  Future<void> _loadHome() async {
    _showControls();
    await _controller?.loadUrl(urlRequest: URLRequest(url: _homeUrl));
  }

  Future<void> _shareCurrentUrl() async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: _url,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<NavigationActionPolicy> _handleNavigation(
    NavigationAction navigationAction,
  ) async {
    final uri = navigationAction.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return NavigationActionPolicy.ALLOW;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return NavigationActionPolicy.CANCEL;
  }

  void _showDownloadUnavailable() {
    _showControls();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Descarga no disponible para Crunchyroll por ahora.'),
      ),
    );
  }

  Future<void> _showEpisodeList() async {
    final count = widget.episodeCount ?? 0;
    if (count <= 0) return;
    _showControls();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      builder: (context) {
        final itemCount = count.clamp(1, 120);
        return SafeArea(
          top: false,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              final number = index + 1;
              final selected = number == _episodeNumber;
              return ListTile(
                selected: selected,
                leading: Icon(
                  selected
                      ? Icons.play_circle_fill_rounded
                      : Icons.play_circle_outline_rounded,
                ),
                title: Text('Episodio $number'),
                subtitle: const Text('Crunchyroll'),
                trailing: IconButton(
                  tooltip: 'Descargar',
                  onPressed: _showDownloadUnavailable,
                  icon: const Icon(Icons.download_outlined),
                ),
                onTap: () {
                  setState(() {
                    _episodeNumber = number;
                    _episodeTitle = 'Episodio $number';
                  });
                  context.pop();
                  _controller?.loadUrl(
                    urlRequest: URLRequest(url: _initialUrl),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '--:--';
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildTopOverlay(BuildContext context) {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible && !_isFullscreen ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    BackButton(
                      color: Colors.white,
                      onPressed: () {
                        restoreSystemUI();
                        context.pop();
                      },
                    ),
                    Expanded(
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _seriesTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          _episodeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    if ((widget.episodeCount ?? 0) > 0)
                      IconButton(
                        tooltip: 'Episodios',
                        onPressed: _showEpisodeList,
                        icon: const Icon(
                          Icons.format_list_bulleted_rounded,
                          color: Colors.white,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Descargar',
                      onPressed: _showDownloadUnavailable,
                      icon: const Icon(
                        Icons.download_outlined,
                        color: Colors.white,
                      ),
                    ),
                    PopupMenuButton<int>(
                      popUpAnimationStyle: popupAnimationStyle,
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 0, child: Text('Inicio')),
                        PopupMenuItem(value: 1, child: Text('Actualizar')),
                        PopupMenuItem(value: 2, child: Text('Compartir')),
                        PopupMenuItem(value: 3, child: Text('Abrir fuera')),
                        PopupMenuItem(value: 4, child: Text('Cerrar sesion')),
                      ],
                      onSelected: (value) async {
                        switch (value) {
                          case 0:
                            await _loadHome();
                          case 1:
                            await _controller?.reload();
                          case 2:
                            await _shareCurrentUrl();
                          case 3:
                            await InAppBrowser.openWithSystemBrowser(
                              url: WebUri(_url),
                            );
                          case 4:
                            await CookieManager.instance().deleteCookies(
                              url: _homeUrl,
                            );
                            await _loadHome();
                        }
                      },
                    ),
                  ],
                ),
                if (_progress < 1)
                  LinearProgressIndicator(value: _progress, minHeight: 2)
                else
                  const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    final enabled = _hasVideoElement;
    final activeColor = enabled ? Colors.white : Colors.white38;

    return IgnorePointer(
      ignoring: !_controlsVisible || _isFullscreen,
      child: AnimatedOpacity(
        opacity: _controlsVisible && !_isFullscreen ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(50),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Retroceder 10s',
                  onPressed: enabled ? () => _seekBy(-10) : null,
                  iconSize: 34,
                  icon: Icon(Icons.replay_10_rounded, color: activeColor),
                ),
                IconButton(
                  tooltip: _isPlaying ? 'Pausar' : 'Reproducir',
                  onPressed: enabled ? _togglePlayback : null,
                  iconSize: 54,
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: activeColor,
                  ),
                ),
                IconButton(
                  tooltip: 'Avanzar 10s',
                  onPressed: enabled ? () => _seekBy(10) : null,
                  iconSize: 34,
                  icon: Icon(Icons.forward_10_rounded, color: activeColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay(BuildContext context) {
    final durationMs = _duration.inMilliseconds;
    final positionMs = durationMs <= 0
        ? 0.0
        : _position.inMilliseconds.clamp(0, durationMs).toDouble();
    final maxMs = durationMs <= 0 ? 1.0 : durationMs.toDouble();

    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible && !_isFullscreen ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xCC000000)],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 28, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white30,
                        thumbColor: Colors.white,
                        overlayColor: Colors.white24,
                      ),
                      child: Slider(
                        value: positionMs,
                        max: maxMs,
                        onChanged: _hasVideoElement && durationMs > 0
                            ? (value) {
                                setState(() {
                                  _position = Duration(
                                    milliseconds: value.round(),
                                  );
                                });
                              }
                            : null,
                        onChangeEnd: _hasVideoElement && durationMs > 0
                            ? (value) =>
                                  _seekTo(Duration(milliseconds: value.round()))
                            : null,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Atras',
                          onPressed: _canGoBack
                              ? () async {
                                  _showControls();
                                  await _controller?.goBack();
                                }
                              : null,
                          icon: const Icon(Icons.skip_previous),
                          color: Colors.white,
                          disabledColor: Colors.white38,
                        ),
                        IconButton(
                          tooltip: 'Adelante',
                          onPressed: _canGoForward
                              ? () async {
                                  _showControls();
                                  await _controller?.goForward();
                                }
                              : null,
                          icon: const Icon(Icons.skip_next),
                          color: Colors.white,
                          disabledColor: Colors.white38,
                        ),
                        Text(
                          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        PopupMenuButton<double>(
                          tooltip: 'Velocidad',
                          icon: const Icon(Icons.speed, color: Colors.white),
                          itemBuilder: (context) =>
                              [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                                  .map(
                                    (speed) => PopupMenuItem<double>(
                                      value: speed,
                                      child: Text(
                                        '${speed}x',
                                        style: TextStyle(
                                          fontWeight: _playbackSpeed == speed
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onSelected: _setPlaybackSpeed,
                        ),
                        IconButton(
                          tooltip: 'Descargar',
                          onPressed: _showDownloadUnavailable,
                          icon: const Icon(
                            Icons.download_outlined,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Pantalla completa',
                          onPressed: _requestVideoFullscreen,
                          icon: const Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRevealBand({required Alignment alignment}) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _showControls,
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).padding.vertical + 76,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canGoBack = await _controller?.canGoBack() ?? false;
        if (canGoBack) {
          await _controller?.goBack();
        } else if (context.mounted) {
          restoreSystemUI();
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: InAppWebView(
                  webViewEnvironment: webViewEnvironment,
                  initialUrlRequest: URLRequest(url: _initialUrl),
                  initialSettings: InAppWebViewSettings(
                    allowsAirPlayForMediaPlayback: true,
                    allowsBackForwardNavigationGestures: true,
                    allowsInlineMediaPlayback: true,
                    allowsPictureInPictureMediaPlayback: true,
                    cacheEnabled: true,
                    domStorageEnabled: true,
                    iframeAllow:
                        'autoplay; encrypted-media; fullscreen; picture-in-picture',
                    iframeAllowFullscreen: true,
                    isElementFullscreenEnabled: true,
                    isInspectable: kDebugMode,
                    javaScriptCanOpenWindowsAutomatically: true,
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    sharedCookiesEnabled: true,
                    supportMultipleWindows: true,
                    useShouldOverrideUrlLoading: true,
                  ),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                  },
                  onCreateWindow: (controller, createWindowAction) async {
                    final url = createWindowAction.request.url;
                    if (url != null) {
                      await controller.loadUrl(
                        urlRequest: URLRequest(url: url),
                      );
                    }
                    return true;
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) =>
                      _handleNavigation(navigationAction),
                  onLoadStart: (controller, url) {
                    if (!mounted) return;
                    setState(() {
                      _url = url?.toString() ?? _url;
                      _progress = 0;
                    });
                  },
                  onLoadStop: (controller, url) => _refreshState(controller),
                  onUpdateVisitedHistory: (controller, url, isReload) =>
                      _refreshState(controller),
                  onProgressChanged: (controller, progress) {
                    if (!mounted) return;
                    setState(() {
                      _progress = progress / 100;
                    });
                  },
                  onEnterFullscreen: (controller) {
                    if (!mounted) return;
                    setState(() {
                      _isFullscreen = true;
                    });
                  },
                  onExitFullscreen: (controller) {
                    if (!mounted) return;
                    setState(() {
                      _isFullscreen = false;
                    });
                    _showControls();
                  },
                ),
              ),
            ),
            if (!_controlsVisible) ...[
              _buildRevealBand(alignment: Alignment.topCenter),
              _buildRevealBand(alignment: Alignment.bottomCenter),
            ],
            _buildTopOverlay(context),
            _buildCenterControls(),
            _buildBottomOverlay(context),
          ],
        ),
      ),
    );
  }
}
