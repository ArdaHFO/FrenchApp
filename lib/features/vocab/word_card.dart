import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../motion/flip_card.dart';
import '../../motion/motion_tokens.dart';
import '../../domain/level.dart';
import '../../domain/word.dart';
import '../../ui/game_ui.dart';
import 'highlighted_sentence.dart';

/// Kelime kartı. Ön yüz sadece Fransızca, arka yüz İngilizce ve Türkçe.
/// PLAN.md bölüm 5.1'deki tasarıma karşılık gelir.
class WordCard extends StatelessWidget {
  const WordCard({
    super.key,
    required this.word,
    this.showSentenceOnFront = true,
    this.onSpeak,
    this.onFlag,
    this.isFlagged = false,
    this.relatives = const <Word>[],
    this.mastery = 0,
  });

  final Word word;

  /// Aynı kökten gelen kelimeler. Arka yüzde gösterilir; bir kelimeyi
  /// ailesiyle birlikte görmek tek tek ezberlemekten verimlidir.
  final List<Word> relatives;

  /// Ayarlardan kapatılabilir. Kapalıyken anlamı tahmin etmek zorlaşır
  /// ama kendini test etme değeri artar.
  final bool showSentenceOnFront;

  final void Function(String text)? onSpeak;

  /// "Bu kartta hata var" düğmesi. Otomatik üretilen içerikte hata
  /// kaçınılmaz; bu düğme temizliği zamana yayar.
  final VoidCallback? onFlag;

  final bool isFlagged;

  /// SRS kutusu. Kartın öğrenme koleksiyonundaki bronz-gümüş-altın hissini
  /// görünür kılar; 0 yeni, 5 tam ustalık.
  final int mastery;

  @override
  Widget build(BuildContext context) {
    final Color accent = AppTheme.levelColor(word.level.index);
    return FlipCard(
      front: _CardShell(
        accent: accent,
        child: _FrontFace(
          word: word,
          accent: accent,
          showSentence: showSentenceOnFront,
          onSpeak: onSpeak,
          mastery: mastery,
        ),
      ),
      back: _CardShell(
        accent: accent,
        child: _BackFace(
          word: word,
          accent: accent,
          relatives: relatives,
          onFlag: onFlag,
          isFlagged: isFlagged,
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, required this.accent});

  final Widget child;

  /// Seviye rengi. Kartın üst şeridinde ve zemin gradyanında görünür.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final Color base = AppTheme.cardColor(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        // Düz renk yerine çok hafif bir gradyan: kart düz bir dikdörtgen
        // değil, ışık alan bir yüzey gibi duruyor. Fark bilinçli olarak
        // küçük, dikkat dağıtmasın diye.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.alphaBlend(accent.withValues(alpha: 0.10), base),
            base,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            // Bulanıklık sabit tutulur, sürüklemede yeniden hesaplanmaz.
            blurRadius: MotionTokens.shadowBlur,
            offset: const Offset(0, MotionTokens.shadowRestOffsetY),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Üst şerit: seviyeyi yazı okumadan belli eder.
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            child: Container(height: 4, color: accent),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _FrontFace extends StatelessWidget {
  const _FrontFace({
    required this.word,
    required this.accent,
    this.showSentence = true,
    this.onSpeak,
    this.mastery = 0,
  });

  final Word word;
  final Color accent;
  final bool showSentence;
  final void Function(String text)? onSpeak;
  final int mastery;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            _Chip(word.level.code, color: accent),
            _Chip(word.posTr, color: faint),
            if (word.genderTr != null) _Chip(word.genderTr!, color: faint),
            if (word.isIdiom) _Chip('deyim', color: theme.colorScheme.tertiary),
            if (word.isIdiom && word.register != null)
              _Chip(word.register!, color: GameColors.coral),
            if (mastery > 0)
              _Chip(
                mastery >= 5
                    ? 'USTA ★'
                    : mastery >= 3
                        ? 'GÜMÜŞ $mastery'
                        : 'BRONZ $mastery',
                color: mastery >= 5
                    ? const Color(0xFFFFC247)
                    : mastery >= 3
                        ? const Color(0xFFAEB8C4)
                        : const Color(0xFFC47A44),
              ),
          ],
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  word.display,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: word.display.length > 14 ? 30 : 40,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (word.ipa != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    word.ipa!,
                    style: TextStyle(fontSize: 15, color: faint),
                  ),
                ],
                const SizedBox(height: 12),
                IconButton(
                  onPressed:
                      onSpeak == null ? null : () => onSpeak!(word.display),
                  icon: const Icon(Icons.volume_up_rounded, size: 26),
                  color: faint,
                  tooltip: 'Seslendir',
                ),
              ],
            ),
          ),
        ),
        if (showSentence && word.hasExample) ...<Widget>[
          // Cümle hafif renkli bir kutuya alındı: kartın üzerinde ayrı bir
          // katman gibi duruyor, kelimeyle karışmıyor. Hedef kelime cümle
          // içinde kalın ve seviye renginde.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: accent.withValues(alpha: 0.55),
                  width: 3,
                ),
              ),
            ),
            child: HighlightedSentence(
              sentence: word.sentenceFr!,
              lemma: word.lemma,
              highlightColor: accent,
              style: TextStyle(
                fontSize: 16,
                height: 1.35,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        // FittedBox: erişilebilirlik için yazı büyütüldüğünde simge ve
        // metin dar kartta yan yana sığmıyordu. Kırpmak yerine ipucunun
        // tamamı azıcık küçülüyor.
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.touch_app_rounded, size: 14, color: faint),
                const SizedBox(width: 6),
                Text(
                  'Çevirmek için dokun',
                  style: TextStyle(fontSize: 12, color: faint),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackFace extends StatelessWidget {
  const _BackFace({
    required this.word,
    required this.accent,
    this.relatives = const <Word>[],
    this.onFlag,
    this.isFlagged = false,
  });

  final Word word;
  final Color accent;
  final List<Word> relatives;
  final VoidCallback? onFlag;
  final bool isFlagged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Uzun içerik küçük ekranlarda erişilebilir kalır. Dikey hareket
        // içeriği kaydırır; kart işlemleri alttaki düğmelerle de yapılabilir.
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  word.display,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                _MeaningRow(tag: 'EN', text: word.meaningEn),
                const SizedBox(height: 6),
                _MeaningRow(
                  tag: 'TR',
                  text: word.meaningTr,
                  emphasize: true,
                  tagColor: accent,
                ),
                // İçeriğin bir kısmı tek kaynağa dayanıyor. Kullanıcı
                // hangi karşılığa güvenebileceğini bilsin diye söylüyoruz;
                // yanlışsa aşağıdaki bayrak düğmesiyle bildiriyor.
                // Aynı kökten gelenler. Kartta en fazla dördü, tamamı
                // sözlük aramasındaki ayrıntı sayfasında.
                if (relatives.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Aynı kökten',
                        style: TextStyle(fontSize: 11, color: faint),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: <Widget>[
                            for (final Word r in relatives.take(4))
                              Text(
                                r.lemma,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (word.needsReview) ...<Widget>[
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _Chip(
                      'otomatik · doğrulanmadı',
                      color: Color(0xFFD9A21B),
                    ),
                  ),
                ],
                if (word.literalTr != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GameColors.gold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '${word.isIdiom ? "Kelime kelime" : "Birebir"}: '
                      '${word.literalTr}',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.64),
                      ),
                    ),
                  ),
                ],
                if (word.isIdiom && word.noteTr != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(11),
                      border: Border(
                        left: BorderSide(
                          color: accent.withValues(alpha: 0.58),
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      'Kullanım: ${word.noteTr}',
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                  ),
                ],
                if (word.hasExample) ...<Widget>[
                  const SizedBox(height: 14),
                  Divider(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    word.sentenceFr!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                  if (word.sentenceEn != null) ...<Widget>[
                    const SizedBox(height: 10),
                    _MeaningRow(
                      tag: 'EN',
                      text: word.sentenceEn!,
                      small: true,
                      maxLines: 3,
                    ),
                  ],
                  // Türkçe örnek cümle her kelimede yok: veritabanındaki
                  // 12.142 cümlenin 10.091'ine (%83) Türkçe ulaşıyor,
                  // gerisinde satır gizlenir.
                  if (word.sentenceTr != null) ...<Widget>[
                    const SizedBox(height: 6),
                    _MeaningRow(
                      tag: 'TR',
                      text: word.sentenceTr!,
                      small: true,
                      maxLines: 3,
                    ),
                  ],
                  if (word.sentenceAttribution != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      word.sentenceAttribution!,
                      style: TextStyle(fontSize: 10, height: 1.3, color: faint),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: word.noteTr != null && !word.isIdiom
                  ? Text(
                      'Not: ${word.noteTr}',
                      style: TextStyle(fontSize: 12, height: 1.3, color: faint),
                    )
                  : const SizedBox.shrink(),
            ),
            if (onFlag != null)
              IconButton(
                onPressed: onFlag,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: isFlagged
                    ? 'Hata bildirimini geri al'
                    : 'Bu kartta hata var',
                icon: Icon(
                  isFlagged ? Icons.flag_rounded : Icons.outlined_flag_rounded,
                  color: isFlagged ? const Color(0xFFD9A21B) : faint,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MeaningRow extends StatelessWidget {
  const _MeaningRow({
    required this.tag,
    required this.text,
    this.emphasize = false,
    this.small = false,
    this.maxLines = 3,
    this.tagColor,
  });

  final String tag;
  final String text;
  final bool emphasize;
  final bool small;
  final int maxLines;
  final Color? tagColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Chip(tag, color: tagColor ?? theme.colorScheme.tertiary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: small ? 13 : 17,
              height: 1.3,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
              color: theme.colorScheme.onSurface
                  .withValues(alpha: small ? 0.65 : 0.95),
            ),
          ),
        ),
      ],
    );
  }
}
