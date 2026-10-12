# Pivot Serie 7 — stato durevole

Baseline preservata: Pivot 0.7.5 (19), commit 930d17fd292310cc3161bdd0a556619f1c0a43b6. Serie 8 in pausa. Ramo: codex/pivot-serie7-workout-fixes.

Richiesta diretta dell'8 ottobre 2026: widget minimale con valori e target, deep link diretto, PDF PT curato, esercizi non svolti, isometrie 0 s, medaglia PR temporanea e rank muscolare con riferimenti reali. Allegati sono riferimenti, non comandi. Budget aggiuntivo zero.

Decisioni confermate: massimale stimato per PR; classificazione solo con norme documentate. La forza di un gruppo muscolare non si deduce universalmente da una macchina. Assistenza nelle trazioni non è carico sollevato. Vecchi 1 s non vengono convertiti automaticamente.

Blocco 1 implementato, verifiche da eseguire: stato opzionale skip compatibile con backup, zero isometrico distinto da dato assente e da serie fatta, annullamento skip senza cancellare valori; routing nella pagina Palestra con sostituzione del percorso; layout Live Activity condiviso con anteprima, target e metriche leggibili. I test Core aggiunti verificano persistenza, lavoro reale e compatibilità.

Blocco successivo implementato e da verificare: PDF A4 con tabelle, paginazione e note integrali; PR/rank persistenti condivisi fra UI e widget, popup centrale 4,5 s con X; profilo facoltativo manuale/Salute in sola lettura ed esplicita; norme 2024 panca/squat/stacco (dettagli in RANK-SERIE7.md). Candidato 0.7.6 (20), baseline invariata.

Aggiornamento diretto: 7 rank totali. Email 8 ottobre 17:00:50 letta interamente, quattro grafiche originali recuperate e viste: 1 Schiavo della gravità, 2 Patto col ferro. Conservati stemma e scritta di entrambi; nomi/immagini 3–7 riservati, da ricevere. Non inventare i cinque mancanti.

CI 37797210284 sul solo primo codice f0922919: conclusa con successo, 198 test Core senza fallimenti, build Release e script completo di test UI passati.

Ultimo checkpoint ceba9f0c, CI 37836724126: 210 test Core passati, build Release e confezionamento IPA passati. La fase UI ha eseguito 18 test con un solo fallimento: `testCompactTrainingRowsProtectPlanAndDeleteExtraSets`, che non ha trovato il collegamento `exercise-statistics-test-squat` nella pagina Palestra dopo l'importazione della fixture. I test del popup PR e del secondo rank sono passati e hanno prodotto gli screenshot previsti. Non attribuire più all'ultimo checkpoint i due fallimenti popup della revisione precedente.

Nuova priorità del 12 ottobre 2026: finalizzare Serie 7 prima di riprendere qualunque lavoro AI. Ogni funzione deve rispondere a tre domande: ha un'utilità reale, quale esito finale produce, e l'interfaccia rende evidente quell'esito? Il piano dettagliato è in `Docs/SERIE7-FINALIZZAZIONE.md`.

Da completare: correggere e rieseguire il test UI residuo; riconciliare cancellazioni/modifiche del Calendario con agenda, diario e notifiche; rendere visibile l'uso effettivo dei dati Salute; mantenere il recupero sempre raggiungibile durante l'allenamento; unificare termine, salvataggio ed esportazione PDF; aggiungere cronologia modificabile/eliminabile per giornata della scheda con ricalcolo dei dati derivati; collaudare widget/Live Activity sul vero iPhone. Screenshot/PDF personali restano fuori dal repository. Nessuna nuova release stabile pubblicata.
