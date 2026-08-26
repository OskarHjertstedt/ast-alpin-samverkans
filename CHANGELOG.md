# Changelog — astalpin.se

## 0.2.0 — 2026-08-26
- Migrerade backend från Supabase Cloud till en self-hostad Supabase-stack
  (Postgres + Auth + REST + Realtime) på egen produktionsserver, bakom Caddy
  på `supabase.astalpin.se`. Allt schema, RLS-regler, funktioner och befintlig
  data (användare, träningar, anmälningar, sparade åkare) migrerat oförändrat.
- Fixade två brister som upptäcktes under migreringen: realtidsnotiser för nya
  anmälningar var av misstag inte aktiverade, och radering av eget konto kunde
  misslyckas för användare som skapat träningar/anmälningar.
- Effekt för användare: alla måste logga in på nytt en gång efter driftsättning.

## 0.1.0 — 2026-08-26
- Första driftsättning som Docker-container på produktionsservern (nginx + statisk frontend).
- Döpte om `index (21).html` till `index.html`.
