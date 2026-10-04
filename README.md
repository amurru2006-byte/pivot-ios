## 0.5.1 — revisione della proposta Claude

- La proposta ricevuta è una specifica, non un'implementazione. È stata confrontata con il Coach 0.5.0: non viene sostituito il modello con un 2B/3B non misurato sull'iPhone.
- Output AI a campi chiusi: scelta di un'opzione verificata e tono. Il testo visibile usa i dati del motore; ID inventati, campi aggiuntivi, JSON malformato o testo libero vengono scartati. È validazione dopo generazione, non decodifica vincolata: non si promette una percentuale di successo del modello.
- Le attività con lo stesso titolo o punteggio richiedono chiarimento. I pulsanti di recupero passano l'identità della singola occorrenza; titolo e orario aiutano anche in chat.
- Negazioni e parole come “personal” non sono interpretate come richieste di recupero. Un bersaglio non riconosciuto non viene sostituito con l'unico evento passato.
- “Oggi”, “domani” e “dopodomani” delimitano il giorno di recupero e conservano le date anche oltre mezzanotte. Nessun accorciamento implicito e nessuna stima di tragitto inventata.
- Un suggerimento AI arrivato dopo un cambio del Calendario, l'accettazione o lo scarto di un'opzione obsoleta non viene aggiunto alla chat.
- Migrazione dati invariata e compatibile con 0.5.0. Preferenze ancora manuali, nessun apprendimento statistico o lettura HealthKit introdotto da questo aggiornamento.

## 0.5.0 — Pivot Coach (prima versione)

- Accesso al Coach dalla home, mantenendo le cinque schede dell’app.
- Recuperi completi e conservativi, con tragitti confermati, durata minima, impegni fissi, orari di sonno e controlli contro i conflitti.
- Accettazione locale e seconda conferma separata nel Coach prima di scrivere sul Calendario. La singola occorrenza viene riletta e verificata anche immediatamente prima del salvataggio EventKit.
- Chat divise per giorno, eliminabili, incluse nel resoconto e nei backup. Preferenze aggiunte manualmente dall’utente, consultabili e cancellabili.
- Qwen3 0.6B Q4_K_M opzionale: download di 397 MB a revisione fissa, verifica SHA-256, Application Support esclusa dal backup. Nessun modello nel repository/bundle e nessuna API a pagamento. LLM.swift fissato a un commit.
- Il modello scrive commenti, non esegue azioni. Le proposte cliccabili vengono sempre dal pianificatore verificato. Se il modello manca, il Coach resta utilizzabile.
- Questa prima versione non comprende apprendimento statistico automatico, tagli multipli, modifica libera di eventi futuri o import HealthKit. Il dialogo locale e le prestazioni vanno verificati sul dispositivo reale; un modello piccolo può sbagliare.
- Attività fatte/parziali attenuate, attività saltate nascoste nella home ma conservate nello storico; salvataggio esplicito chiude i dettagli. Selettore data più visibile per le registrazioni oltre mezzanotte.

Dipendenza locale: [LLM.swift](https://github.com/eastriverlee/LLM.swift), licenza MIT. Modello: [Qwen3 0.6B GGUF](https://huggingface.co/unsloth/Qwen3-0.6B-GGUF), licenza Apache-2.0. Non concede accesso automatico di ChatGPT ai dati di Pivot.

## 0.4.1 — conferme soltanto per nuove lezioni

- Il primo import riuscito dopo l'aggiornamento registra gli eventi esistenti senza richiedere luoghi retroattivamente.
- Le nuove lezioni generano una richiesta; una serie ricorrente genera una sola richiesta, non una per ogni settimana.
- Baseline e richieste sono salvate nello storico/backup. Spostare o rinominare eventi esistenti non riattiva il pop-up.
- Gli eventi vecchi sincronizzati in ritardo vengono esclusi usando la data di creazione del calendario, quando disponibile. Senza questa data, il riconoscimento usa gli identificativi già osservati.
- La scelta di luogo rimane modificabile manualmente nella singola occorrenza; non vengono inventati luoghi o tragitti per gli eventi precedenti.

## 0.4.0 — orari, sonno, lezioni, cardio e schede palestra

- Orari reali con data e selettore iOS a rotella; durate in ore/minuti, secondi per cardio. Nessuna conversione manuale in minuti.
- Navigazione giorni sopra la dashboard e pulsante Oggi; colori sRGB del calendario conservati senza arrotondarli a 8 bit.
- Lavoro generico distinto dalle ripetizioni. Conferma luogo per singola lezione, ultima scelta proposta per studente, tragitti confermati dall'utente. Il popup compare quando Pivot rileva l'evento mentre è attiva, non istantaneamente sopra un'altra app.
- Sonno manuale dai valori leggibili su Apple Watch: durata, sveglia, ora a letto, punteggio/qualità e interruzioni facoltative. Nessuna lettura HealthKit né ricostruzione delle fasi.
- Camminata, escursione e tapis roulant con dati Fitness facoltativi; velocità e inclinazione per tapis roulant.
- Sezione Palestra con importazione PDF strutturati, conferma della scheda, serie/carichi/ripetizioni, ultimo allenamento, tips personali persistenti ed esportazione testuale per il personal. Schede e dati inclusi nei backup.

### Formato del PDF palestra

Un PDF normale o scansionato non viene interpretato automaticamente. La scheda rielaborata deve contenere testo estraibile PDFKit con un blocco delimitato da `PIVOT-WORKOUT-V1` e `END-PIVOT-WORKOUT`. Fra i delimitatori: JSON UTF-8 codificato Base64, spazi e ritorni a capo permessi nel Base64. Usare `TrainingPDFFormat.encodedBlock` come riferimento.

Struttura JSON: `formatVersion: 1`, `name`, `days`. Ogni giorno ha `id`, `name`, `exercises`. Ogni esercizio ha `id` stabile fra aggiornamenti, `name`, `sets` (1–30), `reps` (testo, conserva range/istruzioni), `restSeconds` (0–3600), `coachNotes`. Non aggiungere prescrizioni o carichi non indicati dal personal. Identità di esercizio diversa se cambia significativamente la variante: non trasferire carichi fra macchine/esercizi differenti. Fino a 6 schede conservate; nessun cambio di codice necessario per una nuova scheda conforme.

Le registrazioni precedenti e i PDF sopravvivono a un aggiornamento sopra la stessa app; la cancellazione dell'app richiede un backup esterno. Notifiche reali su iPhone/Watch e invio automatico Gmail restano da verificare/configurare separatamente. Non c'è un collegamento automatico alla chat.

## 0.3.0 — materiali di studio e verifica consolidata

Ogni sessione di studio può avere obiettivi, esercizi e PDF importati da File. I documenti sono copiati nel contenitore privato dell’app, apribili e condivisibili: massimo 6 per sessione, 10 MB ciascuno, 50 MB totali nello storico. Non c’è una sincronizzazione automatica con ChatGPT: salvare il PDF ricevuto in File, poi importarlo nella sessione.

Il normale salvataggio scrive solo i metadati dei documenti. I PDF vengono incorporati nel backup completo esterno/esportato in un processo in background. Il ripristino verifica i documenti prima di sostituire lo storico e usa nuove identità dei file, mantenendo intatte le copie precedenti. Un documento mancante impedisce di sovrascrivere la copia completa. Durante il ripristino i salvataggi sono bloccati per evitare di perdere una registrazione concorrente. I backup precedenti senza documenti restano compatibili.

Promemoria: pasti, mattina e resoconto serale hanno precedenza sulle ripetizioni orarie quando la coda iOS è piena. Lo stesso programma deduplicato e la stessa scelta di frequenza universitaria valgono per agenda e notifiche. Le impostazioni includono un collegamento alle notifiche di Pivot in iOS.

Revisione: dati, duplicati, spostamenti, backup, incassi, compatibilità e promemoria; successivamente test dei percorsi sul simulatore, compreso importazione/apertura PDF e persistenza dopo riavvio dell’app. Le copie Google devono prima essere sincronizzate da iOS; una demo web non verifica questo passaggio né la consegna reale delle notifiche su iPhone.

# Pivot iOS

## Correzioni 0.2.4

Lettura EventKit e backup esterni fuori dal processo dell'interfaccia. Le note HTML
vengono convertite in testo senza caricare risorse web. Gli aggiornamenti si accorpano
senza perdere le modifiche arrivate durante una lettura. La deduplicazione e la home
riducono i calcoli ripetuti. Test UI per tocchi durante un import lento e dopo il rientro
nell'app, oltre ai test dei dati e della sincronizzazione.

## Novità 0.2.3

- Monogramma aggiornato anche nella schermata nativa di avvio, con risorse rinominate.
- Per copie Google/iCloud della stessa attività, mantiene il colore del calendario iCloud originale.
- Calendari riletti al ritorno nell’app, alle modifiche, ogni minuto durante l’uso e manualmente. Le modifiche esterne di titolo/orario nello stesso giorno conservano le risposte; un piano locale obsoleto non prevale sul Calendario.
- Domande diverse per studio, pasti, allenamento, università, ripetizioni, routine e uscite.
- Guadagno collegato alla ripetizione: importo concordato e importo ricevuto distinti, senza doppio incasso al secondo salvataggio.
- Totale annuale per data di pagamento, importo pregresso aggregato modificabile, storico per anno ed esportazione Excel .xlsx con riepilogo, incassi e lezioni.
- Il nuovo anno non cancella pagamenti, lezioni non saldate o storico.
- Avviso giallo da 4.500 €, progressione fino al rosso a 5.000 € e notifica per ciascuna soglia/anno. È un riferimento INPS per lavoro realmente occasionale, non un tetto legale o un’esenzione fiscale. L’app non determina il regime fiscale individuale.
- Un eventuale importo iniziale privato può essere fornito nel pacchetto di installazione attraverso le chiavi Info.plist PivotInitialIncomeCents e PivotInitialIncomeYear. Nessun dato finanziario personale è incluso nel repository.

# Pivot — La tua giornata, riadattata

### Novità 0.2.2
- Icona e schermata iniziale con il monogramma bianco e viola.
- Copie dello stesso appuntamento importate da account diversi riunite in una scheda, preservando le risposte già salvate.
- Gli eventi con orario hanno precedenza sulle loro vecchie copie a giornata intera. Le occorrenze ricorrenti restano separate.
- Il calendario Lavoro identifica le ripetizioni anche quando il titolo contiene studio, laboratorio o esame.
- Per gli eventi che proseguono il giorno dopo vengono mostrate le date e la continuazione, senza cambiare l’orario finale.

App iOS nativa personale, SwiftUI, iOS 17 o successivo. Versione 0.2.2: interfaccia rinnovata, categorie e agenda corrette.
Il repository contiene soltanto codice. Nessun calendario, cliente, pagamento o backup reale.

## Aggiornamento 0.2.1

- Calendari Des e Amici distinti, con cuore e gruppo e i colori originali.
- Scelta giornaliera della frequenza universitaria: le lezioni non previste restano consultabili ma non entrano nel programma, nelle richieste di resoconto o nei recuperi. Gli esami rimangono protetti.
- Un'indicazione esplicita nelle note della routine (`Università: oggi non frequento le lezioni.`) applica la scelta del giorno; la scelta manuale in Pivot può modificarla.
- Le sovrapposizioni sono segnalate, senza cancellare o spostare automaticamente impegni.
- Icona nativa e schermata di avvio, eventi di più giorni con date leggibili e backup 0.2 compatibili.

## Cosa funziona nella prima versione

- Legge i calendari dell'iPhone con EventKit; esclusione festività e selezione dei calendari.
- Giornata, evento in corso/appena concluso, pulsanti Inizia/Termina, compilazione libera.
- Fatto/parziale/saltato, motivazione obbligatoria per gli ultimi due, note, energia, fame pre/post.
- Diario con sveglia reale, umore, energia e condivisione manuale del resoconto.
- Entrate effettive per data di pagamento, studenti, tariffe, lezioni, saldo mancante e pagamenti parziali.
- Ricerca di tre spazi nei prossimi tre giorni per recuperare un evento intero, con tragitti confermati.
- Modifiche solo in Pivot oppure nel Calendario dopo anteprima e conferma esplicita; solo questa occorrenza.
- Database JSON persistente e versionato; salvataggi atomici; dati illeggibili non vengono azzerati.
- Backup esterno tramite cartella scelta nell'app File, copia precedente e ripristino con conferma.
- Notifiche locali dopo evento, dopo 30 minuti, poi ogni ora nelle ore consentite; avvisi pasti a −30/−10.
- Tema scuro e colori dei calendari.

## Limiti espliciti della versione attuale

- Non c'è un'IA autonoma né un collegamento automatico a questa conversazione ChatGPT.
- I percorsi usano tempi inseriti e confermati dall'utente; non vengono interrogate API di routing.
- Nessuna compressione automatica di altri eventi. Il recupero ha durata completa e non sacrifica studio o impegni fissi.
- La priorità studio vicino agli esami è impostabile dall'utente; per ora influisce sui consigli, non su un motore globale di ripianificazione.
- Aprire l'app ogni giorno e dopo modifiche al calendario aggiorna gli avvisi. iOS non garantisce esecuzione continua in background.
- Notifiche limitate ai 60 avvisi futuri più vicini, entro 48 ore, per rispettare i limiti iOS. Full immersion e impostazioni possono silenziarle.
- I pasti vengono letti dalle note del calendario: non vengono inventate grammature o prescrizioni.
- Automazioni avanzate e promemoria di incasso dedicati restano da sviluppare.

## Compilazione da Windows, senza Mac

Ogni push su `main` avvia GitHub Actions su un runner macOS. Esegue i test del nucleo Swift,
genera il progetto con XcodeGen e produce un `.ipa` **non firmato**.

1. Aprire Actions → Compila Pivot per iPhone → esecuzione completata.
2. Scaricare l'artefatto `Pivot-iPhone-unsigned` ed estrarre l'IPA dallo ZIP.
3. Firmare e installare con AltStore Classic oppure Sideloadly da Windows usando il proprio Apple ID.
4. Il rinnovo con account gratuito richiede la rifirma periodica. Non cancellare l'app per rinnovarla.

Il codice non contiene Apple ID, password, certificati o chiavi. Il workflow ha soltanto permesso di lettura.
Non inviare credenziali in chat e non salvarle nel repository.

## Prima installazione: sicurezza dei dati

1. Consentire Calendario e notifiche.
2. Impostazioni → Scegli cartella backup → una cartella in iCloud Drive, **non** la cartella interna di Pivot.
3. Inserire uno studente e una lezione di prova, registrare una giornata e generare il backup.
4. Controllare nell'app File l'esistenza di `Backup Pivot.json`.
5. Installare una nuova build sopra l'app e verificare dati e pagamenti.
6. Esportare un backup e provarne il ripristino. Solo dopo usare lo storico reale.

Il backup completo è personale e non cifrato dall'app: conservarlo in una cartella privata.
iOS gestisce la sincronizzazione iCloud; una copia scritta sul dispositivo non equivale a una conferma
che sia già stata caricata su iCloud. Pivot mostra lo stato e l'ora della copia esterna.

La cancellazione dell'app rimuove il suo archivio locale. Un backup esterno rimane nella cartella scelta.
Dopo reinstallazione: Ripristina un backup, poi riseleziona la cartella. Conservare lo stesso
bundle identifier `app.pivot.personal` e lo stesso Apple ID per gli aggiornamenti in sede.

## Sviluppo e test

`swift test` verifica denaro in centesimi, validazione e round-trip dei backup, conservazione dello storico,
vincoli del recupero, tempi di viaggio, eventi ricorrenti e cambio ora in Europe/Rome.
La build iOS su GitHub compila tutte le schermate e i servizi. Resta necessario il test su iPhone reale.

Le sorgenti core sono in `Core/`; app e servizi in `Pivot/`; specifica XcodeGen in `project.yml`.
Una futura modifica dello schema dati richiede migrazione e test prima dell'installazione: non cambiare
schema o identificativo dell'app per aggirare un problema di aggiornamento.

## Interfaccia 0.2 e verifica visiva

Dashboard con azioni Inizia/Termina, agenda con colori dei calendari, diario a schede
e resoconto completo espandibile. Entrate con incassi effettivi, lezioni da pagare
e schede studente. Check-in e registrazioni usano valori esplicitamente inseriti;
un dato mancante non viene trasformato in zero. Date e orari seguono l'Italia.

Il workflow compila anche per il simulatore iPhone e produce l'artefatto
`Pivot-iPhone-previews` con le schermate principali e i moduli di registrazione. I dati dimostrativi sono abilitati
soltanto in Debug sul simulatore con `--preview`; sono esclusi dall'IPA Release.
L'identificativo dell'app e lo schema dei dati rimangono quelli della 0.1.
