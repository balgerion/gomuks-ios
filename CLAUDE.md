# Zasady

## Kod
- Zero komentarzy i docstringów w kodzie. Wyjątek: gdy wprost o nie poproszę.
- Zero emotek: w kodzie, commitach, dokumentacji i odpowiedziach.
- Przed zmianą w istotnej logice pokaż diff i czekaj na wyraźne "tak, zrób".

## Commity
- Autor: wyłącznie balgerion. NIGDY nie dodawaj trailera Co-Authored-By, "Generated with Claude" ani żadnej innej stopki, także w opisach PR.
- Wiadomości commitów po angielsku, w trybie rozkazującym, jedna linia.
- Commity małe i atomowe: jedna logiczna zmiana na commit, zwykle jeden plik.

## Git
- Repo prywatne na GitHubie, używane głównie dla runnerów macOS w GitHub Actions.
- Push własnego brancha sesji jest dozwolony. Merge do `main` robisz tylko na wyraźne polecenie.
- Tagi bez prefiksu "v" (np. `1.0`, `1.0.1`).

## Środowisko
- Sesja w chmurze nie ma dostępu do LAN użytkownika. Backend `https://gomuks.balgeriada.com` jest dla niej nieosiągalny.
- Testy na iPhonie robi użytkownik (sideload IPA z artefaktu GitHub Actions).
