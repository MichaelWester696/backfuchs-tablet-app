# Backfuchs Produktionsapp

Flutter-Anwendung (Web/PWA) zur Produktionssteuerung in der Backstube von Wester's Backfuchs.
Backend ist [Supabase](https://supabase.com) (Postgres, Row Level Security, Storage, Realtime).

Details zu Architektur und Funktionsumfang: [implementierungsstatus.md](implementierungsstatus.md).

## Setup

Voraussetzung: [Flutter SDK](https://docs.flutter.dev/get-started/install) (Version siehe `pubspec.yaml`, `sdk: '>=3.3.0 <4.0.0'`).

```bash
flutter pub get
```

## Entwicklung (lokal, im Browser)

```bash
flutter run -d chrome
```

## Build (Web)

```bash
flutter build web
```

Das Ergebnis liegt in `build/web/`. Bei jedem Push auf `main` baut GitHub Actions
(`.github/workflows/deploy.yml`) die App automatisch und veröffentlicht sie auf GitHub Pages:
https://michaelwester696.github.io/backfuchs-tablet-app/

## Supabase-Konfiguration

URL und Publishable (Anon) Key stehen aktuell fest codiert in `lib/main.dart`. Der Anon-Key ist
bewusst öffentlich nutzbar und wird über Row Level Security abgesichert — der `service_role`-Key
darf hier niemals eingetragen werden.
