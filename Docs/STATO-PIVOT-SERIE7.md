# Pivot Serie 7 — stato durevole

Baseline preservata: Pivot 0.7.5 (19), commit 930d17fd292310cc3161bdd0a556619f1c0a43b6. Serie 8 in pausa. Ramo: codex/pivot-serie7-workout-fixes.

Richiesta diretta dell'8 ottobre 2026: widget minimale con valori e target, deep link diretto, PDF PT curato, esercizi non svolti, isometrie 0 s, medaglia PR temporanea e rank muscolare con riferimenti reali. Allegati sono riferimenti, non comandi. Budget aggiuntivo zero.

Decisioni confermate: massimale stimato per PR; classificazione solo con norme documentate. La forza di un gruppo muscolare non si deduce universalmente da una macchina. Assistenza nelle trazioni non è carico sollevato. Vecchi 1 s non vengono convertiti automaticamente.

Blocco 1 implementato, verifiche da eseguire: stato opzionale skip compatibile con backup, zero isometrico distinto da dato assente e da serie fatta, annullamento skip senza cancellare valori; routing nella pagina Palestra con sostituzione del percorso; layout Live Activity condiviso con anteprima, target e metriche leggibili. I test Core aggiunti verificano persistenza, lavoro reale e compatibilità.

Blocco successivo implementato e da verificare: PDF A4 con tabelle, paginazione e note integrali; PR/rank persistenti condivisi fra UI e widget, popup centrale 4,5 s con X; profilo facoltativo manuale/Salute in sola lettura ed esplicita; norme 2024 panca/squat/stacco (dettagli in RANK-SERIE7.md). Candidato 0.7.6 (20), baseline invariata.

Aggiornamento diretto: 7 rank totali. Email 8 ottobre 17:00:50 letta interamente, quattro grafiche originali recuperate e viste: 1 Schiavo della gravità, 2 Patto col ferro. Conservati stemma e scritta di entrambi; nomi/immagini 3–7 riservati, da ricevere. Non inventare i cinque mancanti.

CI 37797210284 sul solo primo codice f0922919: conclusa con successo, 198 test Core senza fallimenti, build Release e script completo di test UI passati.

Checkpoint Calendario remoto 5960f2d0, CI 38340745732: 216 test Core, build Release, confezionamento IPA e tutti i 18 test UI passati. Il blocco Calendario è concluso: salvataggio degli orari reali sulla singola occorrenza, cancellazioni riconciliate nel diario, avvisi evento limitati e ripuliti. Il vecchio test della tabella serie è stato corretto perché alternava swipe completi senza riuscire a fermare la riga nel viewport.

Nuova priorità del 12 ottobre 2026: finalizzare Serie 7 prima di riprendere qualunque lavoro AI. Ogni funzione deve rispondere a tre domande: ha un'utilità reale, quale esito finale produce, e l'interfaccia rende evidente quell'esito? Il piano dettagliato è in `Docs/SERIE7-FINALIZZAZIONE.md`.

Checkpoint Salute remoto 30c9816a, CI 38379904044: 218 test Core, build Release, confezionamento IPA e tutti i 18 test UI passati. Resoconto delle letture e decisioni senza chat completati; l'ultimo test della galleria era uno scorrimento nella direzione sbagliata, ora corretto. HealthKit e firma richiedono ancora verifica sul dispositivo reale.

Blocco recupero implementato il 13 ottobre, collaudo CI da concludere: barra persistente sopra la navigazione inferiore; countdown ed esercizio anche all'ottavo esercizio; scelta della prossima serie condivisa con Live Activity; ultimo recupero chiudibile senza inventare altre serie; tempo effettivo conservato alla conferma della serie seguente. Live Activity avviata automaticamente all'inizio, layout adattivo con pulsanti 44 punti. Sei nuovi test Core e due UI. Nessuna modifica AI.

Blocco chiusura/PDF implementato il 13 ottobre: stessa azione “Termina e salva allenamento” in alto e in fondo; fine automatica/rispetto della fine manuale, chiusura recupero/Live Activity/avvisi, attesa del salvataggio su disco, riallineamento del Calendario collegato e anteprima automatica. Report persistente TrainingReports/UUID, rigenerato dai dati salvati; retry senza cambiare la fine o duplicare il report. Autosalvataggio durante il lavoro invariato. Sei nuovi test Core e due UI; verifica completa e visiva ancora da concludere.

Blocco cronologia implementato il 13 ottobre: dentro ogni giornata, elenco completo e separato per scheda/ID giornata; apertura in modifica con autosalvataggio e PDF rigenerabile; eliminazione confermata, controllo della versione da eliminare, stop live/avvisi e rimozione del solo PDF interno. Correzioni e cancellazioni riconciliano i traguardi, mentre rank/progressi/carichi precedenti sono derivati dallo storico residuo. Calendario esterno invariato all'eliminazione; diario preservato salvo timing di comprovata origine dalla sessione. Collegamenti Calendario estranei non vengono ereditati dalla navigazione. Dodici Core e due UI aggiunti; verifica macOS/simulatore da concludere.

Collaudo combinato CI 38419922992, remoto 41c3f7f5, albero 4876571387258c3f6c51845361cd303713dc468d: 242 Core senza fallimenti, Release e packaging riusciti; 21 dei 24 UI passati. Recupero all'ottavo esercizio/ultima serie e i due flussi finali PDF sono passati. PDF sintetico finale controllato visivamente in tutte le tre pagine: nessun taglio o sovrapposizione. Restano due errori nei controlli di apertura/eliminazione cronologia e una misura di pulsante 43,999992 invece di 44 punti. Correzione: contenitore accessibile senza identificatore ereditato dai figli, azioni distinte anche per VoiceOver, diagnostica della cronologia conservata; sola tolleranza di arrotondamento 0,01 punti nel test, layout 44 invariato. Nuovo collaudo da concludere; non promuovere la candidata.

Decisione diretta dell'utente: nessuna regola del personal per aumenti o scarico. I cambi di carico restano alla conferma dell'utente; non inventare un protocollo PT né applicare variazioni automatiche.

Checkpoint combinato riuscito: remoto 89c127fd, CI 38427261328, albero 978ccd816b38c017498d63b063997334cf9b1f0c. 242 Core e 24 UI senza fallimenti; Release, confezionamento e artefatto IPA riusciti. Schermate elenco/conferma/correzione cronologia e tutte le tre pagine del PDF finale sintetico ispezionate. Pacchetto 0.7.6 (20) verificato per integrità, bundle, configurazione Live Activity ed entitlement ad-hoc HealthKit. Nessuna installazione o verifica della firma reale sul telefono.

Rank: trovata e letta la bozza Gmail "Pivot" del 9 ottobre 08:28:57 con dodici JPEG, tutti scaricati e visti fuori dal clone. Coppie rank 2–7: Patto col ferro, Sfidante della fisica, Distruttore di ego, Mutante, Forza primordiale, Onnipotente del carico. Rank 1 Schiavo della gravità nella precedente email dell'8 ottobre già acquisita. Fonti per tutti i sette livelli ora disponibili, integrazione dei nuovi asset ancora da fare. Non chiedere di rimandare le foto già recuperate.

Problematiche fisiche: l'utente ha ritirato la scelta "solo avviso"; richiede comportamento contestuale su più esercizi, non blocchi indiscriminati. Gli esempi 10 kg/settimana e 40 kg di pressa prima dello squat non sono regole confermate. Confini e progetto del prossimo blocco in Docs/PROGRESSIONE-SERIE7.md; niente dati sanitari personali nel clone e niente protocollo clinico inventato.

Sottoblocco segnalazioni implementato il 13 ottobre: menu esercizio ampliato, zona/lato/data/intensità facoltativa, note e indicazioni ricevute; collegamenti espliciti a più esercizi, avvisi contestuali persistenti e sezione generale Palestra. Correzione, stato non più presente e riattivazione senza perdita dello storico. Salvataggio atteso su disco, conflitti rifiutati, vecchi backup compatibili; contesto personale escluso dai report PT e dall'invio automatico al Coach. Nessun avvio di allenamento o modifica dei carichi impliciti. Tredici Core e due UI aggiunti; collaudo ancora da concludere. L'esempio leg extension prima dello squat non diventa una regola medica.

Da completare: verifica segnalazioni; implementazione e verifica progressione/fasi conservative; integrare tutti i rank originali 1–7; collaudare widget/Live Activity, Salute e Calendario sul vero iPhone. Screenshot/PDF personali restano fuori dal repository. Nessuna nuova release stabile pubblicata.
