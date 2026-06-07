import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/services/subtitle_settings_service.dart';
import '../../l10n/l10n.dart';

class SubtitleConfigDialog extends ConsumerStatefulWidget {
  final VoidCallback? onSettingsChanged;

  const SubtitleConfigDialog({super.key, this.onSettingsChanged});

  @override
  ConsumerState<SubtitleConfigDialog> createState() =>
      _SubtitleConfigDialogState();
}

class _SubtitleConfigDialogState extends ConsumerState<SubtitleConfigDialog> {
  final SubtitleSettingsService _service = SubtitleSettingsService();
  double _fontSize = SubtitleSettingsService.defaultFontSize;
  String _colorName = SubtitleSettingsService.defaultColor;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final size = _service.getFontSize();
    final color = _service.getColor();
    if (mounted) {
      setState(() {
        _fontSize = size;
        _colorName = color;
        _loading = false;
      });
    }
  }

  Future<void> _setFontSize(double value) async {
    setState(() => _fontSize = value);
    await _service.setFontSize(value);
    widget.onSettingsChanged?.call();
  }

  Future<void> _setColor(String colorName) async {
    setState(() => _colorName = colorName);
    await _service.setColor(colorName);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (_loading) {
      return const AlertDialog(
        content: Center(child: CircularProgressIndicator()),
      );
    }

    final mpvScale =
        SubtitleSettingsService.fontSizeToMpvScale(_fontSize);
    final previewColor =
        Color(SubtitleSettingsService.colorNameToFlutterValue(_colorName));

    return AlertDialog(
      title: Text(t.subtitleConfigTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  Text(
                    t.subtitleConfigPreview,
                    style: TextStyle(
                      fontSize: _fontSize,
                      color: previewColor,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                      shadows: const [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(-2, -2),
                        ),
                        Shadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(2, -2),
                        ),
                        Shadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(-2, 2),
                        ),
                        Shadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(2, 2),
                        ),
                        Shadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(-2, 0),
                        ),
                        Shadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(2, 0),
                        ),
                        Shadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(0, -2),
                        ),
                        Shadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Font size section
            Text(
              t.subtitleConfigFontSize,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${_fontSize.toStringAsFixed(1)} px  (mpv: ${mpvScale.toStringAsFixed(0)})',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            Slider(
              value: _fontSize,
              min: SubtitleSettingsService.minFontSize,
              max: SubtitleSettingsService.maxFontSize,
              divisions:
                  ((SubtitleSettingsService.maxFontSize -
                          SubtitleSettingsService.minFontSize) *
                      2)
                  .toInt(),
              label: '${_fontSize.toStringAsFixed(1)} px',
              onChanged: _setFontSize,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${SubtitleSettingsService.minFontSize.toStringAsFixed(0)} px',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
                Text(
                  '${SubtitleSettingsService.maxFontSize.toStringAsFixed(0)} px',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Color section
            Text(
              t.subtitleConfigColor,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: SubtitleSettingsService.availableColors.map((name) {
                final colorValue =
                    SubtitleSettingsService.colorNameToFlutterValue(name);
                final isSelected = name == _colorName;
                return GestureDetector(
                  onTap: () => _setColor(name),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(colorValue),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.settingsClose),
        ),
      ],
    );
  }
}
