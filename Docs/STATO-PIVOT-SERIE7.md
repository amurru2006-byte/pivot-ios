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

Da completare: concludere la verifica combinata dopo le correzioni UI; progressione/fasi/problematiche fisiche conservative; acquisire gli asset rank 3–7 mancanti; collaudare widget/Live Activity sul vero iPhone. Screenshot/PDF personali restano fuori dal repository. Nessuna nuova release stabile pubblicata.
