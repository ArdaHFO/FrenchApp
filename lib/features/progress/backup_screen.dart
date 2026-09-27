import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../data/backup.dart';

/// İlerlemeyi dışa/içe aktarma.
///
/// Dosya seçici ya da paylaşım paketi eklemeden çalışır: yedek hem
/// cihazdaki bir dosyaya yazılır hem panoya kopyalanır. Geri yüklerken
/// metni yapıştırman yeterli.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.exportDirectory});

  /// Tests supply a temporary directory without invoking Android storage APIs.
  @visibleForTesting
  final Future<Directory> Function()? exportDirectory;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final TextEditingController _paste = TextEditingController();

  AppState? _app;
  String? _savedPath;
  String? _message;
  bool _busy = false;
  bool _confirming = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= AppScope.of(context);
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_busy || _confirming) return;
    setState(() => _busy = true);
    try {
      final String json = await _app!.exportProgress();

      // Dosya, uygulamanın dış klasörüne yazılır: dosya yöneticisinden
      // Android/data/... altında görünür ve izin gerektirmez.
      final Directory target;
      if (widget.exportDirectory != null) {
        target = await widget.exportDirectory!();
      } else {
        final Directory? dir = await getExternalStorageDirectory();
        target = dir ?? await getApplicationSupportDirectory();
      }
      final String stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final File file = File(p.join(target.path, 'frenchapp-$stamp.json'));
      await file.writeAsString(json, flush: true);

      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      setState(() {
        _savedPath = file.path;
        _message = 'Yedek alındı ve panoya kopyalandı '
            '(${(json.length / 1024).toStringAsFixed(0)} KB).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Yedek alınamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy || _confirming) return;
    final String text = _paste.text.trim();
    if (text.isEmpty) {
      setState(() => _message = 'Önce yedek metnini yapıştır.');
      return;
    }
    _confirming = true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Mevcut ilerleme silinecek'),
        content: const Text(
          'Geri yükleme birleştirme yapmaz, üzerine yazar. '
          'Bu cihazdaki kart durumları, seri ve harita ilerlemesi '
          'yedektekiyle değiştirilecek.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Geri yükle'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final ImportReport report =
          await _app!.restoreProgress(text);
      if (!mounted) return;
      setState(() {
        _message = '$report\nİlerleme ve ayarlar hemen yenilendi.';
        _paste.clear();
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Geri yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Scaffold(
      appBar: AppBar(title: const Text('Yedekleme')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            Text(
              'İlerlemen yalnızca bu telefonda duruyor. Uygulamayı silersen '
              'ya da telefon değiştirirsen kaybolur. Yedek; kart durumlarını, '
              'günlük seriyi, harita ilerlemesini ve ayarları taşır.',
              style: TextStyle(fontSize: 14, height: 1.5, color: faint),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Yedek al'),
            ),
            if (_savedPath != null) ...<Widget>[
              const SizedBox(height: 10),
              SelectableText(
                _savedPath!,
                style: TextStyle(fontSize: 11, color: faint),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Geri yükle',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Yedek metnini buraya yapıştır.',
              style: TextStyle(fontSize: 13, color: faint),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _paste,
              maxLines: 6,
              minLines: 3,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{ "format": 1, ... }',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final ClipboardData? d =
                                await Clipboard.getData('text/plain');
                            if (mounted && d?.text != null) {
                              _paste.text = d!.text!;
                            }
                          },
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Panodan al'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('Geri yükle'),
                  ),
                ),
              ],
            ),
            if (_app!.recoveryRequired)
              FilledButton(
                onPressed: _busy ? null : () async {
                  setState(() => _busy = true);
                  try {
                    await _app!.recoverProgress();
                    if (mounted) setState(() => _message = 'İlerleme yeniden yüklendi.');
                  } catch (e) {
                    if (mounted) setState(() => _message = '$e');
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
                child: const Text('İlerlemeyi yeniden yükle'),
              ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
