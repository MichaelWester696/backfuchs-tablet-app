# Implementierungsstatus

Stand: 2026-08-22

## Überblick

Die Backfuchs-Produktionsapp ist eine Flutter-Anwendung (Web/PWA) zur Produktionssteuerung
in der Backstube von Wester's Backfuchs. Backend ist Supabase (Postgres, Auth via Row Level
Security, Storage, Realtime).

## Architektur

- **Frontend:** Flutter (`lib/`), Zielplattform primär Web (PWA), Material Design.
- **Backend:** Supabase (`supabase_flutter`), Zugriffe zentral über `SupabaseService`
  (`lib/services/supabase_service.dart`).
- **Deployment:** GitHub Actions (`.github/workflows/deploy.yml`) baut die App bei jedem
  Push auf `main` und veröffentlicht sie automatisch auf GitHub Pages.

## Umgesetzte Funktionsbereiche

| Bereich | Screen | Status |
|---|---|---|
| Posten-Login | `posten_login_screen.dart` | Implementiert |
| Aufgaben (Tagesaufgaben je Posten, Erledigt-Markierung, Realtime-Stream) | `aufgaben_screen.dart` | Implementiert |
| Rezepte (Suche/Liste) | `rezepte_screen.dart` | Implementiert |
| Rezeptdetail | `rezept_detail_screen.dart` | Implementiert |
| Bestandszählung (Erfassen/Anzeigen für den Tag) | `bestand_screen.dart` | Implementiert |
| Defektmeldung (mit Fotoupload nach Supabase Storage) | `defekt_screen.dart` | Implementiert |
| Kommunikation (Nachrichten an Posten/Leitung, Realtime) | `kommunikation_screen.dart` | Implementiert |
| Navigation/Rahmen | `home_shell.dart` | Implementiert |

## Datenmodelle (`lib/models/`)

`Posten`, `Aufgabe`, `Rezept`, `Nachricht`, `Defekt` — jeweils mit `fromJson`-Mapping auf die
entsprechenden Supabase-Tabellen (`posten`, `aufgaben`, `rezepte`, `nachrichten`, `defekte`,
`bestandszaehlungen`).

## Bekannte offene Punkte

- `lib/main.dart`: Supabase-URL und Publishable Key sind aktuell hart codiert und stammen aus
  dem bisherigen Rezept-App-Projekt (siehe TODO-Kommentar im Code). Sollten perspektivisch aus
  einer Konfiguration/Build-Variable kommen, spätestens beim Wechsel auf ein eigenes
  Supabase-Projekt.
- Keine automatisierten Tests vorhanden (`flutter_test` ist als Dev-Dependency eingebunden,
  aber es existiert kein `test/`-Verzeichnis).
- Keine README/Setup-Dokumentation im Repository.

## Nicht ersichtlich aus dem Code (zu prüfen)

- Ob Row Level Security auf allen Supabase-Tabellen korrekt konfiguriert ist.
- Ob es eine separate Leitungs-/Admin-Oberfläche gibt oder ob diese Rolle außerhalb dieser
  App abgebildet wird.
