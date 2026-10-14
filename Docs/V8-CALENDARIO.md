# Serie 8: calendario e giornata reale

Avvio autorizzato direttamente dall'utente il 14 ottobre 2026. L'autorizzazione aggiorna la precedente pausa V8: si lavora in questa chat sul ramo `codex/pivot-v8-calendar`, a partire dalla Serie 7 completa. La 0.7.6 (20) consegnata in iCloud non cambia; il suo collaudo touch prosegue nell'uso reale.

## Esito da ottenere

All'apertura Pivot aggiorna Calendario e Salute, mostra il contesto disponibile della giornata e distingue ciò che è stato fatto, è in corso, è parziale, è esplicitamente saltato oppure manca ancora di una risposta. Aiuta a scegliere cosa recuperare e cerca un intervallo sufficiente per l'intera attività e i suoi spostamenti. In chat conserva il contesto tra «mi sono svegliato ora» e «iniziamo dal pranzo e trova spazio per la palestra».

Un evento passato senza registrazione è da verificare. Il sonno che si sovrappone a un evento fornisce un motivo per chiedere, non la prova certa che l'attività sia stata saltata. Il termine del sonno importato non prova un risveglio appena avvenuto né garantisce la disponibilità immediata dei dati HealthKit. Orari manuali restano autorevoli. Eventi eliminati non vengono ricreati dallo storico.

## Primo blocco preparato

- Riutilizzati `CoachV8Context`, `CoachV8Planner` e gli 11 test della fondazione precedente; il contesto di rete continua a usare alias e non include titoli, indirizzi, note, identificativi Calendario o dati sanitari.
- `DayRecoveryReview`: fotografia locale con stati distinti, arretrati fino a sette giorni, preferenza di recupero esplicita, rilevazione di una proposta già presente, dati Salute/manuali distinti. Funzione senza mutazioni o notifiche ripetute.
- `TrainingDurationEstimate`: mediana delle ultime otto sedute complete comparabili entro 180 giorni, almeno tre campioni prima di sostituire il tempo previsto dal Calendario. Stessa scheda, giornata identificata, fase dichiarata, prescrizione, ordine, varianti e struttura delle serie. Carichi diversi non impediscono il confronto temporale. Sessioni vuote, incomplete, saltate, in corso, future, duplicate o con orari invalidi vengono escluse. Nessuna diagnosi o fase inferita.
- Esempio richiesto 60, 90, 75 minuti: stima 75 minuti. Sono mostrabili numero e identificativi dei campioni, minimo/massimo; con meno di cinque campioni il dato resta provvisorio. La mediana è una stima centrale robusta, non una probabilità o una promessa. Minuti frazionari arrotondati in alto. Margine eventuale deve essere esplicito.
- `CalendarTimeBudget`: durata attività separata da andata, preparazione, ritorno e margine. Zero esplicito è valido; preparazione/tragitti non confermati non diventano zero automaticamente.
- `CalendarRecoveryWindows`: ricerca di intervalli completi, rispetto degli altri eventi e dei loro buffer, quiete, disponibilità non confermata degli eventi giornalieri, sola occorrenza corrente e controllo delle proposte già presenti. Nessun accorciamento, spostamento di terzi o scrittura esterna in questo blocco. Questi intervalli non vengono passati alla vecchia conferma modificando falsamente lo snapshot dell'evento.
- Aggiunti 29 test Core per stima, revisione e intervalli; workflow di regressione Core completa sul ramo V8. Tutti sono passati insieme ai test preesistenti e della fondazione riutilizzata.
- Recuperato anche il gateway originale (codice, configurazione, contratto e 10 test). Le 10 prove locali Node con trasporto sintetico sono passate su Windows. Nessun endpoint remoto è stato distribuito o contattato e nessun segreto è presente nel repository.

## Decisioni aggiornate del 14 ottobre

- L'utente sceglie notifica, discussione delle alternative e conferma: nessuna applicazione automatica degli spostamenti. Devono essere disponibili più intervalli e la possibilità di chiedere prima/dopo cena o un altro giorno. Una preferenza conversazionale non può nascondere conflitti.
- Confermate regole riutilizzabili per attività: recuperabile, facoltativa, non recuperabile, con eccezioni per singola occasione.
- Il recupero deve estendersi ai giorni successivi e preservare l'ordine del programma. L'attuale alternanza allenamento/pausa è una preferenza comoda, non un vincolo obbligatorio: l'utente accetta anche due sedute consecutive. Riposi e slittamenti sono discutibili nella conversazione; nessun limite automatico di un giorno intero o 48 ore viene codificato come regola ricevuta.
- Destinazione e tragitto possono cambiare. Origine, palestra, mezzo e orario devono essere parte della richiesta di viaggio: un tempo fisso non vale per casa, università e palestra alternativa. Preparazione variabile e disponibilità della borsa vanno confermate; il nome/indirizzo del Calendario deve essere risolto senza scegliere arbitrariamente tra luoghi omonimi.
- Mezzi pubblici e cammino vanno confrontati in base a disponibilità, attese e coincidenze; il cammino può essere preferibile anche senza essere il percorso nominalmente più breve. Il requisito riguarda tutti gli impegni, non soltanto palestra. Per scioperi, soppressioni e deviazioni servono fonti aggiornate degli operatori e provenienza/data del controllo. L'AI non afferma che una corsa sia disponibile o cancellata senza un dato verificabile. Copertura e accesso automatico ai dati di ciascun operatore restano da verificare.
- Malattia o infortunio possono incidere sulla palestra intera, sui tragitti e sugli altri impegni; non dedurre l'effetto dal solo nome dell'esercizio. L'utente può riferire indicazioni di un professionista, proporre una pausa fino a una data e modificarla in seguito. Nessuna durata minima di guarigione è dedotta dall'AI; una data di rivalutazione non equivale a rientro automatico. Prima della conferma mostrare tutte le attività coinvolte.
- Le tre risposte sono state ricevute. I dettagli personali dei tragitti e gli esempi di malattia/infortunio non sono trasformati in fixture o dati pubblici. Le pause future saranno scelte contestuali, non un interruttore globale obbligatorio.
- L'utente chiede anche un confronto delle strade AI prima della scelta definitiva. La proposta tecnica è in `Docs/V8-DIREZIONE-AI.md`; nessun account o provider reale è stato attivato.

## Passi successivi e informazioni mancanti

1. Unificare la proposta e la conferma Calendario secondo la scelta dell'utente. La notifica apre le alternative e la chat contestuale; ogni cambiamento resta visibile prima della conferma finale.
2. Collegare le regole riutilizzabili a identità esplicite di attività, scheda/giornata e ricorrenza, con eccezioni per singola occorrenza. Non dedurre l'identità soltanto dalla somiglianza del titolo.
3. Integrare un servizio di tragitti e le indicazioni manuali quando il servizio non risponde. Chiarire il mezzo e l'origine effettiva, offrire palestra alternativa e verificare i preparativi necessari. Il termine di un evento universitario non prova da solo la posizione dell'utente.
4. Collegamento dell'associazione evento-scheda/giornata e del budget stimato alla proposta verificata; convalida anche alla scrittura, recupero dell'originale cancellato solo dopo un esito esplicito, storico dell'azione e proposta aggiornata se cambia il contesto.
5. Interfaccia di revisione e proposta proattiva all'apertura dopo i refresh; segnale discreto senza chat duplicata o imposizione di un questionario. Test UI quando il blocco viene collegato.
6. Collegamento di una vera AI con credenziali protette e gateway autenticato. La precedente fondazione non ha endpoint/account attivi. Budget aggiuntivo resta zero euro; prima dell'attivazione verificare disponibilità, privacy e limiti reali. Nessun invio di dati, nuovo account, servizio o costo è stato attivato.

## Palestra e problematiche fisiche: richiesta futura conservata

L'utente vuole in seguito un aiuto contestuale con problematiche registrate, andamento, fasi e proposte di scarico. In questo primo blocco si lavora soltanto sul calendario. Trend del carico o volume non dimostrano da soli stress meccanico, causa del dolore o necessità clinica di scarico. Le fasi restano dichiarate; eventuali ipotesi future saranno distinguibili e confermabili. Nessuna soglia riabilitativa o aumento tra esercizi viene inventato.

## Stato verifiche

Collaudo conclusivo macOS: run 38585969693, job 115927944630, remoto `59bd487bee686d1e7dd200c4cc266713dc373926`, locale `60d8c030e358dddc785cbf270fe58ae26d240745`, albero comune `3bff0286793ea665a361995859c551b319da550b`: **343 Core, zero fallimenti**, compilazione Core riuscita. Include 303 della Serie 7, 11 della fondazione precedente e 29 nuovi. Primo run 38585212355: 340 Core passati; il nuovo collaudo aggiunge e verifica anche gli spostamenti a cavallo del giorno, il budget stimato degli altri allenamenti e la proposta obsoleta. Gateway recuperato dopo questo run, senza ulteriori cambi Swift: **10 test Node locali passati**, provider sintetico.

`git diff --check` superato. Interfaccia, compilazione app iOS, endpoint AI, qualità di conversazione e nuova installazione iPhone non verificati. Il workflow Core non costruisce una nuova IPA e non sostituisce la consegna Serie 7. Notifica/conferma e regole riutilizzabili sono ora scelte confermate; restano da completare il nuovo ciclo multi-giorno, il servizio di tragitti e la configurazione AI. Non considerare il silenzio sulle nuove domande un'autorizzazione aggiuntiva.

Aggiornamento successivo: il collegamento online alla schermata Coach, le impostazioni Keychain, il countdown delle quote e il passaggio esplicito alle regole locali sono ora implementati. Verifiche e limiti correnti in `V8-ONLINE-PRIVACY-E-QUOTE.md`; attivazione accompagnata in `V8-ATTIVAZIONE-GUIDATA.md`. Questo non completa il ciclo multi-giorno, i tragitti o la conferma unica della catena.

Nota filesystem aggiornata: iCloud ha successivamente alterato anche l'indice di `File tecnici/pivot-ios 2`. Non usare più quella copia come checkout di sviluppo e non cancellare o sovrascrivere le copie in conflitto. Il lavoro prosegue nel clone pulito fuori da iCloud `C:/Users/amurr/.codex/visualizations/2026/10/12/01a131e1-f5b9-7601-910e-30fb0037fc63/pivot-v8-work`. Il remoto conserva il codice verificato; l'hash dell'IPA consegnata resta invariato.
