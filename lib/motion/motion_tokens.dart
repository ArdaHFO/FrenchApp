import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Uygulamadaki bütün süre, eğri, yay ve eşik değerleri burada durur.
///
/// Kural: hiçbir widget kendi içinde `Duration(...)` veya `Curves.x` yazmaz.
/// Hareketin hissini ayarlamak bu tek dosyada sayı değiştirmek olmalıdır.
class MotionTokens {
  MotionTokens._();

  /// Ayarlardan gelen animasyon hızı. 0.75 yavaş, 1.0 normal, 1.25 hızlı.
  /// Bütün süreler bu değere bölünerek okunur.
  static double speedScale = 1.0;

  /// Erişilebilirlik ayarı. Hareket tamamen yok olmaz; durum değişiklikleri
  /// anlaşılır kalırken uzun yolculuk ve kutlama süreleri kısalır.
  static bool reducedMotion = false;

  static Duration _scaled(int milliseconds) {
    final double reduction = reducedMotion ? 0.25 : 1.0;
    return Duration(
      microseconds: (milliseconds * 1000 * reduction / speedScale).round(),
    );
  }

  // ---------------------------------------------------------------- süreler

  /// Kartın eşiği geçtikten sonra ekran dışına uçması.
  static Duration get cardFlyOut => _scaled(280);

  /// Yeni kartın destede yerine oturması.
  static Duration get cardSettle => _scaled(350);

  /// Kartın ön yüzden arka yüze dönmesi.
  static Duration get cardFlip => _scaled(450);

  /// Yön rozetinin belirmesi.
  static Duration get badgeIn => _scaled(150);

  /// Üstteki oturum ilerleme çubuğunun dolması.
  static Duration get progressFill => _scaled(400);

  /// Sekmeler arası sayfa geçişi.
  static Duration get pageTransition => _scaled(300);

  /// Oturum sonu özetinde sayıların artması.
  static Duration get counterRise => _scaled(800);

  /// Seçim durumu değişimi (seviye kartı, tema çipi, sekme).
  static Duration get selection => _scaled(200);

  /// Düğme ve kartın parmak altında sıkışması.
  static Duration get press => _scaled(110);

  /// Büyük kahraman görsellerinin çok yavaş, dikkat dağıtmayan döngüsü.
  static Duration get ambientLoop => _scaled(9000);

  /// Ödül ve doğru cevap nesnelerinin yaylanarak sahneye girmesi.
  static Duration get rewardPop => _scaled(520);

  /// Quizde şık seçildikten sonra doğru cevabın okunması için beklenen süre.
  static Duration get quizReveal => _scaled(900);

  /// Yolculuk haritası açılırken yolun çizilme süresi.
  static Duration get mapIntro => _scaled(1100);

  /// Gezginin bir duraktan diğerine yürüme süresi.
  static Duration get mapTravel => _scaled(900);

  /// Ses/video konumu için dengeli arayüz yenileme aralığı. Medya akışı
  /// bundan daha sık gelse bile bütün sayfanın gereksiz çizilmesini önler.
  static const Duration mediaPositionUpdate = Duration(milliseconds: 300);

  // ---------------------------------------------------------------- eğriler

  static const Curve flyOut = Curves.easeInQuad;
  static const Curve settle = Curves.easeOutCubic;
  static const Curve flip = Curves.easeOutCubic;
  static const Curve badge = Curves.easeOutBack;
  static const Curve progress = Curves.easeOutCubic;
  static const Curve counter = Curves.easeOutExpo;

  // ------------------------------------------------------------------- yay

  /// Eşiği geçmeden bırakılan kartın yerine dönüşü.
  /// Sertlik arttıkça keskin ama sert, azaldıkça yumuşak ama gecikmeli hisseder.
  /// Telefonda elle ayarlanacak asıl sayılar bunlar.
  static const SpringDescription returnSpring = SpringDescription(
    mass: 1.0,
    stiffness: 500.0,
    damping: 30.0,
  );

  // ------------------------------------------------------ sürükleme fiziği

  /// Kartın en fazla dönme açısı (16 derece).
  static const double maxRotationRadians = 16 * math.pi / 180;

  /// Yatay eşik, kart genişliğinin oranı olarak.
  static const double thresholdFraction = 0.28;

  /// Dikey eşik. Dikey mesafe daha uzun olduğu için oran daha küçük tutulur.
  static const double thresholdFractionVertical = 0.18;

  /// Bu hızın üstünde bırakılan kart, mesafe eşiğini geçmese de uçar (px/s).
  static const double velocityThreshold = 800.0;

  /// Hız eşiğinin sayılması için gereken en az sürükleme mesafesi (px).
  /// Yanlışlıkla dokunmanın kartı fırlatmasını engeller.
  static const double velocityMinTravel = 24.0;

  /// Kartın ekran dışına ne kadar uzağa gideceği (ekran boyutunun katı).
  static const double flyOutOvershoot = 1.35;

  // ----------------------------------------------------------------- deste

  /// Aynı anda görünen kart sayısı.
  static const int visibleCards = 3;

  /// Derinliğe göre ölçek, dikey kayma ve opaklık. Sıra: üstteki kart önce.
  static const List<double> depthScale = <double>[1.00, 0.95, 0.90];
  static const List<double> depthOffsetY = <double>[0.0, 12.0, 24.0];
  static const List<double> depthOpacity = <double>[1.00, 0.80, 0.55];

  // -------------------------------------------------------------- çevirme

  /// Üç boyutlu dönmenin perspektif derinliği.
  /// Büyütülürse balıkgözü etkisi, küçültülürse düz yassılaşma olur.
  static const double perspective = 0.0012;

  /// Çevirmenin ortasında kartın ne kadar büyüyeceği.
  static const double flipScaleBoost = 0.04;

  // ------------------------------------------------------- renk ve rozet

  /// Sürükleme sırasında kartın üstündeki renk katmanının en yüksek opaklığı.
  static const double overlayMaxOpacity = 0.35;

  /// Rozetin belirmeye başladığı ölçek.
  static const double badgeMinScale = 0.70;

  /// Eşik geçildiğinde rozetin anlık büyüme oranı.
  static const double badgeOverThresholdScale = 1.08;

  // -------------------------------------------------------------- gölge

  /// Gölgenin bulanıklığı sürükleme boyunca sabit tutulur.
  /// Değişen bulanıklık her karede yeniden hesaplanır ve pahalıdır.
  static const double shadowBlur = 24.0;
  static const double shadowRestOffsetY = 6.0;
  static const double shadowLiftOffsetY = 18.0;
}
