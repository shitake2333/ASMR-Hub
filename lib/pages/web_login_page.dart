import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebLoginPage extends StatefulWidget {
  final String initialUrl;
  final String sourceName;

  const WebLoginPage({
    super.key,
    required this.initialUrl,
    required this.sourceName,
  });

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isSupported = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                });
              }
            },
            onPageFinished: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.initialUrl));
    } catch (e) {
      _isSupported = false;
      _errorMessage = e.toString();
    }
  }

  Future<void> _checkCookies() async {
    if (!_isSupported) return;
    try {
      final Object result = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final String cookies = result.toString();

      if (cookies.isNotEmpty && cookies != '""' && cookies != "null") {
        String rawCookies = cookies;
        if (rawCookies.startsWith('"') && rawCookies.endsWith('"')) {
          rawCookies = rawCookies.substring(1, rawCookies.length - 1);
        }

        if (mounted) {
          Navigator.of(context).pop(rawCookies);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No cookies found yet, please login first'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error getting cookies: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Login to ${widget.sourceName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _checkCookies,
            tooltip: 'I have logged in',
          ),
        ],
      ),
      body: _isSupported
          ? Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
              ],
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'WebView is not supported on this platform.',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
