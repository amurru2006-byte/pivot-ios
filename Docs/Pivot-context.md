# Contesto e prossimi passi

## Richieste confermate dell’utente

Pivot è parte di un progetto personale più ampio: semplificare la vita, migliorare le abitudini e tenere traccia degli impegni. Il lavoro non riguarda soltanto l’app. La precedente chat era «orari esami chimica»; gli obiettivi e i consigli non recuperati verranno ripresentati dall’utente quando servono, senza inventarli.

Dispositivo principale: iPhone 15. Il modello AI locale è stato scaricato. La 0.7.0 è molto lenta; il touch risponde, ma con ritardo. Le cause del codice sono verificabili; il contributo effettivo di ciascuna va misurato sul telefono.

Quando registra una ripetizione e il guadagno, lo studente deve essere ricavato dal titolo del calendario, senza riscrivere il nome. Un cliente esistente va riutilizzato solo se il riconoscimento è univoco. Importo e incasso restano scelte esplicite.

Pagamenti: alcuni studenti pagano sempre settimanalmente, altri a ogni lezione. È richiesta un’abitudine persistente per studente e una scelta separata per una sola lezione: prossima lezione o data scelta. Il residuo di un pagamento parziale non scompare. I settimanali non sono in ritardo prima dell’ultima lezione prevista della settimana, da lunedì a domenica. Promemoria locali e saldo dello studente; un incasso può coprire più lezioni, dalla più vecchia, ma non viene mai inventato alla scadenza. Un anticipo superiore al saldo già guadagnato non viene registrato come compenso.

## Intervento 0.7.4 — bug segnalati sul telefono

- Il dispositivo continua a non collegarsi a Salute dopo la procedura 0.7.3: non dichiarare risolto il problema. L’email delle 12:01 mostra l’errore sulla firma; l’email delle 14:07 contiene 10 immagini, fra cui il carosello Entrate con pallini sopra la spiegazione. Le altre immagini sono riferimenti palestra, non nuove istruzioni.
- Carosello: indicatori/comandi separati sotto la scheda; altezza ricavata dai contenuti, spiegazione multilinea. Test UI verifica geometricamente che la navigazione non copra il testo.
- Salute: errori completi con fase, dominio/codice e versione/build, nessun dato sanitario nella diagnostica. Distinzione fra fallimento dei permessi e solo background; osservatori dopo la richiesta di autorizzazione, rimossi quando si disattiva l’integrazione.
- Causa esterna verificata nel codice: AltStore Classic v2.3 punta ad AltSign `0d3c1a3cac608e724ca0c8d7404253cd5fee9495`, che non mappa HealthKit in `ALTCapabilities.m`. PR AltStore #1762 e AltSign #45 descrivono esattamente la perdita del permesso nella rifirma; sono chiuse, non integrate. Una sorgente dichiara permessi ma non aggiunge la mappatura mancante. Non promettere che reinstallare tramite la sorgente risolva, né consigliare l’acquisto di un account come garanzia.
- Per risolvere sul dispositivo serve un percorso di firma/profilo compatibile. Non cambiare installatore, certificati, account o identificativo dell’app senza accordo e backup verificato. Non chiedere password in chat. Il successo CI dell’IPA non verifica la firma finale del telefono.

Fonti: https://github.com/altstoreio/AltStore/pull/1762 ; https://github.com/rileytestut/AltSign/pull/45 ; https://github.com/rileytestut/AltSign/blob/0d3c1a3cac608e724ca0c8d7404253cd5fee9495/AltSign/Capabilities/ALTCapabilities.m

## Intervento 0.7.3

- Tentativo sulla firma e distribuzione: entitlements nell’IPA e dichiarazioni nella sorgente. Non sufficiente a garantire HealthKit nel profilo finale AltStore, come verificato dopo il fallimento sul dispositivo.
- Osservatori HealthKit per sonno e allenamenti; dopo il consenso iOS può risvegliare Pivot e avviare l'importazione senza un'apertura manuale.
- Dettatura locale continua fra più frasi, punteggiatura Apple e vocabolario contestuale di Pivot, studenti ed eventi. Il testo già scritto o dettato non viene sostituito dai risultati successivi.
- Verifica automatica conclusa sul commit `48a701067157bb848790f02af6d71cd13a23edbf`: 178 test core senza errori, build Release per iPhone, interfaccia su simulatore, entitlements HealthKit e pubblicazione della sorgente AltStore riusciti. Restano da verificare sul dispositivo reale l'autorizzazione finale di Salute, i risvegli decisi da iOS e la fluidità.

## Intervento 0.7.2

- Ordine della prima scheda corretto in Squat, Bench, Deadlift e riordinamento esplicito dei giorni dall'editor.
- Galleria esercizi nell'ordine della scheda, filtri per gruppo muscolare principale e miniature tecniche dal catalogo.
- Per un esercizio ambiguo, scelta manuale dell'immagine da varianti suggerite o dal catalogo completo, senza cambiare l'identificativo storico.
- Riepilogo Entrate scorrevole con grafico per intervallo e stile selezionabili.
- Collegamento all'app Salute rinominato e diagnostica specifica quando la firma usata per installare Pivot ha rimosso l'autorizzazione HealthKit. Il progetto dichiara esplicitamente la capacità; la verifica finale resta sul profilo Apple che rifirma l'IPA sul dispositivo.

## Intervento 0.7.1

- Salvataggi locali seriali, atomici, raggruppati e fuori dal thread dell’interfaccia; stato visibile, retry e attesa prima di esportazioni/ripristino/modifiche al calendario.
- Agenda condivisa calcolata in background; modificare lo storico non rilancia ogni volta Calendario e Salute. Import e notifiche vengono limitati e accorpati.
- Riepiloghi e pianificatore Coach in background. Nessun questionario automatico che copra la schermata; conferme disponibili dall’agenda/Coach e dalle notifiche aperte volontariamente.
- AI locale con contesto e risposta limitati; memoria liberata lasciando il Coach, in background, per pressione memoria/calore/risparmio energia e dopo inattività. Il file AI non viene cancellato.
- Riconoscimento studenti dal calendario, gestione esplicita dell’ambiguità e riutilizzo del cliente nei pagamenti.
- Abitudini di pagamento e rinvii per lezione, scadenze dal calendario e promemoria sul saldo ancora dovuto. Pagamenti cumulativi/partiali con registrazioni in centesimi; il denaro conta solo alla ricezione esplicita.
- Impostazioni → Prestazioni e salvataggio mostra tempi e contatori senza contenuti personali.

## Altre modifiche incluse

Richieste aggiunte durante lo sviluppo: spunta = fatto come previsto, con orari e durata suggeriti dal calendario ma senza sensazioni, incassi o serie inventati. Nessuna autocompilazione alla riapertura: le modifiche salvate dell'utente restano autorevoli. Due riferimenti sulle valutazioni: obiettivo dorato e media blu; media delle medie delle quattro settimane ISO complete precedenti, settimane senza dati omesse. Obiettivo energia iniziale 7/10 modificabile, scelto come default perché l'utente ha confermato la configurabilità ma non ha indicato un numero.

Palestra: modifiche alla scheda con versioni e ripristino; nuova scheda/obiettivo separato, anche senza PDF; sessioni e prescrizioni storiche conservate. Esercizi extra e sostituzioni per singolo allenamento oppure anche per la scheda. Le serie già fatte non vengono riassegnate a un altro esercizio. Catalogo offline ampliabile (876 record, molti nomi inglesi), identificativi stabili e ricerca per nome/muscoli/attrezzo. Statistiche dalla palestra e dal diario esercizio: cronologia, carico, volume, progressione e stima Epley prudente. Illustrazione anatomica locale della panca piana; le altre miniature dimostrative visibili sono caricate dal catalogo online fissato a una revisione. La scheda effettiva del coach e ulteriori disegni anatomici personali restano da fornire/preparare; non inventare la scheda.

## Da affrontare dopo la stabilità

### Evoluzione palestra richiesta il 7 ottobre

L'aggiunta ricevuta non sostituisce il lavoro della serie 7 e non autorizza a scartare quanto già implementato. Va applicata per differenza:

- Pivot è già un'app nativa SwiftUI, usa Swift Charts e salva localmente dati compatibili con i backup esistenti. Non si sceglie un nuovo framework né si riscrive lo storage senza una migrazione esplicita e reversibile.
- Il catalogo attuale contiene già 876 esercizi di `free-exercise-db`, scelta guidata delle varianti, filtri muscolari, cronologia, miglior carico, volume, stima Epley e grafico di progressione. Queste parti si conservano.
- «Eliminare il caricamento manuale delle immagini» significa non chiedere all'utente di caricare una propria foto. Non elimina «Scegli tu l'immagine», che associa una variante tecnica del catalogo quando il nome è ambiguo e che l'utente aveva richiesto esplicitamente.
- Prima di sostituire o affiancare il catalogo con ExerciseDB servono verifica di licenza, copertura reale delle immagini anatomiche, limiti/costi e strategia offline. Il repository ufficiale è AGPL-3.0 e dichiara che gli endpoint esplorativi hanno limiti severi e non sono adatti alla produzione: il codice pubblico non equivale a un servizio immagini gratuito e illimitato. Nessuna chiave API reale va inclusa nell'app o nel repository; un eventuale segreto deve stare lato servizio o in configurazione esclusa dal controllo versione.
- Anche le immagini del catalogo `free-exercise-db` richiedono cautela: il dataset e il codice dichiarano Unlicense, ma nel 2026 la discussione ufficiale del progetto ha sollevato dubbi specifici sulla provenienza delle immagini e il maintainer ha proposto di sostituirle con segnaposto. Non considerare quindi già risolti i diritti delle miniature remote; preferire illustrazioni originali/locali oppure una fonte con termini espliciti per i media.
- Funzioni ancora mancanti da progettare senza falsificare lo storico: tipo di serie (riscaldamento, allenante, superset, dropset, cedimento), ghost data visuale della seduta precedente, PR distinti per carico/volume/1RM, doppia progressione e riscaldamento proporzionale. I suggerimenti devono essere spiegabili e confermabili, non prescrizioni mediche né modifiche automatiche ai dati registrati.
- Il carosello Entrate e i tre grafici esistono già. Il requisito residuo è una verifica mirata su iPhone delle pagine, degli indicatori e del ritaglio; non duplicare il componente sulla base di una schermata precedente.

AI esterna (versione 8): valutare un servizio online oppure un server su computer/iPad. Nessun backend, account, costo o invio di dati personali è stato attivato nella serie 7. Per un server personale servono modello/hardware disponibili, connessione e disponibilità del dispositivo; non si presume che il computer possa restare sempre acceso.

Scenario obbligatorio per la V8: dopo «mi sono svegliato a mezzogiorno» e «iniziamo la giornata col pranzo, bisogna trovare un buco per la palestra», Pivot deve mantenere il contesto della conversazione, capire che la giornata reale è slittata, rileggere gli impegni ancora validi e proporre una sequenza concreta con conseguenze e conflitti. Non deve ripetere una risposta generica né richiedere di indicare manualmente un singolo evento quando l'intento è già chiaro. Le modifiche al Calendario restano comunque soggette a conferma.

Recuperare progressivamente con l’utente i restanti obiettivi personali, le abitudini, lo studio/esami e le funzionalità future. Questa nota non è un elenco completo della precedente conversazione.

## Verifica e installazione

I test core e i test di interazione sul simulatore sono nel workflow macOS. La 0.7.3 è pubblicata come prerelease insieme a una sorgente AltStore che dichiara HealthKit e HealthKit background delivery. La misura della fluidità reale e dell’AI richiede ancora l’iPhone 15. Prima dell’aggiornamento verificare/esportare il backup. Installare sopra Pivot esistente con lo stesso Apple ID, senza disinstallare: la cancellazione dell’app elimina la copia locale e il modello scaricato.
