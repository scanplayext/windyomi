import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:windyomi/main.dart';
import 'package:windyomi/utils/global_style.dart';

class CrunchyrollPlayerScreen extends StatefulWidget {
  final String? initialUrl;
  final String? title;

  const CrunchyrollPlayerScreen({super.key, this.initialUrl, this.title});

  @override
  State<CrunchyrollPlayerScreen> createState() =>
      _CrunchyrollPlayerScreenState();
}

class _CrunchyrollPlayerScreenState extends State<CrunchyrollPlayerScreen> {
  static final WebUri _homeUrl = WebUri('https://www.crunchyroll.com/');

  InAppWebViewController? _controller;
  final _searchController = TextEditingController();
  double _progress = 0;
  late String _title = widget.title ?? 'Crunchyroll';
  late String _url = _initialUrl.toString();
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _showSearch = false;
  bool _isFullscreen = false;

  WebUri get _initialUrl {
    final value = widget.initialUrl;
    if (value == null || value.trim().isEmpty) return _homeUrl;
    return WebUri(value.trim());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshState(InAppWebViewController controller) async {
    final currentUrl = await controller.getUrl();
    final title = await controller.getTitle();
    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();

    if (!mounted) return;
    setState(() {
      _url = currentUrl?.toString() ?? _url;
      _title = (title?.trim().isNotEmpty ?? false)
          ? title!.trim()
          : 'Crunchyroll';
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  Future<void> _loadHome() async {
    await _controller?.loadUrl(urlRequest: URLRequest(url: _homeUrl));
  }

  Future<void> _submitSearch(String value) async {
    final input = value.trim();
    if (input.isEmpty) return;

    WebUri uri;
    final parsed = Uri.tryParse(input);
    if (parsed != null && parsed.hasScheme) {
      uri = WebUri.uri(parsed);
    } else {
      uri = WebUri.uri(
        Uri.https('www.crunchyroll.com', '/search', {'q': input}),
      );
    }

    await _controller?.loadUrl(urlRequest: URLRequest(url: uri));
    if (!mounted) return;
    setState(() {
      _showSearch = false;
      _searchController.clear();
    });
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

  Widget _buildToolbar(BuildContext context) {
    final subtitle = _url.replaceFirst(RegExp(r'^https?://'), '');

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: AppBar().preferredSize.height,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: _showSearch
                        ? TextField(
                            controller: _searchController,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Buscar o pegar enlace de Crunchyroll',
                            ),
                            onSubmitted: _submitSearch,
                          )
                        : ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                  ),
                  if (_showSearch)
                    IconButton(
                      tooltip: 'Ir',
                      onPressed: () => _submitSearch(_searchController.text),
                      icon: const Icon(Icons.arrow_forward),
                    )
                  else ...[
                    IconButton(
                      tooltip: 'Buscar',
                      onPressed: () {
                        setState(() {
                          _showSearch = true;
                          _searchController.text = '';
                        });
                      },
                      icon: const Icon(Icons.search),
                    ),
                    PopupMenuButton<int>(
                      popUpAnimationStyle: popupAnimationStyle,
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 0, child: Text('Inicio')),
                        PopupMenuItem(value: 1, child: Text('Actualizar')),
                        PopupMenuItem(value: 2, child: Text('Compartir')),
                        PopupMenuItem(value: 3, child: Text('Abrir fuera')),
                        PopupMenuItem(value: 4, child: Text('Borrar sesion')),
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
                ],
              ),
            ),
            if (!_showSearch)
              SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Atras',
                      onPressed: _canGoBack
                          ? () => _controller?.goBack()
                          : null,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    IconButton(
                      tooltip: 'Adelante',
                      onPressed: _canGoForward
                          ? () => _controller?.goForward()
                          : null,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    IconButton(
                      tooltip: 'Inicio',
                      onPressed: _loadHome,
                      icon: const Icon(Icons.home_outlined),
                    ),
                    IconButton(
                      tooltip: 'Actualizar',
                      onPressed: () => _controller?.reload(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            if (_progress < 1)
              LinearProgressIndicator(value: _progress)
            else
              const SizedBox(height: 2),
          ],
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
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            if (!_isFullscreen) _buildToolbar(context),
            Expanded(
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
                    await controller.loadUrl(urlRequest: URLRequest(url: url));
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
