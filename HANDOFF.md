# gomuks-ios: natywny wrapper iOS dla gomuks web

## Cel

Aplikacja iOS (Swift, SwiftUI + UIKit, jeden `WKWebView`) otwierająca backend gomuks użytkownika. Zastępuje PWA z Safari. Instalacja: niepodpisana IPA z artefaktu GitHub Actions, uruchamiana przez LiveContainer (skrót na ekranie domowym, nie osobna ikona). Bez APNs i płatnego konta Apple.

## Ograniczenia LiveContainer

- `Settings.bundle` i skróty z ikony (`UIApplicationShortcutItems`) nie działają. Ustawienia są w aplikacji (zębatka).
- Schemat `matrix:` nie jest rejestrowany w iOS. Link z zewnątrz musi iść przez `livecontainer://livecontainer-launch?bundle-name=...&open-url=<base64>`. Niesprawdzone na urządzeniu.

## Fakty o gomuks web (zweryfikowane w github.com/gomuks/gomuks)

- Logowanie: HTTP Basic na `POST _gomuks/auth`, serwer ustawia ciasteczko `gomuks_auth` ważne 7 dni i odświeżane przy każdym połączeniu (`pkg/gomuks/server.go`).
- Deep link: `<server>/#/uri/<encodeURIComponent(matrixURI)>`, obsługa w `web/src/ui/MainScreen.tsx` (także przez `hashchange`).
- Każde wejście do pokoju to wpis w historii (`pushState`); powrót gestem z krawędzi cofa historię.
- Lightbox obrazków zapisuje stan `lightbox: {src, alt}` przez `history.pushState` (`web/src/ui/modal/Lightbox.tsx`).
- Media: względne adresy `_gomuks/media/...`, wymagają ciasteczka.
- Nie ustawiaj `window.gomuksAndroid` (przełącza logowanie na natywny bridge Androida).

## Architektura

Sześć plików w `Gomuks/`, podział po funkcjach:

- `App.swift`: start aplikacji, kontroler z `keyboardLayoutGuide` (strona kończy się nad klawiaturą), `GomuksWebView` bez paska nad klawiaturą.
- `Browser.swift`: rdzeń. Start, logowanie natywne (URLSession, ciasteczko do WebKitu), deep linki, nawigacja i linki zewnętrzne, okienka JS (alert/confirm/prompt), wiadomości ze skryptów, kodowanie jak `encodeURIComponent`, konfiguracja `WKWebView` dla mediów.
- `Settings.swift`: ekran serwera, konta i adresu playera; `Credentials` (adres i login w UserDefaults, hasło w Keychain); parsowanie adresu serwera.
- `Scripts.swift`: skrypty wstrzykiwane do strony: `SettingsButton` (zębatka obok lupy), `TimelineScroll` (trzymanie dołu rozmowy przy zmianie wysokości, ResizeObserver), `MediaScript` (przechwycenie lightboxa, lista obrazków, wstawianie playera), `InlineVideoScript` (`playsinline` w ramkach).
- `ImageViewer.swift`: natywny podgląd obrazków (strony w pionie, licznik, udostępnianie), strona ze zoomem i GIF-ami, `SwipeToDismiss` (zamykanie przesunięciem w bok, używane też przez player).
- `VideoPlayer.swift`: adres playera i rozpoznawanie linków (YouTube, Vimeo, TikTok, Twitch, Dailymotion, Streamable, rolki Instagrama, filmy i rolki Facebooka) oraz karta z `/watch`. Podgląd filmu w rozmowie to iframe `<player>/iframe?url=...` (yt-dlp web player, github.com/Matszwe02/ytdlp_web_player). Pełny ekran przez systemowy odtwarzacz iOS.

## Build i testy

- `project.yml` (XcodeGen), `.xcodeproj` poza repo.
- `.github/workflows/build.yml`: IPA jako artefakt `gomuks-ipa`, release przy tagu. Pomija zmiany samych testów.
- `.github/workflows/ui-test.yml`: test UI na symulatorze z lokalnym Synapse, gomuksem, fixture wideo i yt-dlp playerem (`Tests/testbed/`). Uruchamia się tylko po zmianie `Tests/ui-test-trigger` albo ręcznie z `main`. Minuty macOS są drogie: uruchamiać tylko na polecenie.
- Środowisko testowe działa też lokalnie: `GOMUKS_SRC=<checkout gomuks> [PLAYER_SRC=<checkout playera>] Tests/testbed/setup.sh`.

## Otwarte tematy

- Pobieranie plików (`m.file`) i linki zewnętrzne w aplikacji zamiast Safari.
- Powiadomienia (przekaźnik Web Push do ntfy w osobnym repo) i linki `matrix:` przez LiveContainer.
- Merge do `main` i tag `1.0`.
