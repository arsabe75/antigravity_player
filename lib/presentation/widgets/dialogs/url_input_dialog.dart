import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../infrastructure/services/url_validator.dart';
import '../../../infrastructure/services/recent_urls_service.dart';

/// Diálogo mejorado para ingresar URLs de video
class UrlInputDialog extends StatefulWidget {
  const UrlInputDialog({super.key});

  /// Muestra el diálogo y retorna la URL ingresada o null si se cancela
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => const UrlInputDialog(),
    );
  }

  @override
  State<UrlInputDialog> createState() => _UrlInputDialogState();
}

class _UrlInputDialogState extends State<UrlInputDialog> {
  final _controller = TextEditingController();
  final _recentUrlsService = RecentUrlsService();

  ValidationResult? _validationResult;
  List<String> _recentUrls = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecentUrls();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecentUrls() async {
    final urls = await _recentUrlsService.getRecentUrls();
    if (mounted) {
      setState(() {
        _recentUrls = urls;
        _isLoading = false;
      });
    }
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _validationResult = null;
      });
    } else {
      setState(() {
        _validationResult = UrlValidator.validateVideoUrl(text);
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _controller.text = data.text!;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  void _selectUrl(String url) {
    _controller.text = url;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  Future<void> _removeRecentUrl(String url) async {
    await _recentUrlsService.removeUrl(url);
    await _loadRecentUrls();
  }

  void _submit() {
    final url = _controller.text.trim();
    if (url.isNotEmpty && (_validationResult?.isValid ?? false)) {
      _recentUrlsService.addUrl(url);
      Navigator.of(context).pop(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.globe, size: 24),
          const SizedBox(width: 12),
          const Text('Open Network URL'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // URL Input Field
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'https://example.com/video.mp4',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.link),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Validation indicator
                    if (_validationResult != null)
                      Icon(
                        _validationResult!.isValid
                            ? LucideIcons.checkCircle
                            : LucideIcons.xCircle,
                        color: _validationResult!.isValid
                            ? Colors.green
                            : Colors.red,
                        size: 20,
                      ),
                    // Paste button
                    IconButton(
                      icon: const Icon(LucideIcons.clipboard, size: 20),
                      onPressed: _pasteFromClipboard,
                      tooltip: 'Paste from clipboard',
                    ),
                    // Clear button
                    if (_controller.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _validationResult = null;
                          });
                        },
                        tooltip: 'Clear',
                      ),
                  ],
                ),
                errorText: _validationResult?.isValid == false
                    ? _validationResult?.errorMessage
                    : null,
              ),
              autofocus: true,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _submit(),
            ),

            // Domain preview
            if (_controller.text.isNotEmpty &&
                _validationResult?.isValid == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.globe2,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      UrlValidator.getDomain(_controller.text) ?? '',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    if (UrlValidator.getVideoExtension(_controller.text) !=
                        null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.blue[900] : Colors.blue[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '.${UrlValidator.getVideoExtension(_controller.text)}',
                          style: TextStyle(
                            color: isDark ? Colors.blue[200] : Colors.blue[800],
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // Recent URLs
            if (_recentUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(LucideIcons.history, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Recent URLs',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _recentUrls.length,
                  itemBuilder: (context, index) {
                    final url = _recentUrls[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: const Icon(LucideIcons.film, size: 16),
                      title: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        UrlValidator.getDomain(url) ?? '',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      trailing: IconButton(
                        icon: const Icon(LucideIcons.x, size: 14),
                        onPressed: () => _removeRecentUrl(url),
                        tooltip: 'Remove',
                      ),
                      onTap: () => _selectUrl(url),
                    );
                  },
                ),
              ),
            ],

            // Loading indicator
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _validationResult?.isValid == true ? _submit : null,
          icon: const Icon(LucideIcons.play, size: 18),
          label: const Text('Open'),
        ),
      ],
    );
  }
}
