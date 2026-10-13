# Verifica Serie 7

Baseline 0.7.5 preservata. Commit del primo blocco: f0922919bd80df787c94e67ec8a4f0005e423ca5. Correzione percorso artefatti: 3a70c2059a91ab1aa80a5bffbe280cd277d634bd.

CI del primo blocco 37797210284: riuscita, 198 Core e 15 UI senza fallimenti.

CI intermedia 37831664233 sul commit 55a94b2c: 210 Core, build Release e packaging passati; 18 UI con due fallimenti nei test popup PR/rank.

CI finale osservata 37836724126 sul commit ceba9f0c: 210 Core, build Release e packaging passati; 18 UI con un solo fallimento. I test popup PR e rank sono passati. Il fallimento effettivo è `testCompactTrainingRowsProtectPlanAndDeleteExtraSets` alla riga 122: dopo l'importazione della scheda di prova non viene trovato `exercise-statistics-test-squat` nella pagina Palestra. Artefatti recuperati e verificati il 12 ottobre 2026; log e anteprime sono conservati fuori dal clone in `../qa/serie7-ci/ceba9f0c/`.

Checkpoint Calendario, CI 38340745732: 216 Core, build Release, confezionamento IPA e tutti i 18 UI passati.

Checkpoint Salute, CI 38379904044, commit remoto 30c9816ac759a30e4f38ccca38cb3e88311c4f18, albero 5e3ce36cca4a39e67fdac881c2650f025fcf0934: 218 Core, build Release, confezionamento IPA e tutti i 18 UI passati. Il residuo del test galleria è chiuso; gli swipe dopo l'importazione ora tornano verso la galleria, che si trova sopra il controllo di importazione.

13 ottobre: aggiunti sei test Core per contesto serie/recupero e conservazione del tempo effettivo, un test UI per recupero all'ottavo esercizio/ultima serie/persistenza e un test UI per altezza e pulsanti della Live Activity condivisa. Verifica completa del nuovo blocco da concludere.

Nessuna release stabile sostituita. La candidata 0.7.6 (20) richiede ancora il collaudo hardware prima di essere promossa.

Blocco chiusura/PDF del 13 ottobre: aggiunti sei test Core per fine automatica/manuale, idempotenza, orari invalidi, nessuna serie inventata e identità del report. Due flussi UI nuovi controllano chiusura dal fondo, anteprima automatica, file persistente da dati salvati, riapertura/fine invariata e riprova dopo un errore PDF sintetico (solo Debug simulatore). Il test importazione/salvataggio ora richiede l'anteprima e il comando di condivisione. Il PDF sintetico finale viene conservato negli artefatti del collaudo. Esito completo da verificare.

Blocco cronologia del 13 ottobre: dodici test Core e due UI aggiunti. Verificano appartenenza planID/dayID, legacy e revisioni senza ambiguità, oltre 20 sessioni, eliminazioni atomiche e conferme obsolete, conservazione del diario/Calendario, riconciliazione di PR/rank, progressi e carichi successivi. I flussi UI controllano correzione di una sessione terminata senza recupero, Annulla, conferma con serie svolte, rimozione degli avvii vuoti e persistenza dopo riavvio. Test Debug isolati, nessuno storico personale. Esito completo da verificare.

Collaudo combinato 38419922992 (41c3f7f5, albero 4876571387258c3f6c51845361cd303713dc468d): 242 Core, zero fallimenti; Release e packaging riusciti. 24 UI eseguiti, 3 fallimenti: pulsanti `history-open`/`history-delete` non trovati e altezza 43,999992 contro 44 nel layout Live Activity. Nessun artefatto IPA candidato caricato a causa degli UI falliti. Recupero e finalizzazione/PDF, compreso errore e riprova, passati. Artefatti in `../qa/serie7-ci/history-41c3f7f5/`; PDF finale sintetico di tre pagine ispezionato visivamente senza tagli/sovrapposizioni. Screenshot del recupero conferma barra visibile dal fondo.

Correzione in attesa di nuovo collaudo: rimosso l'identificatore del contenitore cronologia per non propagare un ID alle azioni; contenimento accessibile e descrizioni delle azioni con data/ora. Aggiunte schermata e gerarchia accessibile all'apertura della cronologia, con manifest degli allegati conservato dalla CI. Il test delle dimensioni ammette solo arrotondamento di 0,01 punti, senza modificare le aree di tocco reali da 44 punti. Non dichiarare il collaudo concluso prima dell'esito.

Riparazione verificata: CI 38427261328, remoto 89c127fd, locale 98c60927, albero 978ccd816b38c017498d63b063997334cf9b1f0c. Esito riuscito: 242 Core e 24 UI senza fallimenti, Release, packaging e caricamento IPA. Artefatti in ../qa/serie7-ci/history-89c127fd; hash ZIP e IPA conservati nel checkpoint esterno. Verifica read-only del pacchetto riuscita: CRC, bundle app/widget, 0.7.6 (20), configurazione Live Activity e risorse firma/entitlement HealthKit ad-hoc. Schermate cronologia elenco/conferma/correzione e PDF finale sintetico di tre pagine ispezionati senza tagli/sovrapposizioni. Questo chiude la verifica simulatore dei blocchi recupero, chiusura/PDF e cronologia, non quella hardware né la promozione a baseline.

Segnalazioni del 13 ottobre: aggiunti 13 Core per backup vecchi/nuovi, valori invalidi, identità e variante, più movimenti, assenza di deduzioni anatomiche, risoluzione/riattivazione, scritture atomiche e conflitti, indipendenza da allenamenti eliminati ed esclusione dai report. Due UI nuovi aprono il menu esercizio, annullano o salvano dolore/infortunio riferito, collegano due movimenti, verificano avvisi, storico e riavvio. La fixture conferma che non sia stato avviato un allenamento e che scheda/traguardi non siano cambiati. Dati sintetici in archivio Debug isolato; screenshot conservati per il controllo visivo. Windows senza Swift/Xcode: controlli locali statici, verifica macOS/simulatore ancora da concludere.

Prima CI segnalazioni 38444209752, remoto 84442726: Core compilato, 255 test eseguiti, un fallimento in testOldBackupWithoutConcernsStillDecodes. La fixture usava updatedAt = Date() con frazioni di secondo, mentre BackupCodec usa ISO 8601 a secondi interi: il confronto dell'intera sessione differiva soltanto nella precisione della data. Impostato updatedAt al clock fisso sintetico, conservando l'asserzione completa. Nessun cambiamento al codec o ai dati reali. Release/UI non eseguiti perché il primo step è fallito; nuovo collaudo necessario.
