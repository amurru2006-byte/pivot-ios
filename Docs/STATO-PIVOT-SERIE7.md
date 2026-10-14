# Pivot Serie 7 - stato durevole

Aggiornato il 14 ottobre 2026. La candidata completa è Pivot 0.7.6 (20), ramo `codex/pivot-serie7-workout-fixes`. La baseline resta Pivot 0.7.5 (19), commit `930d17fd292310cc3161bdd0a556619f1c0a43b6`, finché non termina il collaudo sul vero iPhone. Serie 8 e AI restano in pausa.

## Candidato verificato

Sorgente runtime remoto `5e319695607503b808a9854abcf0b62875818ad4`, equivalente al commit locale `20c61bcdb86b366c5d9cb8f7d652656f49debe9b`; albero comune `7d4de36b74ea793b09866fdc6e077ecba0c03872`.

GitHub Actions run 38548362555, tentativo 2, job 115855660448: successo. 303 test Core e 28 UI, zero fallimenti; build Release, confezionamento IPA e caricamento artefatti riusciti. Schermate e sette pagine PDF prodotte dall'app sono state ispezionate. Il pacchetto 0.7.6 (20) supera CRC, bundle app/widget, configurazione Live Activity e controllo degli entitlement HealthKit confezionati. La rifirma e le capability sul telefono non sono dimostrate dal simulatore.

## Funzioni concluse nella Serie 7

- Calendario fonte del programma futuro: cancellazioni esterne riconciliate; fotografie pendenti rimosse; storico con dati reali conservato come Rimosso dal Calendario; notifiche riconciliate su 36 ore. Un salvataggio completato o parziale con tempi reali validi aggiorna automaticamente la sola occorrenza collegata, senza titolo, note o ricorrenza.
- Salute in sola lettura: ultima lettura, conteggi, provenienza e modifiche applicate visibili; abbinamenti incerti scelti manualmente; orari Calendario scritti soltanto dopo conferma esplicita. Nessuna scrittura HealthKit e nessuna interpretazione medica.
- Recupero persistente sopra la barra inferiore anche all'ottavo/ultimo esercizio; countdown, esercizio, target, pausa, reset e prossima serie raggiungibili senza tornare in alto. Ultimo recupero chiudibile senza inventare una nuova serie. Live Activity automatica se autorizzata, deep link stabile e controlli da almeno 44 punti.
- Un solo comando Termina e salva allenamento: conserva una fine manuale valida o registra quella automatica, ferma recupero/Live Activity/avvisi, attende il salvataggio, riallinea l'occorrenza Calendario, conserva il PDF con UUID stabile e apre l'anteprima. Il retry PDF non duplica il report né sposta la fine.
- Cronologia per singola giornata/scheda, non per singolo esercizio: apertura e correzione senza nuovo timer o traguardo retroattivo; eliminazione confermata; conflitti obsoleti rifiutati; PR/rank/progressi ricalcolati dai dati rimasti. Calendario esterno e note manuali/Salute restano conservati; viene pulito soltanto il PDF interno derivato.
- Modificare uno storico mentre un campo è temporaneamente incompleto non apre più un alert globale e non sovrascrive l'ultima copia valida. Il dato finale valido continua ad autosalvarsi; le convalide dell'archivio non sono state allentate.
- Menu esercizio con Segnala dolore e Segnala infortunio; area/lato/data/intensità facoltativa/note/indicazioni e fonte; collegamenti espliciti a più movimenti; avvisi persistenti; correzione, Non più presente, storico e riattivazione. Nessun carico bloccato o cambiato automaticamente e nessuna diagnosi.
- Fasi facoltative Carico, Scarico e Recupero/rientro per scheda e giornata, fotografate nella sessione. Modificare una fase non avvia una sessione, non cambia carichi, non cancella segnalazioni e non riscrive il passato. La fase effettiva appare in storico e PDF.
- Obiettivo e andamento in cima ai progressi: usa solo range numerici, serie prescritte confermate e sessioni concluse davvero comparabili per variante, fase, target, set, carico e struttura. Gli avvisi rimangono visibili anche con limite superiore raggiunto. Nessuna diagnosi di stallo, quantità suggerita o aumento automatico.
- Tutti i sette rank originali: Schiavo della gravità, Patto col ferro, Sfidante della fisica, Distruttore di ego, Mutante, Forza primordiale, Onnipotente del carico. Stemma e titolo originali apribili in grande; nessun ritaglio, conversione o asset inventato. Soglie e logica PR restano invariate.
- PDF PT, esercizi/serie non svolti, isometrie a zero, warm-up, PR stimati e popup sono conservati. Il popup rimane leggibile per 8 secondi e chiudibile tramite X da 44 punti.

## Decisioni da non reinterpretare

Il personal non ha fornito una regola per aumenti o scarico. Gli esempi 10 kg/settimana, 40 kg di pressa o leg extension prima dello squat non sono protocolli. Rank, rep range e fase non autorizzano carichi o rientri. Sintomi personali non sono inseriti nel repository, nei PDF o nelle fixture. Nessun servizio a pagamento, release pubblica, nuova baseline o AI attivata.

## Consegna e limite residuo

IPA verificata SHA256 `55E40F57BDDAC02CD4FEDBCA16F764359E35CCFE6D6794FA8102FCF03A9BAE6A`. Consegna locale in `../Consegna-Serie7-2026-10-14/`, distinta dal clone. Prima dell'installazione va esportato un backup e l'IPA va installata sopra l'app esistente con AltStore HK Test, senza disinstallare.

Restano esclusivamente prove hardware: conservazione dati e rifirma, HealthKit reale, singola occorrenza EventKit, Live Activity/blocco schermo, notifiche/background e comportamento sull'iPhone 15. Solo dopo esito positivo si potrà decidere se promuovere 0.7.6 a nuova baseline.
