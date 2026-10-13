# Serie 7 — finalizzazione funzionale

Stato aggiornato il 13 ottobre 2026. La V8 e ogni interpretazione AI restano fuori da questo lavoro.

## Regola di prodotto

Per ogni funzione chiedere:

1. Ha senso nell'uso reale?
2. Quale risultato finale produce?
3. L'interfaccia rende quel risultato evidente e raggiungibile?

Una funzione non è conclusa se legge dati o mostra controlli senza cambiare in modo comprensibile l'esperienza dell'utente.

## Calendario, agenda e diario

Comportamento presente:

- Pivot legge gli eventi da sette giorni prima a due mesi dopo, applica filtri, colori e classificazione.
- Aggiorna la lettura all'apertura, al ritorno in primo piano, agli eventi EventKit e con un controllo periodico mentre l'app è attiva.
- Usa gli eventi per Home, diario, conflitti, promemoria, riconoscimento delle ripetizioni e scadenze dei pagamenti.
- Prima di questo blocco scriveva nel Calendario soltanto dopo una conferma esplicita di una proposta o del riallineamento di un allenamento.

Problema reale:

- I promemoria vengono programmati fino a sette giorni prima. Una cancellazione arrivata dopo la programmazione può lasciare un avviso obsoleto se Pivot non riesce a riconciliare la coda prima dell'ora prevista.
- Il diario unisce gli eventi correnti alle fotografie conservate nei record. Una fotografia pendente di un evento poi cancellato può sopravvivere come se fosse un'attività reale.
- L'utente non vede chiaramente che cosa è cambiato dopo una sincronizzazione.

Esito da finalizzare:

- Il Calendario è la fonte del programma futuro.
- Un evento cancellato non deve più generare una domanda sull'esito.
- Un evento cancellato senza dati reali inseriti sparisce da agenda e diario; se contiene già dati reali, resta nello storico con indicazione “rimosso dal Calendario”.
- Spostamenti e modifiche devono riconciliare l'occorrenza esistente, senza duplicare il diario.
- Dopo ogni sincronizzazione la UI deve mostrare l'ultimo aggiornamento e, quando utile, un breve riepilogo delle variazioni.
- Le notifiche degli eventi vanno riconciliate su un orizzonte più corto e devono rimuovere anche gli avvisi obsoleti già consegnati quando l'app torna attiva.

Decisione chiusa il 12 ottobre: quando l'utente salva un'attività completata o parziale con inizio e fine reali validi, Pivot aggiorna automaticamente gli orari della sola occorrenza corrispondente nel Calendario. Non cambia titolo, note, calendario, ricorrenza o altri eventi. Un evento eliminato, modificato altrove o non scrivibile resta salvato localmente e produce un messaggio esplicito; nessun tentativo di riorganizzazione viene fatto senza AI. Gli allenamenti collegati applicano la stessa regola alla conclusione o al salvataggio finale.

Primo blocco completato e verificato nella CI 38340745732:

- scrittura deterministica degli orari reali sulla singola occorrenza;
- notifiche degli eventi limitate alle successive 36 ore e pulizia degli avvisi consegnati per occorrenze eliminate quando Pivot si aggiorna;
- rimozione dal diario delle fotografie ancora pendenti di eventi cancellati;
- conservazione dei record con dati reali, etichettati “Rimosso dal Calendario”.

La verifica completa ha superato 216 test Core, compilazione Release, confezionamento IPA e 18 test dell’interfaccia. Il precedente falso errore della tabella serie era causato da swipe di collaudo troppo ampi e alternati; ora il controllo porta la riga nel viewport con spostamenti brevi e deterministici.

## Salute

Comportamento presente:

- Integrazione in sola lettura.
- Legge sonno, allenamenti, energia attiva, distanza e frequenza cardiaca disponibili negli ultimi giorni.
- Collega automaticamente un allenamento Salute a un evento soltanto quando l'abbinamento è univoco e prudente.
- Può completare un evento cardio, applicare orari/durata reali e compilare il sonno del check-in.
- Gli allenamenti non abbinabili restano da confermare. Nascita, peso e altezza sono letti soltanto con un'importazione separata del profilo forza.

Problema reale:

- L'effetto dell'importazione è nascosto: l'utente vede il permesso, ma non un resoconto chiaro di quali dati siano stati usati e dove.
- Salute non modifica il Calendario e non riorganizza la giornata automaticamente.

Esito da finalizzare:

- Mostrare per ogni dato la provenienza “da Salute”, l'ora dell'ultima lettura e le modifiche applicate da Pivot.
- Presentare gli abbinamenti incerti come decisioni semplici, senza chat o AI.
- Non trasformare Salute in una fonte di prescrizioni mediche e non scrivere dati in HealthKit.

Secondo blocco completato e verificato nella CI 38379904044 (commit remoto 30c9816a):

- riepilogo di ogni lettura con quantità di allenamenti e notti lette, modifiche applicate e attività ancora da decidere;
- provenienza “Da Salute” visibile su sonno e allenamenti, con indicazione esplicita dell'uso fatto da Pivot;
- scelta dell'evento direttamente nella schermata Salute, senza passare dalla chat o dall'AI;
- aggiornamento degli orari della singola occorrenza nel Calendario soltanto dopo la conferma esplicita dell'utente; se il Calendario non è scrivibile, i dati Salute restano salvati in Pivot;
- nessuna scrittura nell'app Salute e nessuna interpretazione medica.

La verifica ha superato 218 test Core, compilazione Release, confezionamento IPA e tutti i 18 test UI. È stata corretta anche la direzione di scorrimento nel test della galleria dopo l'importazione: la galleria si trova sopra, non sotto, il pulsante di importazione. Permessi e lettura HealthKit sul vero iPhone restano da provare.

## Allenamento, recupero e Live Activity

Comportamento presente:

- Il recupero parte al completamento di una serie ed è visibile in una scheda collocata prima dell'elenco degli esercizi.
- La Live Activity può mostrare esercizio, valori, serie e recupero, ma richiede attivazione esplicita.

Problema reale:

- Negli ultimi esercizi bisogna scorrere fino all'inizio per vedere il recupero.
- I controlli più importanti non seguono l'utente e il percorso per attivare la schermata di blocco non è evidente.

Esito da finalizzare:

- Barra di recupero compatta e persistente nell'app, sempre visibile sopra la barra inferiore durante un allenamento.
- Countdown grande, esercizio corrente, prossima serie e target; pausa, reset e “prossima serie” raggiungibili senza scorrere.
- Live Activity minimale con caratteri e aree di tocco più grandi; avvio automatico quando comincia l'allenamento, se autorizzato.

Terzo blocco implementato, verifica macOS/simulatore da concludere:

- barra fissata nell'area sicura, non nell'elenco: countdown, esercizio del recupero, pausa/reset e passaggio alla prossima serie;
- stessa scelta della prossima serie in app e Live Activity; dall'ultimo esercizio si continua localmente prima di tornare a serie precedenti rimaste incomplete;
- anche l'ultimo recupero resta visibile, con “Chiudi recupero” anziché una serie successiva inventata;
- conservazione del recupero effettivo quando si conferma direttamente una nuova serie; modificare lo storico concluso non avvia un nuovo timer;
- Live Activity automatica all'avvio e pulsante di ripristino; controlli 44 punti, layout distinto per lavoro e recupero; nelle isometrie bilaterali i controlli sono dedicati ai due lati, la zavorra è visibile e modificabile nell'app;
- sei test Core aggiunti e due test UI nuovi: ottavo esercizio/ultima serie/persistenza e altezza/aree di tocco del layout Live Activity condiviso.

Il layout condiviso segue il limite di altezza di 160 punti indicato nella [documentazione Apple](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities). Il simulatore non dimostra l'avvio né il comportamento in background sul blocco schermo reale.

## Chiusura ed esportazione

Comportamento presente:

- “Termina allenamento”, “Salva allenamento” ed “Esporta per il personal” sono tre azioni separate.

Problema reale:

- Non è chiaro quale pulsante concluda davvero il flusso. Il salvataggio non imposta la fine e il termine non apre il PDF.

Esito consigliato:

- Un'unica azione primaria “Termina allenamento”.
- Imposta l'ora di fine, chiude il recupero e la Live Activity, salva, ricalcola risultati e genera il PDF.
- Il PDF resta conservato nello storico Pivot e viene aperto subito in anteprima, da cui condividerlo o salvarlo in File.

Decisione aperta: confermare se l'anteprima automatica con copia interna soddisfa “esporta automaticamente”, oppure se scegliere una cartella File permanente per i salvataggi successivi.

## Cronologia delle giornate della scheda

Comportamento presente:

- Esiste un elenco globale degli ultimi allenamenti e una cronologia per singolo esercizio.
- Non esiste una cronologia dedicata alla giornata Squat/Bench/Deadlift con modifica ed eliminazione esplicite.

Esito da finalizzare:

- Dentro ogni giornata della scheda mostrare le relative sessioni, distinguendo in corso e terminate.
- Permettere la correzione di orari, serie, carichi, ripetizioni, durata e note.
- Permettere di eliminare un avvio accidentale; chiedere conferma rafforzata se esistono serie svolte.
- Dopo modifica o eliminazione ricalcolare progressi, PR e rank per non lasciare risultati derivati incoerenti.
- Le revisioni della scheda e le sessioni svolte restano concetti separati.

## Progressione, fase e problematiche fisiche

Blocco successivo, dopo la chiusura dei punti precedenti:

- Consiglio di progressione nella scheda dell'esercizio basato sul rep range e sul lavoro realmente svolto.
- Valutazione dello storico complessivo, mai dei valori precompilati o delle serie non confermate.
- Fase della programmazione per scheda/giornata: carico, scarico, recupero/rientro.
- Sezione problematiche/infortuni con zona interessata e comportamento conservativo sui movimenti coinvolti.
- Nessuna interpretazione clinica o AI in Serie 7.

## Rank e verifica

- L'email “Pivot - ranked” dell'8 ottobre contiene soltanto quattro immagini assegnate ai rank 1 e 2. Non risultano asset o nomi per i rank 3–7.
- Nell'ultima CI i popup PR e rank sono passati.
- Il test della galleria dopo l'importazione è ora passato nella CI 38379904044; nessun fallimento UI residuo nel checkpoint Salute. Il nuovo blocco recupero richiede una nuova verifica completa e il collaudo sul vero iPhone.
