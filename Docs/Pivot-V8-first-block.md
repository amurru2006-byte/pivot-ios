# V8.1 — contratto del primo blocco

Baseline: 0.7.5 / 930d17fd292310cc3161bdd0a556619f1c0a43b6. Budget aggiuntivo: 0 euro. Questo blocco prepara comprensione remota e anteprima locale; non cambia ancora la schermata Coach e non pubblica una nuova IPA.

## Caso e flusso

L'utente comunica prima che si è svegliato a mezzogiorno, poi chiede pranzo seguito da palestra. Il servizio vede la conversazione pertinente e una fotografia della giornata. Restituisce un messaggio e, per una proposta, gli ID temporanei delle attività nell'ordine richiesto. Non restituisce orari, durate, dati Salute o azioni da eseguire.

`CoachV8Snapshot.make` -> richiesta JSON -> gateway autenticato -> risposta strutturata -> `CoachV8Planner.preview` -> `Planner.recover` -> `CoachPlanner.validate` -> `CoachOption` da mostrare. L'anteprima non modifica AppData. Il successivo collegamento alla UI riuserà le conferme esistenti, con verifica specifica delle proposte che contengono più eventi.

## Contratto e privacy

- Richiesta v1: requestID, now, dayKey, message, eventi del giorno, ultimi messaggi e memorie esplicite.
- Eventi: alias temporaneo, categoria/kind, stato, orari, durata, flessibilità e disponibilità dei tragitti. Nessun identificativo EventKit, titolo libero, indirizzo, nota, studente, pagamento o dettaglio Salute. I messaggi digitati e le memorie possono contenere dati personali: renderlo visibile prima di abilitare AI online.
- Risposta v1: requestID, mode (conversation/clarify/plan), eventIDs ordinati, reply. Schema chiuso. Una plan contiene 1–2 attività, solo pranzo/palestra nel primo blocco. Nessun campo orario o azione.
- Snapshot locale completo per rilevare cambiamenti: inviare meno dati non significa verificare meno conflitti.
- Piano limitato a oggi; nessun accorciamento o spostamento di altri impegni. Se mancano l'attività o i tragitti, chiedere il dato mancante. Una routine trascorsa non viene automaticamente cancellata.
- Gateway: Free tier soltanto, segreto provider sul server, token client revocabile, HTTPS, rate limit, payload e timeout limitati; nessun logging dei prompt o dei corpi degli errori. ZDR da verificare nell'account prima di impostare PRIVACY_READY=zdr-confirmed.
- Quota finita/rete assente: risposta di indisponibilità, regole locali; nessun upgrade o fallback a pagamento.

## Criteri di accettazione

1. Gli orari proposti vengono dal pianificatore locale e preservano durata/tragitti/impegni fissi.
2. Due messaggi collegati sono presenti nel contesto; una memoria persistente non autorizza azioni.
3. ID sconosciuti, duplicati, risposta vecchia, JSON malformato, campi extra e schema errato vengono rifiutati.
4. Agenda o AppData cambiati invalidano la risposta prima della proposta; data passata o cambio giorno richiedono un nuovo contesto.
5. Anteprima senza scritture; assenza di spazio/tragitti produce una spiegazione locale.
6. Gateway nega richieste non autenticate, fuori quota, troppo grandi, scadute e non conformi. Non riflette errori provider contenenti dati.

## Verifica e limiti

Test Swift Core, test gateway Node con trasporto finto (nessun dato reale né chiamata a pagamento), compilazione iOS su CI. Le fixture sono dati sintetici dichiarati per i test, non ricostruzioni della giornata dell'utente. Nessun test con risposta finta dimostra qualità del modello remoto: account Groq, ZDR e endpoint reale restano necessari per quella prova.

Fonti consultate: https://console.groq.com/docs/structured-outputs (GPT-OSS 120B supporta strict schema, senza streaming/tool use); https://console.groq.com/docs/your-data; https://console.groq.com/docs/rate-limits.
