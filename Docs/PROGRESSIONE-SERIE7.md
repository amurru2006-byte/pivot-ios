# Progressione e problematiche fisiche — confini del prossimo blocco

Decisioni dirette del 13 ottobre 2026. Segnalazioni implementate, verifica completa ancora in corso. Sottoblocco fasi preparato localmente con test; non ancora trasferito al collaudo. Lettura della progressione/rep range ancora da implementare.

Ultimo esito segnalazioni: CI 38444835357 con 255 Core passati, app e packaging compilati; 23 dei 26 UI passati. Riparazione in preparazione per tastiera del modulo (Fine esplicito e controllo chiusura) e apertura della cronologia (route stabile). Prima confermare questa riparazione isolata, poi trasferire le fasi; nessun esito UI positivo ancora dichiarato. Dettagli in SERIE7-VERIFICA.md.

## Risultato utile in Serie 7

- Fase dichiarata della scheda/giornata: carico, scarico, recupero/rientro. Una fase non diventa una prescrizione automatica in percentuali.
- Andamento da serie davvero svolte, con target originale e contesto confrontabile: stesso esercizio/variante, tipo di serie, carico e ripetizioni. Valori precompilati, warm-up e serie saltate non dimostrano miglioramento.
- Distinguere obiettivo di ripetizioni raggiunto da sicurezza o opportunità dell'aumento. Nessuna crescita prevista di 10 kg/settimana: l'utente lo ha fornito solo come esempio e il PT non ha dato regole.
- Problematiche fisiche riferite dall'utente: zona/lato, movimenti coinvolti, andamento dei sintomi e eventuali indicazioni professionali. Non convertire descrizioni o ipotesi personali in diagnosi confermate.
- Una problematica può essere collegata a più esercizi; lo storico non è isolato alla sola riga dello squat. L'app esplicita la provenienza dei collegamenti e permette di correggerli.
- Avvisi contestuali e rivalutazione: registrazione e modifiche manuali rimangono disponibili. La scelta iniziale "Mostra soltanto un avviso" è stata ritirata dall'utente; non trattarla come decisione finale né sostituirla con un blocco indiscriminato.
- Eventuali obiettivi collegati tra esercizi possono essere registrati come parte di un percorso concordato, indicando chi li ha stabiliti. Un risultato numerico raggiunto non autorizza automaticamente il ritorno a un altro movimento.

## Cosa non viene dedotto

- Nessuna diagnosi da trend dei carichi, gonfiore, dolore o dalla presenza di una gomitiera.
- Nessun incremento riabilitativo standard o riduzione "prudente" inventata: non c'è ancora un protocollo professionale.
- "40 kg di pressa prima dello squat" e il successivo esempio della leg extension monolaterale sono collegamenti ipotetici, non soglie cliniche ricevute né test di idoneità da codificare. Non dedurre che una variante sia adatta alla riabilitazione personale soltanto dal suo nome.
- Il rank motivazionale e il massimale stimato non sono un permesso di aumentare il carico o rientrare dopo un infortunio.

## Serie 8

L'AI potrà aiutare a spiegare lo storico, raccogliere il contesto e presentare un percorso concordato. Non risolve da sola l'assenza di valutazione e criteri validati, né conferma la sicurezza del rientro da un infortunio. AI e Serie 8 restano in pausa.

## Segnalazioni: primo sottoblocco implementato

- Menu ⋯ dell'esercizio: “Segnala dolore” e “Segnala infortunio”, oltre alle azioni già presenti. Area di tocco di 44 punti.
- Zona obbligatoria, lato, data, intensità facoltativa, note, indicazioni professionali riferite e loro provenienza. Nessuna descrizione personale viene precompilata nel codice.
- Un'unica segnalazione può collegare più esercizi scelti esplicitamente. L'avviso vale anche per la stessa variante di catalogo in altre schede, non per esercizi dedotti dalla zona anatomica. Cambiare variante non trasferisce automaticamente l'avviso.
- Avviso persistente sulla riga degli esercizi collegati, apribile per correggere il contesto. Più segnalazioni sono accessibili dall'elenco completo; niente modifiche automatiche di carichi, scheda, rank o allenamenti.
- Sezione “Dolori e infortuni” in Palestra, anche senza allenamento in corso. Una segnalazione non avvia una sessione. Eliminare la sessione d'origine non elimina il contesto fisico.
- “Non più presente” conserva lo storico e rimuove gli avvisi; riattivazione possibile. Non equivale a un via libera clinico. Nessun archivio automatico in base al tempo trascorso.
- Persistenza nello stesso archivio/backup personale protetto; campo opzionale per i vecchi backup. Escluso dai report PT e dal contesto inviato automaticamente al Coach. Un errore di disco resta esplicito con possibilità di riprova, e un editor obsoleto non sovrascrive una versione più recente.
- Aggiunti 13 test Core e due flussi UI sintetici per collegamenti, compatibilità, validazione, conflitti, isolamento dagli allenamenti, annullamento, storico, riattivazione e persistenza. Esito ancora da verificare, non una funzione già distribuita sul telefono.

## Fasi: secondo sottoblocco preparato localmente

- “Fase della scheda” nell'editor: non dichiarata, carico, scarico, recupero/rientro. Ogni giornata può usare quella della scheda o una propria fase esplicita.
- Ogni nuova sessione conserva una copia del contesto della giornata/scheda. Modificare o ripristinare la scheda non riscrive le sessioni esistenti, anche se ancora in corso.
- “Fase di questo allenamento” permette una correzione esplicita della singola sessione, con autosalvataggio dopo l'avvio; prima dell'avvio non crea un allenamento soltanto per aver scelto una fase.
- Fase visibile nella scheda/giornata, nella cronologia della giornata, nelle versioni della scheda, nella cronologia recente dell'esercizio e nei report PT PDF/testo. Il report usa la fase salvata nella sessione, non quella della scheda attuale; non include automaticamente le segnalazioni fisiche. Le metriche restano quelle effettivamente registrate, non corrette per percentuali inventate.
- Vecchie sessioni: fase non dichiarata, senza inferire il passato dalla scheda attuale. Campi opzionali compatibili con backup e payload delle schede già esistenti.
- Non modifica carichi, serie, ripetizioni, stato dolore, PR/rank o Calendario. I valori precompilati restano l'ultimo dato registrato, non una nuova prescrizione di scarico o rientro. Il nome di una fase non autorizza un aumento né rimuove gli avvisi.
- Quindici nuovi test Core e un flusso UI sintetico, con screenshot editor/storico: eredità/override, snapshot, backup legacy, revisioni/ripristino, assenza di modifica dei carichi, finalizzazione, sostituzione, avvisi indipendenti, conservazione delle metriche ed esportazione del solo contesto dichiarato. Il flusso UI prova cambi manuali prima/dopo l'avvio, senza un avvio implicito. Fixture PDF ampliata per due fasi differenti e protezione delle segnalazioni private; stress di paginazione invariato con le tre fasi. Ancora da compilare/eseguire e ispezionare visivamente su macOS.
- Non trasferire il blocco mentre il collaudo segnalazioni è in corso: un nuovo push sul ramo annullerebbe la verifica precedente. Dopo il suo esito, trasferire e collaudare separatamente le fasi.

## Riferimenti e privacy

La guida ortopedica [AAOS, Knee Conditioning Program](https://www.orthoinfo.org/recovery/knee-conditioning-program/) richiede supervisione e selezione individuale degli esercizi con medico/fisioterapista: non viene trasformata in un protocollo personale o in conversioni tra macchine e bilanciere.

Sintomi e dati sanitari personali non sono inseriti nel repository o nelle fixture pubblicabili. Test sintetici e persistenza compatibile con backup esistenti. Restano da finalizzare i criteri non clinici della progressione e le fasi; nessun obiettivo riabilitativo tra esercizi viene inventato.
