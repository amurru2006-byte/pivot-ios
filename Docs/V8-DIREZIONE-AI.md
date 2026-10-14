# Direzione AI di Pivot - proposta del 14 ottobre 2026

Questo documento conserva le strade valutate. Successivamente l'utente ha autorizzato l'approccio misto proposto; primo provider scelto per il collegamento: Groq con GPT-OSS 120B e gateway personale Cloudflare Workers. Qualità e disponibilità reali restano da verificare, non sono dimostrate dai test sintetici. Stato corrente in `V8-ONLINE-PRIVACY-E-QUOTE.md`. Budget aggiuntivo attuale: zero euro. L'utente richiede alternative, motivazione comprensibile, notifica e conferma prima di scrivere nel Calendario.

## Proposta principale

Usare un sistema misto: un modello online per capire la conversazione, ricordare preferenze esplicite e suggerire priorità; calcoli e convalida locali per attività realmente registrate, durata, conflitti, ciclo delle sedute, tragitti e cambiamenti del Calendario. La scrittura avviene soltanto dopo la conferma dell'utente e un nuovo controllo dei dati correnti.

Il collegamento alle mappe dovrà fornire tempi di viaggio con origine, destinazione, mezzo e orario. L'AI interpreta «dopo cena, con mio padre» o «palestra vicino all'università»; non inventa un tempo di percorso. L'app distingue tragitto calcolato, indicazione manuale e valore ancora sconosciuto. Non presume GPS, mezzo o borsa disponibili.

La successiva precisazione dell'utente amplia il requisito a percorsi multimodali e alternative fra cammino e mezzi, con attese, coincidenze, deviazioni e scioperi. Non basta una sola stima ETA. Servono dati di percorso e avvisi verificabili dei diversi operatori, con orario di controllo e copertura dichiarati. Le pagine pubbliche di stato non garantiscono da sole un'API o un'integrazione gratuita utilizzabile dall'app. Quella fattibilità va verificata prima di promettere il confronto automatico completo.

## Strade possibili

1. Solo telefono: il Qwen3 0.6B già presente ha attualmente un ruolo ristretto di selezione di opzioni verificate. È una base offline, non una comprensione generale già dimostrata della conversazione richiesta. Un modello locale più grande richiede misurare memoria, velocità, batteria e temperatura sul vero iPhone.
2. Online con piano gratuito: prima candidata GPT-OSS 120B servita da Groq, passando dal gateway autenticato già predisposto. Disponibilità del piano gratuito e risposte strutturate verificate nella documentazione ufficiale il 14 ottobre. Limiti e impostazioni reali dell'account vanno verificati prima dell'attivazione. Questo percorso è la proposta iniziale, non una promessa di qualità o gratuità perpetua.
3. Modello su un proprio computer/server: possibile controllo maggiore dell'esecuzione, ma hardware da verificare, macchina accesa e raggiungibile, manutenzione, rete e consumi. Non è automaticamente gratuito né indipendente da internet quando si è fuori casa. Non scegliere senza conoscere l'hardware e la disponibilità del computer.

Il gateway attuale usa GPT-OSS 120B nel codice, ma non è distribuito. Il modello è sostituibile nello sviluppo mantenendo il contratto di azioni verificabili. La scelta sarà confermata solo dopo confronto su casi sintetici in italiano e sulla qualità delle alternative, non dal solo superamento dei test di schema.

## Dati e memoria

Inviare soltanto il contesto necessario alla richiesta. Alias al posto degli identificativi Calendario, nessun invio automatico di indirizzi, titoli liberi, note, nominativi, incassi o dati sanitari. Il testo scritto dall'utente e le preferenze esplicite possono contenere dati personali: renderlo chiaro quando abilita l'AI online. Il gateway conserva il segreto del provider; il telefono usa un token revocabile protetto. Nessuna chiave nel repository o nel backup.

Per Groq, verificare nell'account Zero Data Retention prima dell'uso. La documentazione dichiara che è attivabile da tutti i clienti; non significa che sia già attiva nell'account dell'utente, né elimina l'elaborazione del prompt da parte del provider.

Pivot si personalizza tramite preferenze e dati salvati verificabili: ad esempio palestra prima della cena, una sede preferita e tempi effettivi delle sedute. Non si tratta di addestrare un nuovo modello personale a ogni utilizzo. Le preferenze restano consultabili e correggibili e ammettono eccezioni per una singola giornata.

## Sequenza proposta di sviluppo

1. Revisione delle attività, regole riutilizzabili e alternative su più giorni.
2. Ciclo degli allenamenti con ordine conservato e pause modificabili, stime delle durate e gestione degli spostamenti. Sono ammesse anche sedute consecutive: l'attuale alternanza non è una prescrizione obbligatoria.
3. Conversazione contestuale e negoziazione di alternative; una preferenza temporale modifica la ricerca, non forza uno spazio impossibile.
4. Notifica discreta, anteprima dell'intera catena di modifiche e conferma unica, con rifiuto delle proposte ormai obsolete.
5. Collegamento dell'AI reale e collaudo in italiano, con modalità locale disponibile quando rete o quota non consentono la conversazione online.
6. Solo successivamente: contesto palestra e problematiche fisiche. Nessuna diagnosi, durata di guarigione o fase clinica dedotta dai trend. Richieste di pausa e indicazioni ricevute restano distinguibili dai dati statistici.

## Casi obbligatori prima di scegliere il modello

- Due messaggi collegati: risveglio tardi, poi pranzo e palestra.
- Richiesta di andare dopo cena insieme a una persona, con alternativa prima di cena.
- Seduta saltata e recuperata nei giorni successivi senza cambiare l'ordine; due sedute consecutive quando scelte dall'utente e rispetto dei soli riposi esplicitamente vincolanti.
- Palestra alternativa vicino all'università con borsa non ancora preparata.
- Più origini/mezzi e un tempo di viaggio sconosciuto; confronto fra cammino, attese e coincidenze. Avviso di soppressione o sciopero solo da fonte aggiornata e pertinente.
- Evento passato senza risposta: domanda necessaria, nessun esito inventato.
- Impegno fisso, evento cancellato, proposta obsoleta e ricorrenza da non modificare in blocco.
- Nessuno spazio disponibile: spiegazione, nessuna affermazione di azione riuscita.
- Quota/rete assente: comunicazione esplicita e pianificazione locale.
- Richiesta relativa a malattia o infortunio: proposta di pausa controllabile su palestra o intera giornata, indicazioni professionali riferite e possibilità di revisione; nessuna data di guarigione inventata.

## Fonti ufficiali controllate

- Groq Structured Outputs: https://console.groq.com/docs/structured-outputs
- Groq Free plan e limiti: https://console.groq.com/docs/rate-limits
- Groq gestione dati e Zero Data Retention: https://console.groq.com/docs/your-data
- Cloudflare Workers Free, prezzi e limiti: https://developers.cloudflare.com/workers/platform/pricing/
- Apple MKDirections, candidato per i tragitti nell'app iOS: https://developer.apple.com/documentation/mapkit/mkdirections
- Trenord, pagina ufficiale circolazione in tempo reale: https://www.trenord.it/linee-e-orari/circolazione/tempo-reale/

Nessun servizio è stato attivato e nessun nuovo dato personale è stato inviato per valutare queste strade.
