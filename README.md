# Pivot — La tua giornata, riadattata

App iOS nativa personale, SwiftUI, iOS 17 o successivo. Prima versione 0.1.
Il repository contiene soltanto codice. Nessun calendario, cliente, pagamento o backup reale.

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

## Limiti espliciti di 0.1

- Non c'è un'IA autonoma né un collegamento automatico a questa conversazione ChatGPT.
- I percorsi usano tempi inseriti e confermati dall'utente; non vengono interrogate API di routing.
- Nessuna compressione automatica di altri eventi. Il recupero ha durata completa e non sacrifica studio o impegni fissi.
- La priorità studio vicino agli esami è impostabile dall'utente; per ora influisce sui consigli, non su un motore globale di ripianificazione.
- Aprire l'app ogni giorno e dopo modifiche al calendario aggiorna gli avvisi. iOS non garantisce esecuzione continua in background.
- Notifiche limitate ai 60 avvisi futuri più vicini, entro 48 ore, per rispettare i limiti iOS. Full immersion e impostazioni possono silenziarle.
- I pasti vengono letti dalle note del calendario: non vengono inventate grammature o prescrizioni.
- Le prime schermate sono funzionali; grafica, automazioni avanzate e promemoria di incasso dedicati saranno sviluppati dopo il test base.

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
