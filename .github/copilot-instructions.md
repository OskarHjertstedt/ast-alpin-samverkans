<!-- GENERERAD FIL — redigera inte direkt. Källa: ~/sites/instruktioner.sh -->
# Infrastruktur — Gemensamma regler för alla projekt

> **Instruktionsversion 1.14.0** · genererad 2026-09-07 22:47
>
> Denna fil genereras automatiskt och skrivs över vid varje körning av
> `~/sites/instruktioner.sh`. **Redigera den aldrig direkt** — förbättringar
> (t.ex. lärdomar efter en incident) ska in i skriptet, annars försvinner de
> tyst nästa gång det körs. Föregående version finns som `.bak` bredvid.

## Företagsuppgifter — används i allt utåtriktat
Det här är den verkliga juridiska personen bakom projekten. Uppgifterna ska
användas överallt där ett bolag, en avsändare eller en kontakt anges — och de
får ALDRIG hittas på eller ersättas med platshållare.

| Fält | Värde |
|---|---|
| Bolag | Forss Management Consulting AB |
| Kortnamn | Formacon |
| Webb | formacon.se |
| Huvudkontakt | Pierre Lindbom |
| Telefon | 0735-28 12 15 |
| E-post | pierre.lindbom@formacon.se |

Gäller bland annat: integritetspolicyer och användarvillkor (ett juridiskt
dokument måste peka på den verkliga juridiska personen, annars är det inte
bindande), säljmaterial och offerter, avsändare och signaturer i mailutskick,
footers och kontaktsidor i apparna, `LICENSE` och metadata i `package.json`.

- **Uppfinn aldrig en kontaktadress.** Flera appar har haft påhittade
  support-adresser i sina policyer — en användare som skriver dit når ingen.
- Behövs organisationsnummer, postadress, momsregistreringsnummer eller
  fakturauppgifter: **fråga Pierre**, gissa aldrig.
- Uppgifterna hamnar i filer som kan ligga i git — de är avsedda som publika
  företagsuppgifter, till skillnad från secrets (se Secrets-avsnittet).

## Produktionsserver
- Adress: 192.168.50.7 — all deploy för alla projekt ska alltid ske dit, inga undantag.
- SSH: användare `ubuntu`, port 22. SSH-nyckel är redan konfigurerad — fråga aldrig om lösenord.
- Kör Docker med en container per site, plus en separat container för Caddy.

## Caddy: exakt nuvarande uppställning och säkerhetskrav
Detta är den aktiva, produktionsnära layouten som ska beaktas vid alla förändringar i Caddy. Allt som ändrar domännamn, routes, cert-konfiguration, DNS eller TLS ska utgå från detta mönster.

- Caddy körs som Docker-containern **`caddy-edge`** på produktion (192.168.50.7), separerad från app-containrarna. Compose-projektet ligger i `/home/ubuntu/docker/caddy-edge/`.
- **DEN ENDA SANNA KONFIGURATIONEN ligger på hosten i `/home/ubuntu/docker/caddy-edge/`** (`Caddyfile`, `conf.d/`, `certs/`, `logs/`). Containern bind-monterar dessa till `/etc/caddy/...` *inuti* containern — så när ett kommando körs MED `docker exec caddy-edge ...` är sökvägen `/etc/caddy/...` korrekt, men på hosten redigeras ALLTID `/home/ubuntu/docker/caddy-edge/...`.
- **FÄLLA — hostens `/etc/caddy` är DÖD**: katalogen `/etc/caddy` direkt på hosten är en kvarleva från en nedlagd nativ Caddy-process (omdöpt till `/etc/caddy-OLD-INAKTIV-20260813`). Ändringar där påverkar INGENTING men ser ut att vara rätt. Detta misstag kostade en hel arbetsdag 2026-08-13. Redigera aldrig någon `/etc/caddy*`-katalog på hosten, och återskapa aldrig `/etc/caddy` där.
- Det finns en nativ caddy-binär på hosten (`/usr/local/bin/caddy`) — den får ALDRIG startas. Endast containern `caddy-edge` är ingress. Kontrollera vid misstanke om konflikt: `pgrep -a caddy` på hosten ska vara tomt (containerns process syns inte där).
- Huvud-Caddyfile är minimal och importerar site-konfigurationer från `conf.d/*.conf` (endast filer som slutar på `.conf` importeras).
- Caddy använder Docker-nätverket för backend-routing: site-blocken proxar till app-namn som `lingomaster-app`, `sva_frontend`, `buildtalk` etc., inte direkt till offentliga IP-adresser.
- **HAIRPIN-REGEL (orsakade 502:or 2026-08-13)**: en backend-container som ligger på samma Docker-nät som `caddy-edge` (`caddy_net`) får ALDRIG proxas via `192.168.50.7:<hostport>` — hairpin-NAT på samma brygga ger asymmetrisk routing och i/o timeout. Proxa den via containernamn:internport (t.ex. `globalnews-prod:80`). Backends på andra nät fungerar via host-IP, men containernamn är alltid förstahandsval. Kontrollera nättillhörighet innan en ny route skrivs: `docker inspect <container> --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'`
- HTTP/HTTPS portarna för värden är fixerade och får inte ändras utan uttrycklig instruktion:
  - host: `80 -> 8081`
  - host: `443 -> 4431`
- Den gamla Caddy-servern på 192.168.50.90 existerar INTE längre. Använd aldrig den adressen.
- Site-konfigurationer importeras i filsystemordning. Filnamn med nummer i namn används för ordning; dubbletter eller gamla filer kan skapa överlappande hosts och orsaka felaktig routing.
- Cert- och TLS-konfiguration ska hanteras via separata snippets eller site-blocks, och aldrig genom att manuellt blanda ihop olika domäns konfigurationer i samma fil.
- Om ett domännamn byts, tas ett helt site-block bort/ändras i en enda, väldefinierad site-fil. En ny domän ska aldrig läggas till utan att kontrollera om den gamla filen fortfarande finns, eller om det finns dubbletter från tidigare försök.

### Krav före varje Caddy-ändring
Detta har gått sönder tidigare och tagit timmar att återställa. Följ alltid:
0. **Verifiera att du redigerar den config containern faktiskt läser.** Kör `docker inspect caddy-edge --format '{{json .Mounts}}'` och bekräfta att `Source`-sökvägarna pekar på katalogen du tänker ändra i. Om mounts inte matchar din tänkta sökväg: STOPP — utred innan något redigeras. Detta steg är obligatoriskt och får aldrig hoppas över, oavsett hur säker sökvägen "känns".
1. Ta en full backup av Caddy-konfigurationsstatusen innan något ändras.
   - Kopiera `/home/ubuntu/docker/caddy-edge` till ett tidsstämplat katalognamn, **utan `logs/`**: `sudo rsync -a --exclude logs/ /home/ubuntu/docker/caddy-edge/ /home/ubuntu/caddy-edge-backup-$(date +%Y%m%d-%H%M%S)/` — ALDRIG `/etc/caddy` (den är död, se ovan).
   - Uteslutningen av `logs/` är inte kosmetisk: med `cp -a` blev varje backup ~1,4 GB, varav 1,4 GB loggar och 228 kB faktisk konfiguration. 24 stycken hade hunnit ackumuleras till 23 GB innan det upptäcktes 2026-08-29. Loggarna är dessutom värdelösa i en konfigurationsbackup — det du behöver återställa är `Caddyfile`, `conf.d/` och `certs/`.
   - Backupen innehåller därmed `Caddyfile`, `conf.d/`, `certs/` och `logs/`.
   - Städa gamla backuper när en ändring är verifierad klar — behåll den senast verifierade, låt inte tiotals ackumuleras.
2. Läs och jämför exakt nuvarande `Caddyfile` och `conf.d/*` innan du föreslår en ändring.
3. Leta efter dubbletter, gamla domänfiler och överlappande hostnamn. Dessa är en vanlig orsak till att Caddy blir trasig vid domänbyte eller migrering.
4. Validera alltid med `caddy validate --config /etc/caddy/Caddyfile` inuti Caddy-containern innan reload eller restart: `docker exec caddy-edge caddy validate --config /etc/caddy/Caddyfile` (sökvägen `/etc/caddy/...` är korrekt HÄR eftersom kommandot körs inuti containern, där mounten finns). Kör aldrig `caddy validate` direkt på värden — den nativa binären läser fel config. Reload görs med `docker exec -w /etc/caddy caddy-edge caddy reload --config /etc/caddy/Caddyfile`.
5. Gör inga globala `pkill`, hårda restarts eller ad-hoc `nohup`-startar av Caddy utan att först visa varför och vad som kommer att ändras.
6. Efter ändringen: verifiera exakt den domän som ändrats, inte bara "Caddy verkar köra". Använd riktad kontroll mot den specifika hosten.

### Domänbyte / namnändring: nödvändig försiktighetsåtgärd
Vid byte av domännamn eller migrering mellan olika hostnamn:
- ta backup först
- leta upp den exakta site-filen som kopplar mot gamla domänen
- kontrollera om det finns gamla route-block eller återstående `.conf`-filer som fortfarande importeras
- ändra bara den relevanta filen, aldrig flera globala filer utan förståelse
- se till att den nya hosten inte matchar ett gammalt wildcard eller felaktigt block
- validera efter ändringen
- verifiera med en riktad probe mot den nya domänen och den gamla domänen om den fortfarande finns

### Reload vs restart
Om inget annat anges ska Caddy alltid uppdateras med en graceful reload, inte en full restart av containern. `caddy reload` är att föredra eftersom det uppdaterar konfigurationen utan att avbryta aktiva anslutningar. En full container-restart bör bara användas om reload inte fungerar eller om Caddy inte svarar.

### Orientering om start/restart-risken
Att starta om servern eller Caddy i sig är inte det verkliga problemet — risken ligger i startordning, gamla filer och felaktig import. Om Caddy startar med en trasig eller överlappande `conf.d`-konfiguration kan hela ingressen gå ned. Därför:
- hantera alltid Caddy med backup + validation + målinriktad verifiering
- undvik manuell massreboot av ingressen när det bara gäller en site
- håll `conf.d/` ren och tydlig, och radera aldrig gamla site-filer utan att först kontrollera om de ännu används

### Extra viktiga riskfaktorer att ha koll på
Det finns några centrala risker som ofta glöms bort och som kan slå ut hela ingressen om de inte hanteras:
- flera Caddy-processer eller flera Caddy-container kan existera samtidigt, vilket skapar konflikt mellan "aktiv" config och gamla processer — detta hände 2026-08-13 (nativ caddy + caddy-edge-containern körde parallellt och gav TLS-fel och nginx-liknande felsvar från "fel" process)
- gamla `.conf`-filer i `/home/ubuntu/docker/caddy-edge/conf.d/` kan fortsätta att importeras även efter att ett domännamn ändrats eller flyttats, vilket resulterar i dubbletter eller överlappande routes
- en ändring kan se korrekt ut, validera OK och ändå vara verkningslös — om den gjorts i en katalog containern inte monterar. Symptomet är att beteendet inte ändras alls efter reload. Vid det symptomet: gå direkt till steg 0 (verifiera mounts), leta inte vidare i configens innehåll
- startordningen är kritisk: om Caddy startar innan backend-containrarna är redo kan proxy-konfigurationen fortfarande vara giltig men fungera felaktigt eller misslyckas under belastning
- TLS-/cert-konfiguration kan gå sönder utan att HTTP-routes är uppenbart felaktiga, särskilt när ACME-snippets, wildcard-certifikat eller felaktiga keypar används
- manuell `pkill`, `nohup`-start eller full restart av containern utan backup och validering kan skapa ett "fungerande" men felaktigt system där äldre config återaktiveras

Det viktigaste att komma ihåg är att det inte räcker med att ha en site-fil per domän. Det avgörande är att det finns exakt en aktiv, auktoritativ Caddy-kontext för public ingress, och att inga gamla eller dubbletterade filer fortfarande importeras.

### Verifiering av en enskild site utan att påverka resten
När en site verkar ladda fel sida, fel domän eller "fel innehåll" på första besök men fungerar efter hård refresh, ska följande rutin användas innan man ändrar någonting i Caddy eller restartar ingressen:

0. Om en sajt är OFÖRKLARLIGT nere (inget uppenbart fel, ingen nyligen gjord ändring): diffa den aktiva `conf.d/`-katalogen (`/home/ubuntu/docker/caddy-edge/conf.d/`) mot den gamla/döda katalogen (`/etc/caddy-OLD-INAKTIV-20260813/conf.d/` eller motsvarande) FÖRST, innan du börjar felsöka på andra håll. En fil som av misstag redigerats i fel katalog, eller en gammal fil som dykt upp igen, är en vanlig orsak och syns direkt i en diff.
1. Kontrollera att site-filen är den korrekta och att det inte finns dubbletter eller äldre `.conf`-filer som fortfarande importeras.
2. Validera den aktiva Caddy-konfigurationen inuti Caddy-containern: `docker exec caddy-edge caddy validate --config /etc/caddy/Caddyfile`.
3. Testa exakt host och route från Caddy-nivån med Host-header, inte bara via DNS eller extern URL. Exempel: `curl -H "Host: example.se" http://127.0.0.1:8081/`.
4. Testa direkt mot backend/appens interna adress för att se om rätt innehåll kommer från appen själv, utan Caddy-mellanled.
5. Kolla om felet bara inträffar vid första besök och sedan löser sig efter hård refresh. Det är då ofta ett cache-, browser- eller service-worker-problem, inte ett Caddy-routing-problem.
6. Om HTML eller statiska assets ser gamla ut, kontrollera om Next.js-cache, CDN-cache, browser cache, PWA/service worker eller tidigare build är kvar och återanvänds.
7. Om problemet fortfarande är oklart: utgå från en liten, riktad verifiering och inte från en bred restart. Mät exakt vad som responderar på rätt host innan du ändrar ingressen.

Detta är ett generellt säkerhetsmönster: ett fel som bara visar sig på första visit, men försvinner efter hard refresh, är ofta ett cache- eller stale-state-problem, inte automatiskt ett domän- eller route-problem. I sådana fall ska man verifiera host, backend och cache separat innan man gör en riskfylld Caddy-åtgärd.

### Grundregel
Caddy får aldrig röras på "små sätt" i produktion utan att föregås av:
- backup
- exakt analys av aktuell config
- validering
- begränsad, riktad verifiering

Om något verkar osäkert: fråga innan du startar om Caddy eller ändrar en live route.

## Deploy
- Använd alltid befintliga deploy-script (`deploy.sh`, `_deploy_lib.sh`, `_deploy_template.sh`, `create-site-deploy.sh` — namnet varierar per projekt, kolla vad som finns i repo-roten) — hittar dessa i sites-roten. Uppfinn inte nya deploy-flöden.
- Deploy sker alltid till 192.168.50.7, aldrig lokalt eller till annan miljö.
- **Ändringar i `.env`-filer kräver att containern SKAPAS OM** — `docker compose restart` läser inte om `env_file`; det gör bara `docker compose --env-file <fil> up -d`. Verifiera efteråt inne i containern (`docker exec <c> env | grep NYCKEL`). Se också upp med dubblettnycklar i env-filen: samma nyckel två gånger, och vilken som vinner beror på verktyget — håll en rad per nyckel. (För testservern, se separat avsnitt "Testmiljö" nedan — samma script gäller INTE där per automatik.)
- En ny site är INTE färdigdeployad förrän tre saker är verifierade: projektet syns i masterbackup, databasen (om sådan finns) har fått en färsk dump, och en Uptime Kuma-monitor är på plats. Se Backup- och Övervakningsavsnitten nedan.

### FÄLLA: nya filer deployas men committas aldrig
Deploy-scriptets release-commit stagear med `git add -u`, som **bara tar spårade ändringar**. En nyskapad fil rsyncas till produktion och körs där, men hamnar aldrig i git. Scriptet varnar om otrackade filer men fortsätter ändå, och varningen drunknar i deployutskriften.

Konsekvensen är att `HEAD` slutar gå att bygga från en ren klon så snart en spårad fil importerar en otrackad. Koden lever då bara på dev-maskinen och på servern — går dev-maskinen sönder är arbetet borta trots att det körs i produktion. Upptäcktes 2026-08-30 i valle, där sex filer deployats under tio releaser utan att någonsin committas.

**Deploy-scriptet frågar numera i stället för att bara varna.** Hittas ospårade filer under `src/`, `scripts/`, `docs/` eller `migrations/` stannar deployen och erbjuder tre val:
- `[a]` lägg till dem i release-commiten (rekommenderas)
- `[f]` fortsätt utan dem — de deployas men sparas inte i git
- `[x]` avbryt deployen

Körs deployen utan terminal, till exempel från ett skript eller ett automatiserat flöde, kan den inte fråga och **avbryts** i stället. Vill man medvetet deploya utan filerna sätter man `DEPLOY_ALLOW_UNTRACKED=1`. Ospårade filer utanför källkodskatalogerna (loggar, temporära filer) nämns men stoppar inget.

Utöver det:
- Efter en release som lagt till filer: verifiera att repot faktiskt bygger fristående. Klona till en tom katalog, länka in `node_modules` och kör typkontrollen. Att det bygger i arbetskatalogen bevisar ingenting — där finns filerna oavsett om git känner till dem.
- Lita aldrig på att en lyckad deploy betyder att koden är säkrad. Deploy kopierar filer; git bevarar dem. Det är två olika saker.

### FÄLLA: riv aldrig containrar före bygget
Ett deployflöde får ALDRIG stoppa eller ta bort körande containrar innan de nya avbilderna är färdigbyggda. Bygg först, byt sedan med `docker compose up -d --no-build --remove-orphans` — då är avbrottet sekunder i själva bytet.

Achievers deploy gjorde tvärtom (`compose down` + `docker rm -f` i ett "städsteg" före ett 5-10 minuters bygge) och tog ner sajten under HELA byggtiden, varje release, i månader — upptäckt 2026-09-01 som en oförklarlig 502 mitt i en release. Kuma larmade i Discord varje gång, men ingen bevakade kanalen, och Sentry var tyst eftersom klientens service worker svalde felen snyggt.

Därför, när ett deployflöde skapas eller ändras:
- Leta efter `down`, `stop`, `rm -f` och `--force-recreate` i flödet och ifrågasätt varje förekomst — särskilt "städsteg" från gamla migreringar, och särskilt namnfilter som kan matcha DAGENS containrar (Achievers "legacy-städning" tog `achiever-db-prod`, som var den aktiva databasen).
- Mät hälsan under en hel deploy minst en gång: kör en loop som pollar hälso-endpointen var tionde sekund parallellt med deployen och räkna svarskoderna. Bara 200 plus enstaka fel i bytesögonblicket är godkänt.
- Larmkanalen (Discord för Kuma) ska faktiskt bevakas — larm ingen läser är ingen övervakning.

### Loggar som överlever deployer
`docker logs` nollställs när containern återskapas — alltså vid varje deploy. Utan filloggning finns det NOLL historik att utreda med, och problem som "varför loggas användare ut" går inte att besvara. Därför:
- Applikationer ska logga till fil i en bind-mountad katalog, med rotation (t.ex. 20 MB × 5 filer). I Achiever: `LOG_TO_FILE=true` + `LOG_DIR` mot `./logs`.
- FÄLLA: bind-mountade kataloger skapas på hosten som `ubuntu` (uid 1000), men containern kan köra som annan uid (Achievers API kör som 1001). Då misslyckas skrivningarna TYST — filen förblir tom utan något fel i loggen. `chown <container-uid>` på katalogen före start, och verifiera att filen faktiskt växer.

## E-postutskick — avsändardomänens SPF avgör transporten
Mail med `From:` på en domän vars SPF pekar på Microsoft 365 (`include:spf.protection.outlook.com -all`) MÅSTE skickas via M365 (Graph `sendMail` med app-only-token, eller M365 SMTP) — aldrig via Gmail-SMTP eller annan tredjepartsserver. SPF hard-fail plus DMARC-obalans lägger mailet i skräppost/karantän hos varje Microsoft-mottagare, dvs. de flesta företag; avsändarens egna Gmail/iCloud-tester ser däremot ut att fungera och bevisar ingenting. Achiever drabbades 2026-09-01: första externa registreringen (M365-organisation) fick verifieringsmailet i karantän. Referensimplementation: `apps/api/src/lib/mailTransport.ts` i Achiever (`MAIL_PROVIDER=graph`), uppsättning i `docs/EMAIL_DELIVERY.md`. Verifiera alltid ett byte med testmail till en MICROSOFT-adress och kontrollera SPF/DKIM/DMARC=pass i huvudena. Slå på DKIM för domänen i M365-admin.

## Miljöer — tre skilda maskiner, blanda aldrig ihop dem
| Maskin | Adress | Roll |
|---|---|---|
| Dev-server (Mac mini) | 192.168.50.135 | Kodredigering och utveckling. INGEN testkörning. |
| Testserver | 192.168.50.123 | ALL testkörning — Docker, Colima, containrar, testinstanser. |
| Produktion | 192.168.50.7 | Skarp drift. All deploy sker hit. |

- **INGA tester körs på dev-servern.** Allt som innebär att starta containrar, köra en app i en körande miljö, eller testa ett bygge — med Docker, Colima, `docker compose`, podman eller vad det än råkar heta — ska ske på TESTSERVERN (192.168.50.123), aldrig på dev-servern (192.168.50.135).
- Installera inte Docker, Colima eller motsvarande containerruntime på dev-servern. Föreslå det aldrig heller. Behöver något köras i container: det körs på testservern.
- Dev-servern är till för att skriva kod i (editor, git, `npm install`, typkontroll, linting, enhetstester som körs direkt i Node utan container). Så fort något ska köras i en container eller som en körande instans — flytta till testservern.
- Om du fastnar och frestas att "bara snabbt testa lokalt i en container" — gör inte det. Fråga istället, eller sätt upp det på testservern enligt avsnittet "Testmiljö" nedan.
- Kör aldrig migrations, seed-script eller databasändringar direkt mot produktion utan uttrycklig bekräftelse.
- Anta aldrig att "test" eller "staging" betyder samma sak som produktion.

## Backup
- **Fullständig driftdokumentation: `~/.claude/docs/masterbackup.md`** — läs den vid backup-relaterat arbete, felsökning eller uppsättning av ny site.
- `masterbackup` är den ALLENARÅDANDE backuplösningen för alla projekt på produktionsservern (beslut 2026-08-15). Inga projektspecifika backup-containrar, cron-dumpar eller egna scripts får finnas — hittar du en, avveckla den efter att masterbackup-täckningen verifierats. Behövs något utöver standarden: bygg in det i masterbackup istället.
- Fil-backuper sker via auto-discovery av `/home/ubuntu/docker` (GFS-retention: 7 dagliga / 4 veckor / 12 månader). DB-dumpar körs var 6:e timme via `ops/backup-databases.sh` (host-cron, `flock`-skyddad, 7 dagars retention). Larm går till Discord-webhook och som `COVERAGE ERROR` i `data/backup-cron.log`.
- Krav på varje projekt: ligg i `/home/ubuntu/docker/<projekt>/` med `docker-compose.yml`; databas i egen container med officiell image och standardmiljövariabler (det är dem dump-skriptet autentiserar med); SQLite-filer i en bind-mountad katalog under projektmappen, aldrig i en anonym volym; `BACKUP.md` i projektroten.
- Ändra ALDRIG DB-lösenord enbart i compose/`.env` — en initierad databas behåller sitt gamla lösenord och dumpen börjar faila tyst. Ändra i databasen och i env samtidigt.
- Rör aldrig klassificeringslogiken i `ops/backup-databases.sh` utan att förstå historiken (image-omtaggning fick 11 databaser att tyst falla ur backupen 2026-08-15) — den dokumenteras i masterbackup.md.
- Om projektet har en databas ska en backup av databasen ALLTID tas innan deploy, oavsett hur liten ändringen verkar vara. Deploy ska aldrig ske utan att en färsk databas-backup finns.
- Undantag som INTE ersätter något ovan: `backup-sites.sh` på Pierres Mac (cron 02:00) rsyncar källkod från `/Volumes/Sourcecode/sites/` (projektens riktiga hem sedan flytten 2026-08 — `~/sites` innehåller bara symlänkar dit), `~/sites/` (loggar/hjälpskript) och `/Volumes/Dev/sites/` till extern disk — det är en dev-maskinsbackup, inte en produktionsbackup.

## Rollback
- Innan en release med större ändringar (databasmigrationer, breaking changes i API), beskriv kort hur en rollback skulle göras om något går fel.

## Farliga kommandon — fråga alltid först
- Kör aldrig `rm -rf`, `docker system prune`, `docker-compose down -v` eller liknande utan att visa exakt vad som tas bort och vänta på godkännande.
- Rör aldrig `.env`, `.env.local` eller andra secret-filer utan att fråga.
- Skriv aldrig över befintliga databaser/migrations utan bekräftelse.
- Ändra aldrig portmappningar, DNS eller nätverksinställningar utan godkännande.

## Secrets
- Skriv aldrig API-nycklar, lösenord eller tokens direkt i kod eller commit-meddelanden. Om en hemlighet behövs, använd `.env`-filer och påminn om att lägga till dem i `.gitignore`.

## Gör aldrig utan att fråga
- Committa eller pusha kod automatiskt.
- Ändra CI/CD-konfiguration (GitHub Actions, etc.).
- Installera nya npm-paket eller ändra `package.json` utan godkännande.

## Konventioner
- Följ befintlig kodstil i projektet — introducera inte nya ramverk/bibliotek utan att fråga.
- Använd TypeScript strict mode där det redan används i projektet.
- Skriv commit-meddelanden på engelska, korta och beskrivande.

## Git-hygien
- **Databasdumpar, backuper, media och skärminspelningar hör ALDRIG hemma i ett repo.** Achievers repo var 930 MB varav 813 MB gamla dumpar och en inspelning — pushar tog minuter och kunde time-outa, och att få bort dem i efterhand krävde historieomskrivning med force-push (git rm räcker inte; historiken behåller allt). Kolla `.gitignore` INNAN en ny filtyp börjar genereras i repot.
- Städa det som ackumuleras: lint-staged lämnar en backup-stash per misslyckad commit (Achiever hade 16), gamla helt inmergade grenar och bortglömda worktrees samlar damm. Vid städning: verifiera att grenar är inmergade (`git branch --merged`) och spara ocommittade worktree-ändringar som patch innan borttagning.
- Hooks som kör pnpm/node måste fungera även från GUI-klienter (VS Code kör dem utan shellens PATH): `~/.config/husky/init.sh` med `export PATH="/opt/homebrew/bin:$PATH"` löser det på dev-maskinen.

## Testning
Detta avsnitt handlar om att köra automatiserade tester (Jest/etc.) — inte om testmiljön på testservern (se separat avsnitt nedan).
- Kör befintliga tester (om sådana finns) innan en release anses klar. Om testerna failar, fixa eller flagga det — släpp inte ändringar med kända failande tester utan att fråga.
- Om inga tester finns för det som ändras, föreslå att skriva minst grundläggande tester för nya funktioner, men fråga innan du lägger till ett helt nytt testramverk.
- **Kör aldrig testsviter parallellt med varandra eller med ett pågående bygge.** CPU-trängsel ger slumpvisa timeouts som ser ut som flaky tester (Achiever: tre "flaky" på två dygn, alla var 10-sekunders-timeouts under parallellkörning). I pre-push-flöden: `--workspace-concurrency=1` eller motsvarande.
- **Avfärda aldrig en röd körning som "flaky".** Kör om en gång; går den igenom, utred ändå orsaken — varje avfärdad röd körning lär alla att ignorera röda körningar. Timeouten i felmeddelandet skiljer miljöproblem (Exceeded timeout) från riktiga fel (assertion).
- **Enhetstester rör aldrig nätverk, Redis eller databas.** En svit som inte avslutar efter "passed" har ett test som öppnat en riktig anslutning — hitta det med bisektering fil för fil (macOS saknar `timeout`; använd `perl -e 'alarm N; exec @ARGV'`). `forceExit` i testrunnern är ett symptom att utreda, aldrig en lösning att behålla — den döljer nästa läcka.

## Versionshantering och release notes — obligatoriskt för varje app
- Varje app ska stödja versionshantering (t.ex. version i `package.json` eller motsvarande) och en changelog/release notes-fil.
- Vid varje release:
  1. Höj versionsnumret (patch/minor/major beroende på ändringens omfattning — fråga om det är oklart vilket).
  2. Skriv ett tydligt commit-meddelande på SVENSKA som sammanfattar nyheterna i releasen.
  3. Uppdatera changelog/release notes-filen i projektet med samma sammanfattning.
- Håll koll på versionshistoriken i varje projekt — föreslå inte en release utan att först kolla nuvarande version och tidigare changelog-poster.
- Hoppa aldrig över versionshöjning eller release notes vid en release, även vid små ändringar.
- **Före varje versionsbump: kolla `git log --oneline -5` och changelogens översta post.** Flera sessioner (Claude, Copilot, Pierre själv) kan arbeta i samma repo, och din bild av "senaste versionen" kan vara timmar gammal. Achiever 2026-08-31: en session släppte "4.65.6" ovanpå en redan släppt 4.66.0 — versionsnumret gick baklänges i produktion. Ett nummer per release, alltid uppåt, och har repot rört sig sedan din session började ska du läsa in dig innan du bumpar.
- **Fråga om säljmaterialet:** i samband med release-commiten ska det alltid ställas en fråga om appens säljblad ska uppdateras med releasens nyheter — se avsnittet "Säljmaterial" nedan.

## Dokumentation — obligatoriskt vid varje ändring
- Teknisk dokumentation ska alltid uppdateras när kod ändras. Ändras
  databasschemat gäller dessutom Datamodell-avsnittet nedan; ändras ett API
  gäller API-avsnittet. Om teknisk dokumentation saknas för det du ändrar/skapar, skapa den — anta inte att avsaknad dokumentation betyder att den inte behövs.
- Varje förändring (ny funktion, ändrat beteende, borttagen funktionalitet) ska speglas i dokumentationen samma release, inte skjutas upp.
- End-user-dokumentation (hjälptexter, guider, ev. FAQ) ska hållas uppdaterad parallellt med den tekniska dokumentationen — om en ändring påverkar hur en användare interagerar med appen, uppdatera end-user-dokumentationen i samma release.
- Manualer och guider ska förses med skärmdumpar där det är relevant, samt länkar för smidig navigation mellan avsnitt/sidor i dokumentationen.
- Koden själv ska dokumenteras och kommenteras tydligt på lämpliga ställen (komplexa funktioner, icke-uppenbar logik, viktiga beslut/avgränsningar) — så att en annan utvecklare kan sätta sig in i och ta över koden vid behov, utan att behöva fråga den ursprungliga utvecklaren.
- Fråga innan du tar bort eller kraftigt skriver om befintlig dokumentation — komplettera hellre än att radera, om inte innehållet är uppenbart inaktuellt.
- Dokumentation räknas som en del av leveransen, inte ett separat efterföljande steg — en release är inte klar förrän dokumentationen är uppdaterad.

## Säljmaterial — uppdateras vid varje release
Gäller appar som ska kunna säljas eller presenteras utåt (Achiever, CogniFin, StaffHub, LingoMaster m.fl.). För experiment-, test- och arkivmappar är detta frivilligt.

- Varje sådan app ska ha ett **levande säljblad**: en fil (t.ex. `MARKETING.md` i repo-roten) som beskriver programmets funktioner i stort på ett säljande språk — vad appen gör, för vem, och varför det är värt det. Det är inte teknisk dokumentation utan underlag för presentation, offerter, hemsida och säljsamtal.
- **Vid VARJE release ska frågan ställas:** "Ska säljbladet uppdateras med den här releasens ändringar?" Ställ frågan i samband med release-commiten — den är en del av release-diskussionen, inte något som hoppas på att kommas ihåg. Besvara aldrig frågan åt Pierre; han avgör vad som är säljbart.
- Om ja: uppdatera bladet så att nya funktioner syns och ändrade funktioner beskrivs rätt, i samma commit som releasen. Rent interna ändringar (refaktorering, beroendeuppdateringar) behöver inte nämnas — bladet beskriver vad användaren/köparen får, inte vad som händer under huven.
- Saknas säljbladet i en app som ska ha det: påpeka det och föreslå att skapa det (fråga först), istället för att låta avsaknaden passera tyst.
- Bladet följer appens språkregel (svenska som grund), skrivs i du-form och hålls i nuptid — det ska alltid gå att skicka som det är utan att först behöva saneras.
- Ett säljblad som inte rörts på flera releases trots nya funktioner är ett förfallotecken — flagga det proaktivt när du märker det, på samma sätt som inaktuell dokumentation.

## Testmiljö (deploy till testservern) — SKILJ FRÅN "Testning" ovan
OBS: detta avsnitt handlar om att sätta upp en körande testinstans av en app på testservern — INTE om att köra en automatiserad testsvit (`npm test`/Jest, se avsnittet "Testning" ovan). Att köra befintliga tester ska ALDRIG i sig trigga något i detta avsnitt.

- Dedikerad testserver finns på 192.168.50.123, ren/avsedd enbart för tester på lokala nätverket. Kör Docker. **Detta är den ENDA maskin där testkörning i container får ske** — se Miljöer-avsnittet ovan. Dev-servern (192.168.50.135) ska aldrig köra containrar.
- SSH: användare `serveradmin`, port 22. Lösenord hanteras separat, be alltid Pierre om inloggning om det behövs — spara/skriv aldrig ut lösenordet i kod, kommentarer eller commit-meddelanden.
- Detta avsnitt gäller ENDAST när Pierre uttryckligen ber om att sätta upp, deploya till, eller köra en testmiljö/testinstans av ett projekt (t.ex. "sätt upp en testmiljö för X", "deploya X till testservern"). Anta inte att en testmiljö ska sättas upp bara utifrån annat kontext eller egen bedömning.
- Deploy till testservern är ALDRIG samma som deploy till produktion — de vanliga deploy-scripten (`deploy.sh` m.fl., se avsnittet "Deploy" ovan) är byggda för produktion (192.168.50.7). Anta inte att de fungerar rakt av mot testservern; fråga eller anpassa om inget testserver-specifikt deployflöde redan finns för projektet.
- Vid uppsättning av testmiljön: exponera projektet på 192.168.50.123 med en unik port per projekt i Docker. Håll ett enkelt register (t.ex. en README eller portlista i testserver-mappen) över vilken port som är upptagen av vilket projekt, så en ny port aldrig krockar med ett annat pågående testprojekt.
- Endast när en testmiljö faktiskt sätts upp/deployas på testservern enligt ovan ska appen TYDLIGT visa att den körs i testläge (t.ex. en synlig banner, badge eller liknande i UI:t) — det ska aldrig gå att förväxla en testinstans med produktion. Lägg INTE in en sådan banner i produktionskoden proaktivt eller "för säkerhets skull".
- Testservern är skild från produktionsservern (192.168.50.7) — blanda aldrig ihop dem, och deploya aldrig till testservern av misstag när produktion var avsikten eller vice versa.
- Kopiera aldrig en `.env` från produktion rakt av till testservern — en testinstans ska aldrig peka mot produktionsdatabasen eller andra produktions-secrets. Skapa separata test-specifika miljövariabler/secrets.
- **Testmiljöer är AVSTÄNGDA som default.** Stoppa miljön (`docker compose stop`/`docker stop` — aldrig `rm`, datan ska ligga kvar) när testet är klart och senast när det som testades har deployats till produktion. Nästa testomgång är ett `docker compose start` bort — sekunder, med datan intakt.
- Varför detta är en regel: en stående testmiljö kostar minne dygnet runt. 2026-09-02 OOM-dödades en dev-databas på testservern när ~5 GB stående miljöer trängdes på 7,7 GB RAM — däribland en Supabase-stack på 1,35 GB som stått igång en hel vecka efter att migreringen den testade gått i produktion. Kontrollera också att det stoppade inte har restart-policy `always` (då smyger det igång vid nästa boot); `unless-stopped` respekterar manuell stopp.
- Efter avslutat test: städa bort containern/porten på testservern om den inte längre används aktivt, så 192.168.50.123 inte samlar på sig gamla testcontainrar över tid. Fråga om du är osäker på om en container fortfarande behövs innan du tar bort den. (Stoppa = default efter varje test; ta bort = när projektet inte längre behöver någon testmiljö alls.)

## Övervakning
- **Fullständig driftdokumentation: `~/.claude/docs/kuma.md`** — läs den vid övervakningsarbete, felsökning av Kuma eller när monitorer ska läggas till.
- Övervakning sker i **Uptime Kuma** (Docker-containern `uptime-kuma` på produktionsservern). Det finns INGEN Prometheus/Grafana-stack — föreslå aldrig det.
- Nya containrar/siter på produktionsservern ska få en Uptime Kuma-monitor, inte lämnas som en blind fläck utanför övervakningen.

## Felrapportering (Sentry)
- **Fullständig dokumentation: `~/.claude/docs/sentry.md`.**
- Felrapportering sker i **sentry.io (SaaS, EU-region)**, organisation `o4511914067427328`, inloggning `pierre.lindbom@lconsulting.se`. Ingen self-hosted Sentry finns. Bygg aldrig en parallell error-tracker.
- Aktiv i dagsläget endast för `status.lconsulting.se` och achiever-API:t. Achiever web, cognifin och yatzy har paketet installerat men saknar DSN i produktion — de rapporterar alltså ingenting.
- **Initiera Sentry ENDAST när en riktig DSN finns** (`if (dsn) Sentry.init(...)`). Använd aldrig en platshållar-DSN som fallback — achiever hade det och felrapporteringen var död i månader trots att den såg aktiverad ut. Utan DSN ska Sentry vara tyst avstängd, inte låtsas fungera.
- DSN läggs i `.env` på servern, aldrig i kod. Sätt `release` till appens version så fel kan kopplas till en release (hänger ihop med kravet på versionshantering ovan).
- Skapa ett eget Sentry-projekt per app, inte en delad soptunna. Följ mönstret från `status.lconsulting.se` som referensimplementation.
- **Bakgrundsjobb (cron, köer, schemalagda jobb) får inte faila tyst.** Rapportera jobbfel till Sentry (captureException), inte bara till en loggfil ingen läser. Achiever: embedding-jobbet kraschade 03:30 varje natt efter en ORM-uppgradering och upptäcktes först veckor senare när filloggning infördes. Efter större uppgraderingar (ORM, Node, ramverk): kontrollera error-loggen morgonen efter.
- Sentry ersätter INTE Uptime Kuma. Kuma svarar på "är siten uppe?", Sentry på "vilka fel får användarna?" — en ny site behöver båda. Och larmen måste LANDA någonstans som bevakas: Kumas Discord-larm gick ut 95 gånger under en helg utan att någon såg dem.

## Hälso- och versionskontrakt — i varje app
Varje app ska exponera två endpoints. De är inte features utan kontraktet som övervakning och deploy vilar på:

- **`/api/health`** (eller `/health`): svarar 200 när appen är frisk. Kontrollen ska röra databasen med en billig query när databas finns — "processen svarar" säger inget om att appen fungerar. Kuma-monitorn ska peka HIT, inte på startsidan.
- **`/version.json`**: aktuell version och byggtidpunkt. Deployverifieringen läser den ("vänta tills version.json visar X, kontrollera hälsan"), och hälsomätning under deploy förutsätter att den finns.

Utan kontraktet övervakas "svarar startsidan 200" — vilket var sant för flera appar medan deras API:er kunde vara döda.

## Datamodell — dokumenterad och levande i varje app
Varje app ska ha en **dokumenterad datamodell** (`docs/datamodell.md` eller
motsvarande) som uppdateras i SAMMA release som schemat ändras. Ett schema
säger vilka kolumner som finns; dokumentet säger vad de betyder och hur
tabellerna hänger ihop. Den som tar över appen ska kunna läsa datamodellen
och förstå verksamheten, utan att först läsa all kod.

För experiment-, test- och arkivmappar är detta frivilligt.

### Vad dokumentet ska innehålla
- **Varje modell/tabell med sitt syfte** i en mening — vad den representerar i
  verkligheten, inte vad den heter.
- **Fälten som inte är självklara.** Typerna står redan i schemat; skriv
  betydelsen, enheten, och vad `null` betyder (saknas ≠ noll ≠ nej).
- **Relationerna och vad som händer vid radering** (kaskad, `SetNull`,
  restriktion). Det är här data försvinner tyst när någon inte visste.
- **Unika nycklar och vad de skyddar mot** — t.ex. att normaliserat
  organisationsnummer är unikt per tenant för att stoppa dubbletter.
- **Enum-värden med innebörd.** `ACCEPTED` och `RESOLVED` ser lika ut i koden
  men betyder olika saker för verksamheten.
- **Vilka fält som bär persondata**, så GDPR-export och radering går att
  stämma av mot modellen i stället för mot minnet (se GDPR-avsnittet).
- **Ett ER-diagram** där det går att generera (t.ex. mermaid `erDiagram`) —
  genererat, inte handritat, annars driver det isär.

Fältkommentarer i schemat (Prisma `///`, SQL `COMMENT ON`) är förstahandsvalet
för *varför ett fält finns*: de ligger bredvid fältet och syns i samma diff.
Dokumentet ger överblicken — hur delarna hänger ihop.

### Checklistan när en ny modell läggs till
En ny tabell är inte klar när migrationen kört. Gå igenom:

1. **Radering och export (GDPR):** ingår den i kontokraderingen och i
   dataexporten? En modell som glöms här blir kvarlämnad persondata.
2. **Sammanslagning och andra massoperationer:** har appen en "slå ihop
   dubbletter"-funktion, måste den nya modellen med i listan.
3. **Backup:** täcks den av masterbackup (ligger den i rätt databas)?
4. **API:t:** ska den nya datan gå att nå programmatiskt (se API-avsnittet)?
5. **Dokumentationen:** datamodellen uppdateras i samma release.

Punkt 1 och 2 är de som faktiskt smäller. **Skriv ett test som jämför listorna
mot schemat** i stället för att lita på minnet — en modell med främmande
nyckel som saknas i sammanslagningen raderas tyst när två poster slås ihop,
och det upptäcks först när någons data är borta. Ett sådant test fångade
exakt det i Custio 2026-09-07, samma dag modellen skrevs.

## API och webhooks — standard i varje app med riktiga användare
Varje app med riktiga användare ska ha ett **anropbart API** och **utgående
webhooks**. Appens funktioner ska gå att nå programmatiskt, inte bara via
UI:t — det är förutsättningen för integrationer, automatisering och
MCP-anslutningar. För experiment-, test- och arkivmappar är detta frivilligt.

### API:t
- **Appens kärnfunktioner ska vara nåbara via ett dokumenterat API** (REST/JSON
  under `/api/...`), med samma valideringar och behörighetskontroller som UI:t.
  Interna endpoints som bara appens egen frontend använder räknas inte som
  detta API förrän de är dokumenterade och stabila nog att anropa utifrån.
- **API:t följer med funktionerna — i samma release.** En ny funktion är inte
  klar förrän den också är nåbar via API:t. Samma princip som dokumentation
  och policydokument: aldrig "läggs till sen", för sen blir aldrig. Rent
  UI-kosmetik behöver förstås inget API.
- **API-dokumentationen uppdateras i samma release** som API:t ändras —
  helst en genererad OpenAPI-spec ur koden (ett underhållsställe), annars en
  docs-sida som ingår i releasens diff. En odokumenterad endpoint finns inte
  för den som integrerar.
- **Dokumentationen ska räcka för att integrera utan att läsa koden.** Per
  endpoint: metod och väg, vad den gör, vilken behörighet den kräver,
  parametrar och body med vilka som är obligatoriska, ett exempelanrop med
  exempelsvar, samt **felkoderna och vad de betyder** — "finns inte", "kvoten
  är slut" och "saknar behörighet" är olika besked och ska inte alla bli
  \`500\`. Ange också gränser: rate limit, sidstorlek, maxlängder.
- **Datatyperna i API:t ska gå att slå upp i datamodellen** (se avsnittet
  ovan). Ett fält som heter samma sak i API:t och i databasen ska betyda samma
  sak — gör det inte det, skriv ut skillnaden.
- **Versionera från start** (`/api/v1/...`) och håll kontraktet: en klient
  ska tåla att ligga EN version efter (jfr PWA-avsnittet). Breaking changes
  kräver ny version + rollback-beskrivning (jfr Rollback-avsnittet).
- **Autentisering med API-nycklar** per användare: skapas och återkallas i
  appens inställningar, lagras hashade i databasen, skickas som
  `Authorization: Bearer ...`. Sessionscookies är för webbläsaren — aldrig
  API-auth. Strikt rate limit per nyckel, och nyckelns behörighet är aldrig
  vidare än användarens egen.
- **Finns en MCP-server ska den vara ett tunt lager ovanpå samma API** —
  aldrig en parallell logikväg som driver isär (samma regel som ETT
  policydokument: en källa, inte två som divergerar).

### Webhooks (utgående)
- Appen ska kunna **skicka webhooks vid viktiga händelser** (skapat/ändrat/
  raderat i kärnobjekten, statusbyten) till URL:er användaren registrerar i
  inställningarna, med val av vilka händelser som prenumereras.
- **Signera varje leverans** med HMAC (delad hemlighet som visas EN gång vid
  registrering) så mottagaren kan verifiera avsändaren. Payload innehåller
  händelsetyp, tidpunkt och objektet — aldrig hemligheter eller andra
  användares data.
- **Leveranser får aldrig fälla appen:** skicka asynkront (kö/efterhand),
  timeout på några sekunder, omförsök med backoff, och inaktivera endpoints
  som failar konsekvent (samma städprincip som döda push-prenumerationer).
  Ett webhook-fel loggas — det stoppar aldrig den handling som utlöste det.
- **Leveranslogg** per endpoint (senaste försök, svarskod) synlig för
  användaren, så "varför kom inget?" går att besvara utan serveråtkomst.

Vid NYBYGGE ingår API-struktur, nyckelhantering och webhook-grunden i
scaffoldingen, precis som i18n och mörkt läge. Befintliga appar kompletteras
successivt — men fråga Pierre innan en stor engångsinsats påbörjas; det är
ett eget arbete, inte något som smygs in i en annan release.

## PWA-uppdatering — skydd mot inaktuella klienter
En PWA som cachar lämnar användare på gammal kod i dagar: de rapporterar buggar som redan är rättade, och gamla klienter pratar med nya API:er.

- När en ny service worker är installerad ska appen visa en diskret "Ny version finns — ladda om" som laddar om vid klick. Aldrig tyst tvångsomladdning mitt i arbete.
- Cachen versioneras mot appversionen så en release faktiskt slår igenom (jfr Mobil/PWA-avsnittet).
- API-ändringar ska tåla att en klient ligger EN version efter — bryt aldrig ett endpoint-kontrakt i samma release som klienten som slutar använda det.

## GDPR och dataskydd — bas för appar med riktiga användare
Apparna har användare utanför hushållet. Minimum:

- **Integritetspolicy-sida** som säger vad som lagras och varför. Att Umami är cookiefritt är en styrka — skriv det.
- **Export och radering:** användaren ska kunna exportera sina data och radera sitt konto med ALL sin data. Radering är radering (kaskader i databasen), inte `isActive=0`. Erbjud gärna anonymisering som alternativ där andras data refererar användaren.
- **Ingen persondata i loggar.** E-postadresser, namn och fritext hör inte hemma i `combined.log` — logga användar-id och maskera adresser (`ev***@example.com`) där något alls behövs. Loggarna roteras och är inte ett personregister.
- Mailutskick, pushprenumerationer och AI-anrop till tredje part ska framgå av policyn.

## Policydokument och juridiska sidor — ska finnas, inte bara planeras
Gäller varje app med riktiga användare. Saknas något av nedanstående ska det
**byggas** — det räcker inte att notera att det fattas. En app som samlar
persondata utan publicerad policy är inte klar, oavsett hur färdiga
funktionerna är.

Minimum i varje sådan app:

- **Integritetspolicy** — vad som lagras, varför, hur länge, vilka
  underbiträden som anlitas (AI-leverantör, mailleverantör, analys) och vilka
  rättigheter användaren har. Se GDPR-avsnittet ovan för innehållskraven.
- **Användarvillkor** — tjänstens omfattning, ansvar, betalda planer om
  sådana finns, uppsägning.
- **Kontaktväg** — en adress som någon faktiskt läser. Se
  Företagsuppgifter-avsnittet; hitta aldrig på en support-adress.
- **Cookie-/analysinformation** där sådant används, även när lösningen är
  cookiefri (att Umami är cookiefritt är en styrka — skriv det).

Krav på hur de görs:

- **Nåbara UTAN inloggning**, länkade från footern och från registreringen.
  En policy man måste ha konto för att läsa är inte publicerad.
- **Personuppgiftsansvarig ska stå utskriven** med bolagsnamn enligt
  Företagsuppgifter. Ett juridiskt dokument som inte pekar ut den verkliga
  juridiska personen är inte bindande.
- **Datum för senaste ändring** ska framgå i dokumentet.
- **ETT dokument per sak.** Finns både en statisk fil och en sida i appen är
  det två källor som garanterat driver isär — välj en, eller generera den ena
  ur den andra. (Achiever hade två integritetspolicyer med olika innehåll,
  upptäckt 2026-09-05.)
- **Uppdateras i SAMMA release som databehandlingen ändras.** Ny
  AI-leverantör, ny datatyp (t.ex. ljud vid diktering), ny integration eller
  nytt mailutskick — då ändras policyn samtidigt, inte "sen".
- Följer appens språkregel: svenska som grund, engelska där appen är
  tvåspråkig. Blanda aldrig språk i samma dokument.
- Vid NYBYGGE ingår sidorna i scaffoldingen, precis som i18n och mörkt läge.

## Tillgänglighet — bas för alla appar
Mobilavsnittet täcker touch; detta gäller överallt:

- All funktionalitet nåbar med enbart tangentbord; synligt fokus (aldrig `outline: none` utan ersättning); Esc stänger modaler och menyer.
- Ikonknappar har `aria-label`; formulärfel kopplas till sina fält (`aria-describedby`); statusmeddelanden annonseras (`role="status"`).
- Kontrast som klarar WCAG AA för text; förlita dig aldrig på enbart färg för att skilja tillstånd.
- Verifiera med tangentbordet vid nya vyer: tabba igenom hela flödet en gång före release.

## UI-kontinuitet — gemensamt formspråk för alla appar
Apparna beter sig likadant (tillgänglighet, mobil, språk) men ser ut som olika produkter. Tre områden är gemensamma för att byte mellan apparna ska kännas som samma hand har byggt dem. Paletten och layouten i övrigt får vara per app — strukturen nedan är det gemensamma.

### Mörkt läge — standard i varje app
- Varje app stödjer ljust OCH mörkt läge från start. `prefers-color-scheme` är default; manuell växlare i inställningarna vars val sparas per användare (serverside där konton finns, annars localStorage) — samma lagringsmönster som språkvalet.
- Minimikravet som gör detta möjligt: appens färger definieras som CSS-variabler på ett ställe och används via `var(--...)` i komponenter — aldrig hex-koder inline. Utan det blir mörkt läge en jakt på hårdkodade färger i varje komponent.
- Båda lägena ska klara kontrastkraven i Tillgänglighetsavsnittet — mörkt läge med grå text på grå botten är sämre än inget mörkt läge.
- Verifiera båda lägena före release, inte bara det utvecklaren själv kör.

### Komponentkonventioner — samma vardagsmönster överallt
- **Knappordning:** primärknappen till höger, "Avbryt" sekundär till vänster. Alltid, i alla dialoger och formulär.
- **Destruktiva handlingar:** röd knapp, bekräftelsedialog som beskriver konsekvensen ("3 projekt och deras data raderas"), och ALDRIG default-fokus på den destruktiva knappen — Enter ska inte kunna radera av misstag.
- **Dubbelklickskydd:** submit-knappar inaktiveras medan anropet pågår (med laddindikator i knappen). Varje app som saknar detta får så småningom dubbletter i databasen.
- **Formulär:** label ovanför fältet, validering vid blur, felmeddelandet vid fältet (kopplat med `aria-describedby` enligt Tillgänglighetsavsnittet) — inte bara en samlad lista överst.
- **Toasts/notiser:** en position per app (rekommenderat nere till höger), auto-stäng efter ~4 s. Fel som kräver användarens handling visas ALDRIG som toast — de ska stå kvar tills de hanterats.
- **Laddningstillstånd:** skeleton för innehållsytor som väntar på data, spinner endast i knappar/små ytor. Aldrig en helsides-spinner för en delvy.

### Ikonografi och ordval
- **Ett ikonbibliotek per app, aldrig blandat.** Standard är **lucide** (`lucide-react` där React används, lucide-SVG:er annars) — samma linjestil överallt ger igenkänning även när paletterna skiljer sig.
- **UI-ton:** du-form, sentence case ("Spara ändringar", aldrig "SPARA ÄNDRINGAR").
- **Samma svenska termer för samma handling i alla appar:** "Radera" (destruktivt), "Ta bort" (plockar bort ur lista utan att förstöra data), "Spara", "Avbryt", "Stäng", "Redigera", "Lägg till". Uppfinn inte synonymer — och lägg motsvarande engelska termer i språkfilerna med samma konsekvens.

## Felsidor och error boundaries
Ett fel någonstans får aldrig ge vit skärm eller rå stacktrace:

- **Error boundary per route/vy** (jfr Achievers `RouteErrorBoundary`): en krasch i en vy ger ett vänligt felkort med "försök igen", inte en död app.
- **404-sida** med väg tillbaka, och **offline-sida** i PWA:n när nätet saknas.
- Tomtillstånd är designade, inte tomma: en ny användare utan data ska se vad ytan är till för och hur man kommer igång — inte en tom lista.
- Felmeddelanden till användare är på användarens språk och säger vad man kan göra; tekniska detaljer går till Sentry, inte till skärmen.

## Guidat flöde, tips-knapp och "vad är nytt"
Gäller appar med riktiga användare (Achiever, CogniFin, StaffHub, Stugan, LingoMaster m.fl.). För experiment-, test- och arkivmappar är detta frivilligt — inför det inte där utan att fråga.

- Varje sådan app ska ha ett **guidat genomgångsflöde** (produktrundtur) som förklarar innehållet i varje modul, samt en alltid tillgänglig **tips-knapp** som låter användaren köra guiden igen.
- **Guidens innehåll ska bo i modulen, inte i en central tour-fil.** Varje modul exporterar sina egna steg i en fil bredvid komponenten (t.ex. `modules/budget/budget.tour.ts`). Detta är avgörande: då syns tour-filen i samma diff som kodändringen, och guiden förfaller inte tyst. En central fil som listar alla moduler blir alltid inaktuell — inför aldrig en sådan.
- **Versionera per modul**, inte bara per app: varje modultour har ett eget `version`-fält som bumpas när stegen ändras. Användarens state lagras som vilka modulversioner hen sett (serverside per användare där auth finns, localStorage endast som fallback). Har användaren sett version 2 och aktuell är 3 → erbjud just den modulens guide igen, inte hela rundturen.
- **"Vad är nytt" ska genereras från changelog/release notes**, inte skrivas separat. Utöka changelog-posterna med vilka moduler releasen berör, så kan flödet både visa texten och erbjuda genomgång av just de modulerna. Ett underhållsställe — skapa aldrig en parallell "nyheter"-fil.
- Tips-knappen öppnar en liten meny: rundtur för aktuell sida, "vad är nytt" (med badge endast när det finns osedd version), och möjlighet att köra hela introduktionen igen.
- Regler så att det inte blir irriterande: auto-öppna aldrig vid varje besök; visa "vad är nytt" automatiskt endast vid minor/major, aldrig patch; alltid stängbar med Esc och tydligt kryss; blockera aldrig pågående arbete.
- **Deploy ska varna vid förfall:** om filer i en modulkatalog ändrats sedan förra taggen men modulens tour-`version` är oförändrad → varning i deployflödet. Samma princip som `COVERAGE ERROR` i masterbackup: systemet upptäcker sitt eget förfall istället för att det märks ett halvår senare.
- Spåra tour-events i Umami (`tour_started`, `tour_step_viewed` med steg-id, `tour_completed`, `tour_skipped`). Avhopp på ett visst steg betyder oftast att modulen är förvirrande, inte att guiden är dålig — det gör guiden till ett produktinsiktsverktyg.
- Biblioteksval är ännu inte låst. Eftersom portföljen har blandad stack är ett ramverksagnostiskt alternativ att föredra framför React-specifika. Fråga Pierre innan du väljer bibliotek till ett nytt projekt.

## Feedbackväg — i varje app med riktiga användare
Samma status som guidat flöde och Kuma-monitor: en app med riktiga användare ska ha en inbyggd väg att rapportera buggar, idéer och övrigt — inte en mailto-länk (kräver mailklient, ger ingen spårbarhet).

- Liten knapp i menyn → enkelt formulär: typ (Bugg/Idé/Övrigt) + fritext. Sida, appversion och webbläsare bifogas automatiskt så rapportören slipper.
- Inskicken sparas i databasen med status (ny/sedd/planerad/klar/avfärdad), visas i en adminvy, och mailas till adminadresserna vid inskick (mailet får aldrig fälla inskicket).
- Inloggning krävs och strikt rate limit på inskick.
- Referensimplementation: Achiever 4.70.0 (`/feedback` + `/admin/feedback`, modellen `Feedback`).

## Mobil och PWA — obligatoriskt för alla appar
Alla appar ska fungera fullt ut på mobil enhet och vara en komplett PWA. Mobilen är inte ett andrahandsläge som fixas sist — den ska fungera från början.

### PWA-grund
- Komplett `manifest.json` (namn, kort namn, ikoner i alla nödvändiga storlekar inkl. maskable, `theme_color`, `background_color`, `display: standalone`, `start_url`, `scope`).
- Service worker som ger installbarhet och rimligt offline-beteende — minst en offline-fallback, gärna cache av statiska assets. Se upp med stale cache: versionera cachen mot appversionen så en release faktiskt slår igenom (jfr Stugans service worker/cache-flöde).
- Appen ska gå att installera på hemskärmen och starta utan webbläsarens adressfält.
- Verifiera med Lighthouse PWA-audit innan en release anses klar — inte bara "det såg ut att funka i desktop-läge".

### Push-notiser (VAPID)
- Push-notiser implementeras med **VAPID** (Web Push). VAPID-nycklar genereras per app och läggs i `.env` på servern — publik nyckel exponeras till klienten, privat nyckel lämnar ALDRIG servern och committas aldrig.
- Fråga alltid användaren om notis-tillstånd i ett meningsfullt ögonblick (efter en handling som gör nyttan tydlig), aldrig som en popup direkt vid första sidladdning — det ger permanent nekad behörighet.
- Hantera alla tre lägena korrekt: `default`, `granted`, `denied`. Appen ska fungera fullt ut även när användaren nekar.
- Prenumerationer ska sparas serverside och städas bort när de blir ogiltiga (410/404 från push-tjänsten) — annars växer prenumerationstabellen med döda endpoints.
- iOS kräver att appen är installerad på hemskärmen för att push ska fungera. Bygg inte flöden som antar att push finns i Safari-fliken.

### Zoom, scroll och layout
- Korrekt viewport-meta med `viewport-fit=cover`. **Använd ALDRIG `user-scalable=no` eller `maximum-scale=1`** — det bryter tillgängligheten för synsvaga. Lös zoomproblem genom att göra zoom onödig, inte förbjuden.
- Inputfält ska ha minst 16px teckenstorlek — mindre än så gör att iOS auto-zoomar vid fokus, vilket är den vanligaste orsaken till att layouten "hoppar".
- Inget innehåll får hamna utanför viewporten. Ingen horisontell scroll ska uppstå. Kontrollera med devtools och på riktig enhet — inte bara i responsivt läge.
- Respektera safe-area-insets (notch, hemknappsindikator, statusfält) med `env(safe-area-inset-*)` så innehåll och knappar inte hamnar under systemets UI.
- Använd `dvh`/`svh` snarare än `vh` där det är relevant — `100vh` blir fel när mobilens adressfält fälls in/ut.
- Sätt `overscroll-behavior` där det behövs så att scroll i en modal eller lista inte "läcker" och scrollar sidan bakom.
- Touch-targets minst 44x44px. Hover-beroende interaktion får aldrig vara enda vägen till en funktion.

### Meny och navigation
- Menyn ska vara robust på mobil: fungera med touch, gå att stänga med Esc och genom att klicka utanför, låsa bakgrundsscroll när den är öppen, och släppa fokusfällan korrekt när den stängs.
- Menyn ska vara tillgänglig via tangentbord och ha korrekta ARIA-attribut (`aria-expanded`, `aria-controls`).
- Menyn får aldrig täcka innehåll den inte är tänkt att täcka, eller hamna under safe-area. Testa med öppet tangentbord — det är där mobilmenyer oftast går sönder.
- Navigationen ska fungera likadant installerad som i webbläsaren (inga länkar som antar att adressfältet finns).

### Testning
- Testa på riktig mobil enhet innan release, inte bara i webbläsarens responsiva läge. Emulatorn missar tangentbordsbeteende, safe-area och installerat PWA-läge.
- Testa både installerat (hemskärm) och i webbläsarflik — de beter sig olika, särskilt på iOS.

## Språk — svenska och engelska i alla appar
Alla appar med användargränssnitt ska stödja **svenska och engelska**, och användaren ska själv få välja.

- **Vid NYBYGGE är tvåspråkigt stöd (sv/en) en del av grunduppsättningen från första committen** — i18n-ramverk, BÅDA språkfilerna och språkväljare ingår i scaffoldingen. Det är aldrig något som "läggs till sen": en app som byggs enspråkig får hårdkodade strängar i varje komponent, och konverteringen i efterhand är ett eget projekt (se sista stycket). Bygg rätt från start så uppstår aldrig det projektet.

### Användarens val
- Appen ska erbjuda språkval: en tydlig språkväljare i inställningarna, och gärna en fråga vid första inloggningen (eller följ webbläsarens språk som förval). Svenska är standard/fallback.
- Valet sparas per användare (serverside där konton finns, annars localStorage) och gäller hela appen — inte bara vissa vyer.
- Mail och notiser skickas på användarens valda språk där mallar finns; saknas översättning gäller svenska, aldrig en blandning i samma meddelande.

### Regler så att det inte förfaller
- **All UI-text går via översättningsfunktionen** (t.ex. i18next `t('nyckel')`). Ingen hårdkodad text i komponenter — inte ens "tillfälligt"; tillfälligt blir permanent.
- **Varje ny nyckel läggs i BÅDA språkfilerna i samma commit.** En nyckel som bara finns i svenskan ser hel ut för den som utvecklar (svenska är fallback) men lämnar engelska användare med svensk text mitt i gränssnittet — det syns aldrig i utvecklarens egen testning.
- **Ingen HTML i översättningssträngar.** En sträng med `<strong>{{email}}</strong>` renderas som synlig taggtext när komponenten använder `t()` rakt av (hände i Achiever 2026-09-01). Formattering görs i komponenten (JSX/`<Trans>`), strängarna hålls rena.
- Datum, tal och valuta formatteras via locale (`toLocaleDateString` m.m. med användarens språk), inte med hårdkodade format.
- Å, ä och ö ska vara korrekta i svenskan — inga omskrivningar (aa, ae, oe).
- Vid större ändringar: sök igenom nya komponenter efter hårdkodade strängar innan release, på samma sätt som SEO/analytics kontrolleras proaktivt.

### Befintliga appar
Nya funktioner ska följa detta från dag ett. Befintliga appar med enbart svenska konverteras successivt — men fråga Pierre innan en stor engångskonvertering påbörjas; det är ett eget arbete, inte något som smygs in i en annan release.

## SEO och analytics
- Varje site ska vara förberedd för bästa möjliga SEO: relevanta meta-taggar (title, description), semantisk HTML, korrekt struktur på rubriker, sitemap.xml och robots.txt där det är relevant för sitens typ.
- Analytics sker via en självhostad Umami-installation (Docker-container) på https://analytics.lconsulting.se — INTE Google Analytics. Varje site ska utvecklas med fullt stöd mot denna Umami-instans.
- Sidvisningar ska spåras som standard via Umamis tracking-script. Utöver det ska relevanta events (t.ex. formulärinskick, knapptryck, viktiga användarflöden, konverteringar) spåras med Umamis event-tracking där det är meningsfullt för projektet.
- Om Umami-integrationen saknas i ett projekt, komplettera med det (kontrollera att rätt website-ID/spårnings-script för siten finns konfigurerat — fråga Pierre om ID:t saknas) istället för att lämna analytics okonfigurerat.
- Kontrollera detta proaktivt vid större ändringar eller vid uppsättning av en ny site — anta inte att SEO/analytics redan är på plats bara för att det inte nämnts.

## Vid osäkerhet
- Om instruktionerna i denna fil är tvetydiga, motsägelsefulla, eller inte täcker situationen — fråga innan du agerar. Gissa aldrig dig till en lösning i produktionsnära kod.
- Pierres direkta instruktion i chatten/sessionen väger alltid tyngre än denna fils standardregler (t.ex. om han uttryckligen ber om att hoppa över backup-steget för ett specifikt tillfälle). Men påminn honom en gång kort om vad som hoppas över (t.ex. "Kör utan backup som du bad om — observera att ingen databas-backup tas denna gång"), så det är ett medvetet val, inte en tyst avvikelse.
