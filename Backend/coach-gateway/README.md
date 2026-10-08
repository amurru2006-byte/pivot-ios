# Pivot Coach gateway — primo blocco

Il gateway è predisposto, NON ancora distribuito. Il Free tier Groq e Workers è obbligatorio per questo progetto; se quote/condizioni cambiano il servizio va sospeso o sostituito, non aggiornato automaticamente a pagamento.

Endpoint HTTPS POST /v1/coach. Contratto in Docs/Pivot-V8-first-block.md. Test senza rete: `node --test Backend/coach-gateway/worker.test.mjs` dalla radice.

Prima della connessione reale:

1. Account Groq Free; attivare e verificare Zero Data Retention, senza abilitare batch/fine-tuning. La semplice variabile del gateway non verifica l'account da sola.
2. Account Cloudflare Workers Free. Verificare che rate limiting binding e CPU del gateway rientrino nel piano. I limiti del binding sono locali al datacenter, non un contatore globale; le quote Groq restano il limite globale. Nessuna garanzia di servizio gratuito perpetuo/illimitato.
3. Generare un token client casuale di almeno 32 byte (base64url), conservarlo nel Keychain nell'integrazione iOS successiva; mettere sul server soltanto il digest SHA256. Non incollare segreti in chat, commit, backup o schermate.
4. Configurare GROQ_API_KEY e PIVOT_CLIENT_TOKEN_SHA256 come secrets, PRIVACY_READY=zdr-confirmed dopo la verifica. Se qualcosa manca, l'endpoint restituisce 503 senza contattare il provider.
5. Distribuire e verificare con payload sintetico; poi collegare il Coach e provare dati reali minimizzati. Non pubblicare l'app commerciale usando questo token personale condiviso.

Il gateway non archivia cronologia, non contiene console.log e non riflette i messaggi di errore del provider. Il provider elabora i dati del prompt; il trasporto cifrato non li rende invisibili al provider. La richiesta contiene messaggi e memorie forniti dall'utente, che possono essere personali. Nessun titolo libero, nota, indirizzo o identificativo calendario nel DTO.

Provider fisso gpt-oss-120b, schema strict, non streaming (limite attuale Groq Structured Outputs). Nessuna tool call, ricerca web, pagamento o retry automatico. Timeout 25 secondi, input 24 KB, output provider 32 KB, rate limit 3/minuto per token/datacenter. Il limite del provider può essere raggiunto prima. La UI deve continuare con le regole locali.
