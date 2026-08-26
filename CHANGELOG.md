# Changelog — astalpin.se

## 0.3.0 — 2026-08-26
- Ny anmälan skickar nu ett bekräftelsemejl till den som gjorde anmälan
  (byggt som en databas-trigger + Edge Function i den self-hostade
  Supabase-stacken — inte en frontend-ändring i sig).
- Bekräftelsemeddelandet efter kontoregistrering påminner nu om att kolla
  skräpposten (redan fanns för lösenordsåterställning sedan tidigare).
- Bakgrund: bekräftelse-/återställningsmejl visade sig hamna i mottagarens
  skräppost hos minst en användare — bekräftat inget fel i utskicket från vår
  sida (inga SMTP-fel, alla anrop lyckades), men ett känt problem med att
  använda ett privat Gmail-konto som avsändare för automatiska mejl. En
  riktig transaktionsmejltjänst (egen domän, SPF/DKIM) är uppskjuten till en
  senare, egen ändring.

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
