# Serie 7 - finalizzazione funzionale

Stato conclusivo del 14 ottobre 2026. La regola di prodotto applicata a ogni blocco è: **ha senso nell'uso reale, quale fine produce e l'interfaccia rende evidente quell'esito?** Serie 8 e ogni interpretazione AI restano fuori da questo lavoro.

## Calendario, agenda e diario

Il Calendario è la fonte del programma futuro. Pivot aggiorna la lettura all'apertura, in primo piano e su cambiamenti EventKit. Un evento futuro eliminato non deve più generare la domanda su come sia andato: le fotografie ancora pendenti vengono rimosse. Se l'utente aveva già inserito dati reali, il record resta nello storico con Rimosso dal Calendario.

Quando si salva un'attività completata o parziale con inizio/fine reali validi, Pivot aggiorna automaticamente gli orari della sola occorrenza collegata. Non cambia titolo, note, calendario, ricorrenza o altri eventi. Evento mancante/non scrivibile e problemi EventKit non cancellano il dato locale. Gli avvisi vengono programmati su 36 ore e riconciliati quando l'app torna attiva; iOS non garantisce che Pivot possa intervenire se non viene riattivato in background.

Esito: il calendario non viene soltanto letto; modifica l'agenda e viene a sua volta riallineato dai dati reali confermati, entro confini deterministici. Verificato nei test Core/UI; singola occorrenza e notifiche vanno provate sul telefono.

## Salute

HealthKit resta in sola lettura. Pivot mostra ultima lettura, conteggi, provenienza e modifiche applicate a sonno/allenamenti/cardio. Un abbinamento incerto richiede una scelta semplice, senza chat o AI. Gli orari vengono scritti nell'occorrenza Calendario soltanto dopo conferma esplicita; un Calendario non scrivibile non perde i dati Salute.

Esito: il permesso produce un resoconto comprensibile e dati applicabili, non una raccolta invisibile. Nessuna diagnosi o scrittura nell'app Salute. La rifirma AltStore e i dati reali devono essere verificati sull'iPhone.

## Allenamento, recupero e Live Activity

La barra di recupero è fissata sopra la navigazione inferiore durante la sessione. Mostra countdown grande, esercizio, prossima serie e target, con pausa, reset e avanzamento; resta raggiungibile al Cable Crunch/ottavo esercizio e sull'ultima serie. Chiudi recupero evita una serie fantasma. La conferma diretta della serie successiva conserva il tempo effettivo precedente.

La Live Activity usa lo stesso contesto e si avvia automaticamente quando autorizzata. Pesi, ripetizioni, isometrie bilaterali e recupero hanno aree di tocco da almeno 44 punti. Il deep link riapre la pagina stabile dell'allenamento senza sheet duplicata.

Esito: non serve più scorrere in cima o spegnere il telefono per conoscere il recupero. Simulatore e layout condiviso verificati; ActivityKit reale resta hardware.

## Chiusura, salvataggio e PDF

Un unico pulsante Termina e salva allenamento appare in alto e in fondo. Registra una fine automatica valida o conserva quella manuale, ferma recupero/Live Activity/avvisi, attende il disco, riallinea il Calendario e genera il PDF dai dati salvati. Il report resta in Application Support/TrainingReports con UUID stabile e si apre automaticamente. Salva modifiche e apri PDF rigenera senza duplicare né spostare la fine.

Se il disco fallisce, il flusso non finge di aver concluso. Se falliscono solo PDF o Calendario, la sessione salvata resta e l'errore è riprovabile. Esito: chiusura ed esportazione non sono più tre comandi ambigui.

## Cronologia della giornata

Ogni giornata Squat/Bench/Deadlift ha il proprio elenco completo, identificato da piano/giornata e non dagli esercizi condivisi. Sessioni in corso e terminate possono essere aperte; correzioni valide si autosalvano senza recupero o traguardi retroattivi. L'editor mantiene l'ultima copia valida durante input transitori incompleti.

L'eliminazione richiede conferma e avvisa quando esistono serie svolte. Operazioni obsolete vengono rifiutate. PR, rank, grafici e prossimo carico derivano dallo storico residuo. L'evento Calendario esterno non viene cancellato; diario manuale, dati Salute e note non originati dalla sessione restano; viene pulito solo il PDF interno derivato.

Esito: un avvio accidentale può essere eliminato e un errore corretto, senza confondere schede o corrompere risultati derivati.

## Problematiche, fasi e progressione

Il menu ⋯ include Segnala dolore e Segnala infortunio. L'utente registra il proprio contesto, collega esplicitamente più movimenti e mantiene avvisi, storico, risoluzione e riattivazione. Pivot dichiara che è una segnalazione, non una diagnosi. Nessun blocco indiscriminato o cambio di carico.

Scheda e giornata possono dichiarare Carico, Scarico o Recupero/rientro. La sessione conserva lo snapshot e lo mostra in storico/PDF. Nessuna fase applica percentuali o riscrive il passato.

Obiettivo e andamento legge il rep range numerico e le serie davvero confermate. Confronta soltanto sessioni concluse equivalenti e conserva target/fase originali. Un limite raggiunto non elimina gli avvisi e non autorizza un aumento. Gli esempi 10 kg/settimana, 40 kg pressa o leg extension prima dello squat non sono regole.

Esito: Serie 7 raccoglie il contesto e rende leggibili dati comparabili; decisioni cliniche o consigli AI contestuali restano fuori.

## Rank

La galleria contiene tutti i livelli 1-7: Schiavo della gravità, Patto col ferro, Sfidante della fisica, Distruttore di ego, Mutante, Forza primordiale e Onnipotente del carico. Ogni stemma e titolo originale è apribile intero, con nome accessibile. Asset copiati byte per byte dalle fonti ricevute, senza generazione o ritaglio. Soglie e PR restano invariati; il popup dura 8 secondi ed è chiudibile.

Esito: non restano slot vuoti 3-7 e le grafiche ricevute hanno una destinazione chiara nell'interfaccia.

## Verifica e consegna

Run finale 38548362555, tentativo 2, sorgente `5e319695607503b808a9854abcf0b62875818ad4`: 303 Core e 28 UI passati, build Release e IPA riuscite. Tutte le schermate chiave e sette pagine PDF reali sono state esaminate. IPA 0.7.6 (20) SHA256 `55E40F57BDDAC02CD4FEDBCA16F764359E35CCFE6D6794FA8102FCF03A9BAE6A`.

La baseline 0.7.5 (19) non è stata sostituita. La candidata va prima installata sopra l'app esistente, dopo un backup, e provata sull'iPhone per conservazione dati, rifirma HealthKit, Calendario e Live Activity. Nessuna release pubblica o servizio a pagamento è stato creato.
