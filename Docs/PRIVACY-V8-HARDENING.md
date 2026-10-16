# Privacy V8 — prima correzione, non ancora un rilascio

## Confini modificati

- Il DTO online usa una copia priva degli stati e degli spostamenti riconoscibili
  come derivati da Salute, indipendentemente dal consenso ai resoconti.
- Memorie escluse dal cloud: non hanno una provenienza verificabile. Messaggio e
  sei turni recenti ammissibili passano da un filtro deterministico per nomi e
  alias dei contatti noti, luoghi noti, email, link, IBAN e numeri telefonici.
- Prima di ogni POST è richiesta un'anteprima locale con destinatari e richiesta
  completa. Annullamento, passaggio alla base locale o background non inviano
  nulla. Viene inviata la stessa richiesta esaminata; cambiamenti locali o
  scadenza dello snapshot la invalidano, senza rigenerazione nascosta.
- I nuovi backup JSON esterni escludono sempre i dati importati da Salute e il
  profilo forza, anche quando la vecchia impostazione di inclusione è attiva.
  In assenza di provenienza legacy affidabile, si escludono anche i rank derivati
  dal profilo. Restano registrazioni allenamento, record personali e finanze.
- La directory privata iOS viene esclusa dai futuri backup di sistema iCloud.
  I file locali restano protetti dalle opzioni di Data Protection già presenti.
- File locali illeggibili non vengono più esportati saltando il filtro; restano
  intatti per un eventuale recupero esplicito, senza sovrascrittura.

## Limiti espliciti

Non è cifratura del backup. Non è anonimizzazione semantica garantita. Nomi,
indirizzi e informazioni sanitarie sconosciuti possono restare nel testo libero:
la revisione è obbligatoria e la UI invita a usare la base locale per la salute.
Note e PDF allegati ai backup possono contenere informazioni personali non
identificabili automaticamente. Il filtro non è una certificazione di conformità
né una prova di assenza di qualsiasi canale derivato.

Non si leggono dati Salute reali o segreti, non si generano QR, non si chiamano
provider AI nei test e non si attiva un servizio nuovo. Nessun dato dell'utente
viene modificato. Nessuna pulizia delle copie iCloud precedenti: una modifica del
codice non può rimuovere retroattivamente file già esportati dall'utente.

La copia esterna è volutamente parziale: in un ripristino da JSON profilo forza,
rank derivati e dati Salute esclusi non sono disponibili e vanno ricompilati o
reimportati. Per un archivio portabile cifrato serve progettare anche password,
recupero e verifica del ripristino; non introdurre crittografia artigianale.

## Verifica

Test Core per provenienza e neutralizzazione, filtro testuale e suoi limiti,
immutabilità dell'originale, pagamento/residuo invariati, vecchi consensi e wake
senza sleep. UI sintetica: annulla conserva il testo, nessun invio prima del
consenso, errore provider simulato solo dopo il consenso. Gateway e strumenti
testati offline. Su Windows non sono disponibili compilatore Swift o simulatore
iOS: il collaudo Swift richiede il runner standard GitHub, senza pacchetto/rilascio.
Eseguiti localmente: 25 test gateway e 11 test Python, tutti passati. I 12 nuovi
test Swift e il nuovo test UI NON sono ancora eseguiti. Il workflow dedicato
esegue prima il Core completo e poi compila l'app per i quattro test UI del
collegamento online. Non produce un IPA e non sostituisce la regressione completa
richiesta per una consegna finale.

Fonti Apple ricontrollate il 16 ottobre 2026:
- https://developer.apple.com/documentation/healthkit/protecting-user-privacy
- https://developer.apple.com/app-store/review/guidelines/#health-and-health-research

## Dopo questo blocco

Restano cifratura portabile dei dati personali, audit di tutte le derivazioni e
note, privacy delle esportazioni PDF, verifica UI iOS e regressione completa sul
candidato finale. Entrate/Salvadanaio, audio definitivo e integrazioni future non
sono implementati da queste modifiche. Versione e IPA installata invariati.
