# gomuks-ios: natywny wrapper iOS dla gomuks web

## Cel

Aplikacja iOS (Swift, SwiftUI + `WKWebView`) otwierająca istniejący backend gomuks użytkownika (`https://gomuks.balgeriada.com`, dostępny tylko w LAN). Zastępuje PWA z Safari. Instalacja przez sideload niepodpisanej IPA (narzędzie do sideloadu podpisuje ją samo). Bez APNs i bez płatnego konta Apple.

Powiadomienia obsługuje osobny projekt: przekaźnik Web Push do ntfy, robiony w innym repo. Aplikacja ntfy pokazuje powiadomienie, a tap otwiera ten wrapper przez URL `matrix:roomid/<room>/e/<event>`. To repo musi tylko obsłużyć schemat `matrix`.

## Fakty o gomuks web (zweryfikowane w github.com/gomuks/gomuks)

- Deep link: `<serverURL>/#/uri/<encodeURIComponent(matrixURI)>`. Obsługę robi `web/src/ui/MainScreen.tsx`, tak samo działa wrapper Androida `github.com/gomuks/android`.
- Logowanie: zwykły ekran logowania gomuks ustawia cookie `gomuks_auth`. Trwały `WKWebsiteDataStore.default()` wystarczy.
- Nie ustawiaj `window.gomuksAndroid`. Ta flaga przełącza logowanie na natywny bridge (web czeka na event `auth` z natywnej strony) i ukrywa część ustawień. Nie kopiuj bridge'a z wrappera Androida.

## Zakres

SwiftUI + `UIViewRepresentable` z `WKWebView`, target iOS 17.

- **Adres serwera:** domyślnie `https://gomuks.balgeriada.com`, do nadpisania przez `Settings.bundle` (pole tekstowe w systemowych Ustawieniach iOS). Bez własnego ekranu ustawień w aplikacji.
- **`WKWebView`:**
  - `websiteDataStore = .default()`,
  - `allowsInlineMediaPlayback = true`,
  - `mediaTypesRequiringUserActionForPlayback = []`,
  - `isInspectable = true`,
  - `allowsBackForwardNavigationGestures = false` (gomuks ma własne gesty).
- **Linki zewnętrzne:** inny host niż serwer oraz `target=_blank` (przez `WKUIDelegate.createWebViewWith`) otwieraj przez `UIApplication.shared.open`.
- **Uprawnienia:** `WKUIDelegate.requestMediaCapturePermissionFor` zwraca `.grant` (połączenia).
- **`Info.plist`:**
  - `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`,
  - `CFBundleURLTypes` ze schematem `matrix`.
- **Deep link:** `onOpenURL` dla `matrix:...` ładuje `<server>/#/uri/<percent-encoded URL>`. To samo przy zimnym starcie z linku.
- **Safe area i klawiatura:** webview na cały ekran. Po pierwszym teście użytkownika popraw, jeśli treść wchodzi pod notch albo pasek domowy.
- **Ikona:** logo gomuks z `github.com/gomuks/gomuks` (`web/public`), 1024x1024 w `Assets.xcassets`.
- **Bundle ID:** `com.balgeriada.gomuks`, nazwa wyświetlana `gomuks`.

Pomiń w tej wersji: haptykę, share extension, pobieranie plików, bridge JS. Dodaj je dopiero na prośbę użytkownika.

## Build

Projekt generowany przez XcodeGen z `project.yml`. `.xcodeproj` nie trafia do repo.

Workflow `.github/workflows/build.yml` na `macos-15`, uruchamiany na push (każdy branch) i `workflow_dispatch`:
```
brew install xcodegen
xcodegen generate
xcodebuild -project Gomuks.xcodeproj -scheme Gomuks -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir Payload && cp -R build/Build/Products/Release-iphoneos/Gomuks.app Payload/
zip -qr gomuks.ipa Payload
```
Wynik jako `actions/upload-artifact` (`gomuks-ipa`). Przy tagu dodatkowo release na GitHubie z `gomuks.ipa`.

Budżet: minuty macOS w prywatnym repo liczą się x10, zostaje ok. 200 minut miesięcznie. Pushuj rzadko, najlepiej jeden push na skończony etap, a nie po każdym commicie.

## Kolejność

1. `project.yml`, aplikacja i workflow. Push, sprawdzenie, że CI przechodzi i daje artefakt.
2. Użytkownik sideloaduje IPA i testuje: logowanie, trwałość sesji po zabiciu aplikacji, wysyłanie zdjęć, safe area, otwarcie `matrix:` linku z Safari.
3. Poprawki według jego uwag.
