# Studenti, calendario e correzione importi

Requisiti del bug report recepiti prima della candidata AI. Nessun dato reale del report è incorporato nel repository o nelle prove.

## Profilo unico e doppioni preesistenti

Aggiungere una tariffa per un nome già registrato aggiorna lo stesso ID, senza ricalcolare lezioni o incassi passati. Con più corrispondenze la scrittura viene rifiutata: il nome uguale non prova che sia la stessa persona. Dal dettaglio studente sono disponibili modifica nome/tariffa e unione esplicita di due profili, con scelta della persona da conservare e conferma. L'unione conserva importi, date, ID di lezioni/incassi e collegamenti al calendario; cambia soltanto il riferimento allo studente. La tariffa e l'abitudine di pagamento del profilo conservato restano quelle future. Le bozze associate al profilo trasferito vengono ricollegate. I saldi si ricalcolano sugli stessi incassi, non su conguagli sintetici.

I vecchi nomi e gli alias confermati sono riconoscibili nel calendario. Corrispondenze esatte o per parole intere, accenti/case/spazi normalizzati; identità ambigue mai attribuite automaticamente. Nessuna unione automatica al caricamento dei backup. Gli alias sono locali e opzionali, così i backup precedenti rimangono leggibili.

## Compenso e incasso sono diversi

Il dettaglio della lezione è raggiungibile anche dagli incassi già saldati, non soltanto dai debiti. Correggi compenso modifica quanto era dovuto e il residuo, senza modificare quanto è stato ricevuto. Correggi questo incasso modifica la singola ricevuta selezionata alla sua data originale, aggiorna il totale ricevuto e quindi il conteggio annuale; non cambia altri incassi, importo pregresso o lezioni future. Ogni correzione effettiva lascia una traccia locale vecchio/nuovo importo e istante.

Importi invalidi, ricevute non positive e compensi inferiori agli incassi vengono rifiutati prima di modificare i dati. Un rimborso effettivo non va mascherato da correzione: un flusso rimborsi è fuori da questo blocco. Se un incasso era digitato male, correggere prima quell'incasso. L'annullamento non scrive nulla.

## Riconoscimento e primo blocco AI

Il riconoscimento dei nomi già noti avviene localmente nell'evento, anche recuperando una bozza, e nelle scadenze dello studente. Doppioni o alias condivisi richiedono scelta esplicita. Non si inviano nomi di clienti, incassi, titoli liberi o note del calendario a Groq per risolvere un'associazione finanziaria. Il contratto online di questo primo blocco rimane limitato a conversazione e proposte pranzo/palestra per oggi, con conferma delle modifiche. Interpretazione AI di nuovi soprannomi o identità non note e l'intera pianificazione multi-giorno NON sono ancora dichiarate implementate.

## Verifiche preparate, non ancora passate

15 nuove prove Core coprono aggiornamento tariffa, rifiuto duplicati, unione senza perdita di denaro/ID/date, alias, conflitti, correzioni compenso/incasso, audit e compatibilità. Includono rinomina con mantenimento del nome Calendario e riuso/rifiuto ambiguo dell'identità anche nella registrazione contabile, non solo nella UI. Tre UI verificano unione/modifica tariffa/riavvio, correzioni persistenti e rifiuto del compenso sotto il ricevuto. Usano soltanto fixture sintetiche e un contenitore Debug simulatore dedicato per UUID. Nessun dato dell'installazione personale viene migrato durante il collaudo.
