# Progressione e problematiche fisiche — confini del prossimo blocco

Decisioni dirette del 13 ottobre 2026. Primo sottoblocco segnalazioni implementato; verifica macOS/simulatore da concludere. Fasi e lettura della progressione ancora da implementare.

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

## Riferimenti e privacy

La guida ortopedica [AAOS, Knee Conditioning Program](https://www.orthoinfo.org/recovery/knee-conditioning-program/) richiede supervisione e selezione individuale degli esercizi con medico/fisioterapista: non viene trasformata in un protocollo personale o in conversioni tra macchine e bilanciere.

Sintomi e dati sanitari personali non sono inseriti nel repository o nelle fixture pubblicabili. Test sintetici e persistenza compatibile con backup esistenti. Restano da finalizzare i criteri non clinici della progressione e le fasi; nessun obiettivo riabilitativo tra esercizi viene inventato.
