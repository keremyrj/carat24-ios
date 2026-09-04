# Carat24 iOS

Carat24'ün iPhone ve iPad için hazırlanan yerel uygulama kabuğudur. Canlı web sistemini değiştirmez; mevcut hesap, ayar, fiyat ve yansıtma ekranlarını güvenli HTTPS bağlantısıyla kullanır.

## Özellikler

- Uygulama içi kullanıcı girişi
- Kalıcı WebKit oturumu; kullanıcı her açılışta yeniden giriş yapmaz
- Kâr ve Ayarlar, Yansıtma ve Yönetim Paneli alt menüsü
- Yansıtma seçildiğinde panel ayarlarını kaydedip birinci ekran fiyat görünümünü açma
- Geri kaydırma, aşağı çekerek yenileme ve çevrimdışı uyarısı
- iPhone ve iPad desteği

## Mac satın almadan derleme

1. Bu klasörü özel bir Git deposuna gönderin.
2. Kiralık bir bulut Mac veya macOS bulut derleme hizmetinde Xcode 26 ve XcodeGen kurun.
3. Proje klasöründe `xcodegen generate` çalıştırın.
4. Oluşan `Carat24.xcodeproj` dosyasını Xcode'da açın.
5. Apple Developer takımını seçin ve `com.ceremybilisim.carat24` Bundle ID'sini hesabınızda oluşturun.
6. Önce TestFlight'a yükleyip iPhone'da test edin; ardından App Store incelemesine gönderin.

## Güvenlik

- Yalnızca `ceremybilisim.com` ve `www.ceremybilisim.com` uygulama içinde açılır.
- Başka web adresleri Safari'ye gönderilir.
- HTTP ve geçersiz TLS bağlantılarına izin verilmez.
- Uygulama reklam/izleme SDK'sı içermez.
