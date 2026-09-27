import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Fransızca seslendirme.
///
/// Cihazın kendi konuşma motorunu kullanır, ek ses dosyası indirmez.
/// Fransızca dil paketi kurulu değilse sessizce başarısız olur ve
/// [available] false döner; uygulama sessiz de tam çalışır.
class TtsService {
  TtsService._(this._tts, this.available);

  final FlutterTts _tts;
  final bool available;

  static TtsService? _instance;
  static Future<TtsService>? _loading;
  static const double defaultRate = 0.45;

  static Future<TtsService> instance() async {
    final TtsService? existing = _instance;
    if (existing != null) return existing;

    final Future<TtsService>? loading = _loading;
    if (loading != null) return loading;

    final Future<TtsService> future = _create();
    _loading = future;
    try {
      return await future;
    } finally {
      _loading = null;
    }
  }

  static Future<TtsService> _create() async {
    final FlutterTts tts = FlutterTts();
    bool ok = false;
    try {
      final dynamic languages = await tts.getLanguages;
      if (languages is List) {
        ok = languages.any(
          (dynamic l) => l.toString().toLowerCase().startsWith('fr'),
        );
      }
      if (ok) {
        await tts.setLanguage('fr-FR');
        await tts.setSpeechRate(defaultRate);
        await tts.setPitch(1.0);
        await tts.awaitSpeakCompletion(false);
      }
    } catch (e) {
      debugPrint('TTS hazırlanamadı: $e');
      ok = false;
    }

    final TtsService service = TtsService._(tts, ok);
    _instance = service;
    return service;
  }

  Future<void> speak(String text, {double rate = defaultRate}) async {
    if (!available || text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS okuyamadı: $e');
    }
  }

  Future<void> stop() async {
    if (!available) return;
    await _tts.stop();
  }
}
