# AI online in Pivot: quote, dati e collegamento

Richiesta autorizzata il 14 ottobre 2026: conversazione interamente dentro Pivot, sistema online/local, messaggio esplicito quando finisce la quota, timer solo quando il servizio comunica un tempo, protezione dei dati personali. Provider scelto: GPT-OSS 120B via Groq, gateway personale Cloudflare Workers sul piano gratuito. Nessun passaggio automatico a pagamento.

## Comportamento implementato, da collaudare

- La stessa chat può usare il collegamento online oppure la base locale. Il compositore resta intatto se la rete, la quota o la risposta falliscono. Il passaggio locale è esplicito; il messaggio non viene accodato né reinviato automaticamente.
- Limiti provider e richieste ravvicinate sono distinti. Gateway legge Retry-After e i reset dei soli contatori esauriti; non confonde il reset di un contatore ancora disponibile con il tempo da aspettare. Con due limiti esauriti usa l'attesa maggiore. I tempi sconosciuti rimangono sconosciuti.
- Countdown in chat e orario italiano per riprovare. Persistenza protetta della sola attesa: chiudere Pivot non azzera il limite. La fine del timer permette una nuova verifica, non certifica crediti rigenerati.
- Promemoria locale facoltativo se c'è un tempo verificato e iOS ha autorizzato le notifiche. Testo generico, nessun evento o dato sanitario sul blocco schermo. L'aggiornamento dell'agenda conserva il promemoria; il tocco apre il Coach di Pivot.
- Configurazione iniziale in Pivot: endpoint HTTPS personale e token Pivot nel campo protetto, consenso esplicito sui dati inviati. Non si inserisce la chiave Groq nell'app.

## Protezioni concrete

- DTO minimizzato già verificato: alias, categoria/stato/orari; esclusi titoli liberi, indirizzi, note, studenti, pagamenti e dati Salute aggiunti automaticamente. Il testo digitato e le preferenze esplicite possono contenere dati personali e il consenso lo spiega.
- HTTPS con controlli TLS del sistema. Endpoint limitato al percorso previsto sul dominio Workers; query, credenziali nell'URL, frammenti e HTTP rifiutati. Redirect rifiutati su telefono e gateway, per non inoltrare token o corpo a un'altra destinazione.
- Token e configurazione nel Keychain `WhenUnlockedThisDeviceOnly`, sincronizzazione iCloud disattivata. Non fanno parte di AppData, JSON dello storico, export o backup Pivot. Revoca e cancellazione del collegamento disponibili.
- URLSession effimera, niente cache/cookie, tempi di attesa e dimensioni limitati; nessun errore grezzo del provider mostrato, salvato o aggiunto alla diagnostica. Le risposte AI valide vengono mostrate nella chat e incluse nel suo storico locale, come i messaggi dell'utente. Modificare la configurazione, lasciare la chat, mettere l'app in background o passare alla base locale cancella l'intero turno, anche prima dell'invio; controlli prima/dopo ogni attesa impediscono richieste tardive. Il testo nuovo eventualmente digitato durante l'attesa non viene cancellato dalla risposta precedente.
- Copie interne dello storico scritte con la stessa protezione iOS del file principale. Questo non introduce cifratura con password nei backup JSON esportati volontariamente: conservarli in un luogo protetto resta distinto dalla protezione del collegamento AI.
- Gateway richiede token, configurazione privacy verificata, schema limitato e rate limit; nessun log di prompt, archivio conversazioni, tool/URL/modello arbitrario o retry automatico. Secret Groq soltanto sul server; sul server digest del token client.

HTTPS non è cifratura end-to-end che renda il testo illeggibile al modello: il servizio deve elaborare la richiesta. Zero Data Retention va verificato nel vero account Groq prima dell'attivazione; la variabile del gateway non dimostra da sola la configurazione. Nessuna garanzia assoluta di assenza di vulnerabilità viene dichiarata.

## Verifiche

16 test Node locali passati con provider sintetico: quota di cinque ore, tempi composti/date HTTP, contatori distinti, dati mancanti o malformati, assenza di retry/leak di errori e controlli precedenti. Aggiunti 8 Core per stato, timer, persistenza, endpoint, consenso e sanitizzazione. Aggiunti 3 UI per compositore conservato, passaggio locale, impostazioni protette e annullamento prima dell'invio. Il workflow ora compila l'app e conserva la regressione Core/UI intera.

Prima verifica macOS, run 38596475109: **351 Core, zero fallimenti; 16 Node, zero fallimenti**, contati nei log. Questo run è stato sostituito durante la compilazione app per includere la correzione del ciclo di annullamento, non per un fallimento dei test. Verifica aggiornata su remoto `e5c7e76676551c634ff83ed243aaadf12d0ed579`, locale `69979fb3f069035961a235509a2ece541adb3092`, albero comune `f9e27ce224416d7d8d0047e1ca7b91677f2e3f9b`: run 38597561128, job 115968450621. **351 Core e 16 Node passati, compilazione Release iOS passata, 30/31 UI passati**. Tutte le 28 prove preesistenti, impostazioni privacy e annullamento del turno passano. La prova quota fallisce alla riga 43: impone textView mentre il TextField SwiftUI si trova con il suo identificativo esatto (usato anche dalla prova di annullamento passata). Correzione del solo localizzatore eseguita: typing e valore atteso restano obbligatori, da rieseguire. Non attribuire ai test sintetici qualità o disponibilità del vero modello e non dichiarare questo blocco interamente collaudato finché manca la nuova verifica.

## Limiti e prossimo passo

La 0.7.6 consegnata resta invariata. Questo primo collegamento mantiene il contratto iniziale pranzo/palestra di oggi; ciclo multi-giorno, alternative negoziate, fonti trasporto e avvisi operatori sono ancora da collegare. Non dichiararli già disponibili nella chat online.

Servono account Groq e Cloudflare reali, verifica piano gratuito e ZDR, endpoint e token personale prima della prova di comprensione in italiano. L'utente ha confermato di non avere/non conoscere gli account. Gli è stato chiesto soltanto di entrare in Groq, senza carte o chiavi: procedura in `V8-ATTIVAZIONE-GUIDATA.md`. Nessun account/servizio, segreto reale o costo è stato attivato. Tutto l'uso quotidiano avverrà in Pivot; l'accesso iniziale agli account è un'attività di configurazione separata.

## Continuità filesystem

iCloud ha alterato anche l'indice Git del checkout precedente, mostrando eliminazioni e file non tracciati per l'intero repository. Quelle copie sono state lasciate intatte. Il lavoro riprende da clone pulito del remoto `6d1a408ca379672be565191eb2b1178742645b96` in `C:/Users/amurr/.codex/visualizations/2026/10/12/01a131e1-f5b9-7601-910e-30fb0037fc63/pivot-v8-work`, area scrivibile di questa chat fuori da iCloud. La distribuzione all'utente resta in iCloud/PIVOT.

Fonti ufficiali: https://console.groq.com/docs/rate-limits ; https://console.groq.com/docs/your-data ; https://developer.apple.com/documentation/security/keychain-services ; https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral
