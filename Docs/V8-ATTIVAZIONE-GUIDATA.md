# Attivazione iniziale dell'AI di Pivot

Stato al 14 ottobre 2026: l'utente ha creato gli account Groq e Cloudflare. Entrambi i piani sono stati verificati nella UI autenticata: Free, $0, Current Plan. Su Groq Global ZDR e Inference APIs ZDR sono attivi; Batch e Fine-tuning/LoRA sono disattivati. Il solo gateway `pivot-coach` è pubblicato su Workers Free dopo consenso specifico, senza upgrade. L'utente ha inserito direttamente la chiave Groq come secret; il token Pivot è generato e conservato nel portachiavi Windows, solo il suo digest è sul server. Flag privacy configurato dopo nuova verifica ZDR. Quattro controlli di accesso e due casi italiani sintetici passati sul servizio reale. Nessun valore della chiave Groq letto o passato in chat, nessun calendario reale trasmesso, nessuna nuova IPA consegnata. La procedura va accompagnata un passo alla volta: non richiede competenze informatiche.

## A cosa servono questi due account

Groq fornisce il modello che interpreta i messaggi. Cloudflare ospita il piccolo collegamento personale che tiene la chiave Groq fuori dall'iPhone. Dopo questa configurazione iniziale, si scrive e si ricevono le risposte dentro Pivot; non si usa una seconda chat esterna.

Si usa soltanto il piano gratuito. Le quote esistono e possono cambiare; non sono una promessa di uso illimitato. Nessuna carta o attivazione a pagamento deve essere richiesta per proseguire questa procedura. Se compare una richiesta del genere, fermarsi e verificare la schermata.

## Accesso a Groq (già completato)

1. Aprire https://console.groq.com.
2. Creare l'account con il metodo di accesso che si preferisce, oppure accedere se l'account esiste già. Password, codici di verifica e accettazione delle condizioni sono operazioni dell'utente.
3. Una volta entrati, riferire cosa appare nella schermata principale. Si può mostrare una foto con email e altri dati personali oscurati.

Non incollare chiavi nella conversazione. Account, pubblicazione e segreti server sono già configurati: non ripetere login, creazione account, chiave Groq o Deploy. Restano il collaudo dell'app e il trasferimento protetto del distinto token Pivot all'iPhone. La versione 0.7.6 consegnata non contiene questo nuovo collegamento.

## Passi successivi, da accompagnare dopo l'accesso

- Verificare il piano Groq e le quote dell'account reale. Nelle impostazioni Data Controls verificare e abilitare Zero Data Retention per l'inferenza; disabilitare funzioni che conservano contenuti. Non basta impostare una variabile nel codice. Groq continua a elaborare il testo e a conservare metadati d'uso: ZDR non significa che il provider non vede il messaggio.
- Account Cloudflare, Workers Free e pubblicazione iniziale sono completati. La configurazione del limite richieste è stata verificata durante il deploy: 3 richieste/60 secondi, locale al datacenter. Non serve acquistare un dominio o pubblicare l'intero repository iOS dal wizard GitHub.
- Creare la chiave Groq soltanto quando è pronto il suo inserimento diretto tra i segreti del collegamento. Non passarla in chat, screenshot, repository, iCloud o backup. Il token personale Pivot è un segreto diverso: sul server resta soltanto il suo digest; sull'iPhone viene conservato nel portachiavi non sincronizzato.
- Distribuire il collegamento personale, verificarne autenticazione, quota e risposta con dati sintetici. Nessun invio del calendario reale finché privacy, consenso e verifiche non sono completati.
- Collegare Pivot dalla schermata «AI online e privacy», inserendo indirizzo e token Pivot nel campo protetto, e confermare il consenso. Non inserire nell'app la chiave Groq.
- Provare la conversazione in italiano e il comportamento con rete o quota assente. I test sintetici verificano il software, non la qualità del modello reale. Gli spostamenti nel Calendario richiedono comunque la conferma dell'utente.

## Cosa resta da costruire

Il primo contratto online permette conversazione e proposte per pranzo/palestra di oggi. Recupero del ciclo su più giorni, budget statistico collegato alla proposta, percorsi alternativi e avvisi trasporto non sono ancora disponibili nella chat online. Non confondere la configurazione del collegamento con il completamento della Serie 8.

Fonti ufficiali consultate il 14 ottobre 2026:

- Accesso Groq: https://console.groq.com
- Dati e ZDR: https://console.groq.com/docs/your-data
- Quote: https://console.groq.com/docs/rate-limits
- Workers Free: https://developers.cloudflare.com/workers/platform/pricing/
- Rate limiting e limiti della dashboard: https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/
