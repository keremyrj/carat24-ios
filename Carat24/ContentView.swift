import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.95, blue: 0.91)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                BrowserView(webView: browser.webView)
                    .overlay {
                        if browser.isOffline {
                            OfflineView(retry: browser.retry)
                        }
                    }

                if browser.showsBottomBar {
                    BottomNavigation()
                        .environmentObject(browser)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: browser.showsBottomBar)
        .task { browser.start() }
        .alert(item: $browser.availableUpdate) { update in
            Alert(
                title: Text("Yeni sürüm hazır"),
                message: Text("Carat24 \(update.version) yayınlandı. En güncel özellikler için uygulamayı güncelleyin."),
                primaryButton: .default(Text("App Store’da Güncelle"), action: browser.openAvailableUpdate),
                secondaryButton: .cancel(Text("Daha sonra"))
            )
        }
    }
}

private struct BottomNavigation: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 4) {
            TabButton(title: "Kâr ve Ayarlar", systemImage: "slider.horizontal.3", selected: browser.section == .settings) {
                browser.open(.settings)
            }
            TabButton(title: "Yansıtma", systemImage: "rectangle.on.rectangle", selected: browser.section == .display) {
                browser.open(.display)
            }
            TabButton(title: "Yönetim Paneli", systemImage: "briefcase", selected: browser.section == .management) {
                browser.open(.management)
            }
        }
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .padding(.bottom, 3)
        .frame(minHeight: 55)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct TabButton: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: selected ? .bold : .semibold))
                Text(title)
                    .font(.system(size: 10, weight: selected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(selected ? Color(red: 0.65, green: 0.43, blue: 0.07) : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Color(red: 0.96, green: 0.91, blue: 0.80) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct OfflineView: View {
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.10, blue: 0.13)
            VStack(spacing: 18) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 42, weight: .semibold))
                Text("İnternet bağlantısı bekleniyor")
                    .font(.title3.bold())
                Text("Bağlantınızı kontrol edip yeniden deneyin.")
                    .foregroundStyle(.secondary)
                Button("Yeniden Dene", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.68, green: 0.46, blue: 0.10))
            }
            .multilineTextAlignment(.center)
            .padding(28)
            .foregroundStyle(.white)
        }
    }
}
