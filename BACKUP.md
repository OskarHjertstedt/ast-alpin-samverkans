# Backup — astalpin.se

## Databas
Ingen lokal databas i denna stack. All data (auth, `events`, `registrations`,
`saved_skiers`, `app_secrets` m.fl.) ligger i ett externt Supabase-projekt,
se `AST-supabase-setup.sql` för schema.

Detta betyder:
- `ops/backup-databases.sh` på produktionsservern hittar ingen databas här och
  ska inte förväntas dumpa något för denna site.
- Supabase-projektets data täcks **inte** av masterbackup. Backup av
  Supabase-data (t.ex. schemalagda dumpar eller Supabases egna
  point-in-time-recovery) hanteras separat i Supabase-projektet, utanför
  denna repos ansvar.

## Filer / container
Denna stack är stateless (statisk nginx-container, ingen bind-mount med
persistent data). `/home/ubuntu/docker/astalpin.se/` täcks av masterbackups
vanliga fil-auto-discovery (källkod, Dockerfile, compose-fil).
