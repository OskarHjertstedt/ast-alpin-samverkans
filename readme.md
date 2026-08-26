# AST — Alpin Samverkansträning

Detta projekt är en liten webbapplikation för att hantera träningspass, anmälningar och administrering för Alpin Samverkansträning. Appen är byggd som en enkel statisk frontend i HTML/CSS/JavaScript och använder en self-hostad Supabase-stack (Postgres + Auth + REST + Realtime, egen drift på produktionsservern) som autentisering och databas — migrerad från Supabase Cloud 2026-08-26.

## Innehåll

- `index.html` — huvudapplikationen (frontend)
- `AST-supabase-setup.sql` — SQL för att skapa databasen, RLS-regler och trigger
- `Dockerfile`, `nginx.conf`, `docker-compose.yml` — containerisering och drift
- `deploy.sh` — deploy till produktionsservern
- `BACKUP.md` — vad som täcks (och inte täcks) av backup
- `CHANGELOG.md` — versionshistorik
- `readme.md` — den här dokumentationen

## Syfte

Applikationen gör att användare kan:

- registrera sig och logga in
- skapa och administrera träningsaktiviteter
- välja grupper och datum för evenemang
- anmäla deltagare till träningar
- lagra tidigare åkare i ett personligt register
- visa registreringar i en adminvy
- hantera administratörsrollen och säkerhetskod

## Teknologier

- Self-hostad Supabase-stack (GoTrue/Auth, PostgREST, Realtime, Postgres, Envoy-gateway) — drivs som eget compose-projekt i `/home/ubuntu/docker/astalpin-supabase/` på produktionsservern, se dess `BACKUP.md`
- Row Level Security (RLS)
- Vanilla JavaScript + HTML + CSS
- Statisk hosting via egen nginx-container bakom Caddy

## Datamodell

Databasen skapas via `AST-supabase-setup.sql` och innehåller bland annat:

- `public.profiles` — användarprofiler kopplade till Supabase-auth
- `public.events` — träningspass och evenemang
- `public.registrations` — anmälningar till evenemang
- `public.saved_skiers` — sparade åkare per användare
- `public.app_secrets` — admin-hemligheter

Det finns även:

- trigger för automatisk skapande av profil vid signup
- funktion för att ge admin-rättigheter via e-post och adminkod
- vy `public.registrations_with_event` för enklare rapportering
- SQL för GDPR-säker hantering av personuppgifter

## Hur projektet körs

### 1. Backend: self-hostad Supabase-stack

Databasen körs INTE längre i Supabase Cloud. Den är ett eget compose-projekt
`/home/ubuntu/docker/astalpin-supabase/` på produktionsservern (192.168.50.7):
Postgres + GoTrue (Auth) + PostgREST + Realtime + Envoy-gateway, exponerad via
Caddy på **`https://supabase.astalpin.se`**.

`AST-supabase-setup.sql` är historiskt (Supabase Cloud-eran) och redan
divergerat från det skarpa schemat (t.ex. saknar tabellen `clubs`) — använd
det INTE som facit. Skavägen till schemat är nu produktionsdatabasen själv;
ändringar görs med riktade `ALTER`-satser, aldrig genom att köra om hela filen.

VIKTIGT: kör aldrig `docker compose down -v` eller motsvarande mot detta
projekt utan en färsk backup — det är nu den enda källan till appens data.

### 2. Konfigurera frontend

I `index.html` finns konfigurationen:

```js
const SUPABASE_URL = 'https://supabase.astalpin.se';
const SUPABASE_ANON_KEY = '...';
```

Dessa pekar redan mot produktionens self-hostade stack. Ändra bara om en ny
instans (t.ex. en testmiljö) ska användas.

### 3. Drift

Frontend körs som en Docker-container (`nginx` som serverar `index.html`) på
produktionsservern (192.168.50.7), bakom Caddy på domänen **astalpin.se**.
Backend (self-hostad Supabase) körs som ett separat compose-projekt på samma
server, se ovan.

- `Dockerfile` / `nginx.conf` — bygger en statisk nginx-image av `index.html`
- `docker-compose.yml` — service `app`, container `astalpin-app`, nätverk `caddy_net`
- `deploy.sh` — deploy till produktion via det gemensamma deploy-flödet
  (se `~/sites/.instructions.md`). Körs från `~/sites/astalpin.se/`:
  ```bash
  ./deploy.sh              # auto-bumpar patch-version och deployar
  ./deploy.sh --status     # visar driftstatus
  ./deploy.sh --rollback   # återställer föregående version
  ```
- Caddy-konfiguration:
  - Frontend: `/home/ubuntu/docker/caddy-edge/conf.d/51-astalpin.se.conf`
    (TLS via ACME/TLS-ALPN, proxar till `astalpin-app:80`)
  - Backend: `/home/ubuntu/docker/caddy-edge/conf.d/52-supabase.astalpin.se.conf`
    (TLS via ACME/TLS-ALPN, proxar till `astalpin-supabase-envoy:8000`)
- Övervakas i Uptime Kuma (se `~/sites/kuma/tools/monitors.json`)
- Se `BACKUP.md` för vad som täcks (och inte täcks) av masterbackup

Lokalt under utveckling kan filen fortfarande öppnas direkt eller köras via
en enkel lokal webbserver:

```bash
open index.html
# eller
python3 -m http.server 8000
```

## Användarflöde

### Registrering och login

- användaren kan skapa konto via e-post och lösenord
- första användaren som registreras blir automatiskt admin
- admins kan senare uppgradera andra användare via adminkod

### Träningar / evenemang

- admin eller skapande användare kan skapa pass
- pass kan kopplas till grupper
- det går att filtrera på grupp och år
- kalendern visar tävlingar/pass i månadsöversikt

### Anmälningar

- användare kan anmäla deltagare till ett träningspass
- data lagras i `public.registrations`
- listor kan visas i adminvy

### Sparade åkare

- användare kan spara åkare för snabbare återanvändning vid nya anmälningar
- data är skyddad per användare via RLS
- endast ägaren kan läsa och uppdatera sina egna poster

## Adminfunktioner

Appen stödjer följande admin-åtgärder:

- identifiera användare med admin-roll
- uppgradera användare via `set_admin_by_email`
- kontrollera adminkod via RPC: `check_admin_code`
- visa alla träningar/registreringar
- exportera/visa registreringsdata

Adminkoden lagras i databasen i `public.app_secrets`:

```sql
insert into public.app_secrets (key, value)
values ('admin_code', 'DIN_ADMINKOD_HÄR');
```

Detta ska inte hårdkodas i frontend-koden.

## Säkerhet och GDPR

Projektet inkluderar flera säkerhetsåtgärder:

- autentisering via Supabase Auth
- RLS-regler för användare, evenemang och registreringar
- användarföräldrade begränsningar för `saved_skiers`
- möjlighet att radera eget konto via `delete_own_account()`
- personuppgifter hanteras per användare och raderas vid användarkonto-borttagning

## Vanliga saker att kontrollera

- `SUPABASE_URL`/`SUPABASE_ANON_KEY` i `index.html` pekar mot `supabase.astalpin.se`
- databasen redan finns och ska inte återinitieras eller skrivas över
- schema matchar aktuell app-version — ändra med riktade `ALTER`-satser, aldrig genom att köra om `AST-supabase-setup.sql` (den är föråldrad, se ovan)
- RLS är aktiverat på tabellerna
- admin-koden har lagts in i `app_secrets`
- `auth.users` och `public.profiles` är i sync

> Databasen körs nu i vår egen self-hostade stack, inte i Supabase Cloud. Gör inga `docker compose down -v`, "reset" eller motsvarande destruktiva kommandon mot `/home/ubuntu/docker/astalpin-supabase/` utan en färsk backup. Använd riktade ändringar eller jämförelse mot befintligt schema.

## Utvecklingsnotering

Detta projekt är byggt som ett litet, fokuserat internverktyg utan större frontend-ramverk. Om projektet ska utökas rekommenderas att det separeras i komponenter och att eventuella nya funktioner dokumenteras i samma anda som den nuvarande statiska applikationen.

## Licens

Det finns ingen separat licensfil i repot. Kontrollera med ägaren om projektet ska publiceras eller återanvändas i andra sammanhang.