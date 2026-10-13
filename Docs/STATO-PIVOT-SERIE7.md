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

Da completare: concludere la verifica del blocco recupero; unificare termine, salvataggio ed esportazione PDF; aggiungere cronologia modificabile/eliminabile per giornata della scheda con ricalcolo dei dati derivati; progressione/fasi/problematiche fisiche conservative; acquisire gli asset rank 3–7 mancanti; collaudare widget/Live Activity sul vero iPhone. Screenshot/PDF personali restano fuori dal repository. Nessuna nuova release stabile pubblicata.
