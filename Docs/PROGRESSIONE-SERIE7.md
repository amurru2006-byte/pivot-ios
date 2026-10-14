# Progressione, fasi e problematiche fisiche - Serie 7

Implementazione e collaudo simulatore conclusi il 14 ottobre 2026. Serie 8/AI resta in pausa.

## Scopo reale

La Serie 7 rende leggibile ciò che l'utente ha davvero registrato e mantiene visibile il contesto dichiarato. Non sostituisce il personal o un professionista sanitario e non decide autonomamente un carico.

Il personal non ha fornito una regola per aumenti o scarico. Gli esempi 10 kg/settimana, 40 kg di pressa o leg extension prima dello squat erano ipotesi illustrative, non protocolli. Non sono codificati come soglie, equivalenze fra esercizi o idoneità al rientro.

## Segnalazioni

- Dal menu ⋯ di ogni esercizio sono disponibili Segnala dolore e Segnala infortunio, oltre a Cambia esercizio.
- Una segnalazione registra zona obbligatoria, lato, data, intensità facoltativa 0-10, note ed eventuali indicazioni ricevute con la loro fonte.
- L'utente collega esplicitamente uno o più movimenti. L'avviso segue lo stesso identificativo/variante di catalogo; Pivot non deduce collegamenti dalla parte del corpo.
- Gli avvisi persistono sulle righe interessate e nella sezione generale Dolori e infortuni. La segnalazione non avvia un allenamento e non modifica scheda, serie, carichi, PR o rank.
- Non più presente toglie l'avviso ma conserva lo storico; una segnalazione può essere corretta o riattivata. Non equivale a guarigione o via libera clinico.
- Vecchi backup restano compatibili. Le segnalazioni sono escluse dai report PT e dal contesto inviato automaticamente al Coach.

## Fasi

- Fase facoltativa della scheda: Carico, Scarico, Recupero/rientro o non dichiarata.
- Ogni giornata può ereditare la fase della scheda o sostituirla esplicitamente.
- La nuova sessione conserva uno snapshot. Modifiche successive non riscrivono allenamenti vecchi o già iniziati.
- La fase di una sessione può essere corretta manualmente e appare in cronologia, revisioni e report PT.
- Scegliere una fase prima dell'avvio non crea una sessione. Nessuna fase applica percentuali, cambia carichi, risolve segnalazioni o autorizza un rientro.

## Obiettivo e andamento

Il riquadro è in cima a Cronologia e progressi dell'esercizio, prima della fotografia.

- Interpreta soltanto numeri o intervalli numerici espliciti da 1 a 1000. AMRAP, tempo, piramidi, istruzioni per lato, isometrie, back-off e drop set non ricevono una soglia inventata.
- Contano soltanto serie prescritte realmente confermate. Warm-up, extra, saltate, incomplete o soltanto precompilate non dimostrano un risultato.
- Una sessione in corso resta parziale; non viene sostituita da un vecchio successo.
- Il confronto richiede una sessione precedente conclusa e completa con stesso esercizio/ID/variante, fase, target, numero e tipo di set, carico, cedimento, gruppo/superset, recuperi prescritti e indicazioni PT.
- Vengono mostrati target originale, serie confermate, limite superiore e differenza totale di ripetizioni quando il confronto è valido. Nessuna diagnosi di stallo, debolezza o quantità da aggiungere.
- Grafici e riepilogo usano lo stesso filtro di variante. Gli avvisi fisici rimangono visibili e apribili anche dopo un risultato numerico positivo.

## Verifica

Test dedicati inclusi nel collaudo completo: 13 Core segnalazioni, 15 Core fasi, 25 Core progressione e i rispettivi flussi UI, oltre a compatibilità backup, conflitti, privacy PDF, persistenza e assenza di mutazioni. Il run finale 38548362555 ha superato complessivamente 303 Core e 28 UI.

## Confine Serie 8

Una futura AI potrà spiegare lo storico o preparare domande per coach/professionista, ma non dovrà trasformare correlazioni in diagnosi o protocolli. Nessun dato sanitario personale è inserito nel repository o nelle fixture pubblicabili.
