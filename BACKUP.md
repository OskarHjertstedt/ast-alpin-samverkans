# Backup — astalpin.se

## Databas
Ingen lokal databas i DENNA stack (frontend). Databasen migrerades 2026-08-26
från Supabase Cloud till en self-hostad Supabase-stack i ett eget
compose-projekt: `/home/ubuntu/docker/astalpin-supabase/` (egen `BACKUP.md`
där). All data (auth, `events`, `registrations`, `saved_skiers`,
`app_secrets`, `clubs` m.fl.) ligger där, i containern
`astalpin-supabase-db` (officiell `supabase/postgres`-image, standard
`POSTGRES_*`-env) — täcks alltså av masterbackups vanliga 6-timmars
DB-dumpschema.

`AST-supabase-setup.sql` i det här repot är historiskt (Supabase Cloud-eran)
och redan divergerat från det skarpa schemat — facit är produktionsdatabasen
själv, inte den filen.

## Filer / container
Denna stack är stateless (statisk nginx-container, ingen bind-mount med
persistent data). `/home/ubuntu/docker/astalpin.se/` täcks av masterbackups
vanliga fil-auto-discovery (källkod, Dockerfile, compose-fil).
