# Salvadanaio — contabilità locale e interfaccia

Non è un saldo bancario, un modulo investimenti o una promessa di disponibilità
reale del patrimonio. Si considerano soltanto i flussi nel registro Pivot.

## Invarianti

- Guadagnato annuale, fondi del budget e quote riservate sono tre quantità diverse.
- I pagamenti storici possono avere `excludedFromBudget: true`: rimangono incassi
  nello storico annuale, ma non diventano automaticamente denaro disponibile oggi.
  Il campo assente conserva il trattamento dei pagamenti già registrati.
- Il budget cattura l'importo pregresso originario una sola volta, **prima** che
  una ricostruzione storica riduca l'aggregato annuale e dettagli i vecchi incassi.
  Non si somma due volte il pregresso e non si ricalcola il budget dopo il backfill.
- I nuovi pagamenti normali aumentano i fondi. Un credito ancora da riscuotere,
  una lezione prevista e una promessa di pagamento non finanziano un obiettivo.
- Accantonare/rendere disponibili non cambia l'incassato annuale e non è una
  spesa o un trasferimento bancario. La somma di tutte le riserve non può essere
  accantonata una seconda volta su un altro obiettivo.
- Operazioni di conferma ripetute con lo stesso UUID non duplicano il movimento.
- Una spesa realmente avvenuta va registrata anche se rivela fondi insufficienti:
  il budget segnala il deficit senza cancellare o ridurre di nascosto le riserve.
  Anche una correzione di incasso può rivelare un deficit. Nessun nuovo
  accantonamento è ammesso in assenza di fondi liberi.
- Gli obiettivi con riserve richiedono prima un rilascio esplicito per essere
  archiviati. Lo storico dei movimenti viene conservato, non eliminato.
- Nome, obiettivo monetario, categoria e scadenza facoltativa. Il raggiungimento
  del target non prova il pagamento di un debito o l'acquisto del viaggio.

## Compatibilità e verifica

`AppData.savingsBudget` è opzionale e non viene inizializzato automaticamente
all'avvio. L'anteprima non modifica i dati: la base viene conservata solo alla
prima azione esplicita su obiettivo/spesa. Il codice non legge calendari e non
importa incassi storici: il futuro flusso EventKit
dovrà gestire identità, tariffe confermate, duplicati, date di pagamento ignote
e anteprima senza inventare un pagamento mensile.

`BackupCodec` valida il journal quando presente. I totali ricevuti per lezione
sono calcolati in tempo lineare con controllo overflow, anziché filtrare l'intero
registro per ogni lezione; controlla anche l'overflow dei totali annuali. Le nuove strutture entrano solo negli archivi
protetti, mai nel DTO online del Coach.

Test sintetici: apertura una sola volta, storico annuale separato, nuovi incassi,
crediti esclusi, più obiettivi, plafond, rilascio, idempotenza, spese/deficit,
correzione incasso, archiviazione, rollback, backup e overflow. Correzione,
annullamento e ripristino spese mantengono le revisioni. Le modifiche di obiettivi
e spese rifiutano una versione superata, senza sovrascrivere dati più recenti.

La UI aggiunge una card arancione fra riepilogo e grafico, lasciando iniziale il
riepilogo originale. Il vecchio ID grafico rimane stabile. Stato vuoto con +,
modulo nome/target/categoria/scadenza, accantonamento/rilascio, spese correggibili,
deficit esplicito e più obiettivi selezionabili. Nessun riferimento INPS nella
card obiettivo, nessun testo esplicativo superfluo. L'importo pregresso resta un
controllo del totale annuale e dichiara che non corregge i fondi già inizializzati.
Il collaudo Core non equivale a una verifica iPhone o a una consegna.
