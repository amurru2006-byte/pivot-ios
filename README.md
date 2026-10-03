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
