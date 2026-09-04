# Carat24 iOS — Son Adımlar

Fiziksel Mac satın almanız gerekmiyor. Proje Windows'ta hazırlandı; Apple'ın zorunlu tuttuğu derleme ve imzalama işlemi geçici bir bulut Mac üzerinde yapılacak.

## Sizden gerekecekler

1. Apple Developer Program üyeliği.
2. App Store Connect'te `Carat24` adında iOS uygulama kaydı.
3. Bundle ID: `com.ceremybilisim.carat24`
4. Uygulamanın App Store'da görünecek destek e-postası ve iletişim bilgileri.

## İzleyeceğimiz sıra

1. Proje özel bir Git deposuna yüklenir.
2. Bulut Mac'te XcodeGen ile proje oluşturulur.
3. iPhone simülatör derlemesi alınır ve hatalar düzeltilir.
4. Apple hesabıyla otomatik imzalama açılır.
5. İlk paket TestFlight'a yüklenir.
6. Kendi iPhone'unuza TestFlight uygulamasından Carat24 kurulur.
7. Giriş, oturum hatırlama, üç alt menü ve yansıtma akışı gerçek telefonda denenir.
8. Test onayından sonra App Store incelemesine gönderilir.

## App Store uygulama bilgileri

- Uygulama adı: Carat24
- Bundle ID: `com.ceremybilisim.carat24`
- Sürüm: `1.0.0`
- Ana dil: Türkçe
- Desteklenen cihazlar: iPhone ve iPad
- Gizlilik: Reklam ve izleme SDK'sı yoktur; mevcut Ceremy Bilişim hesabıyla giriş yapılır.

## Canlı sistem güvenliği

Bu iOS projesi `ceremybilisim.com` üzerindeki canlı kodu veya veri tabanını değiştirmez. Uygulama, mevcut HTTPS sayfalarını giriş yapan kullanıcı için gösterir.
