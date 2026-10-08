# Stato Pivot V8

Aggiornato: 8 ottobre 2026. Primo blocco autorizzato direttamente dall’utente («vai pure avanti»).

Baseline immutata: Pivot 0.7.5 build 19, commit 930d17fd292310cc3161bdd0a556619f1c0a43b6. Ramo di lavoro: codex/pivot-v8-ai-foundation.

Vincoli: budget aggiuntivo 0 euro; dati online ammessi se protetti; offline essenziale conservato; eventuale vendita futura, senza credenziali condivise nell’IPA. Nessuna riscrittura.

Preparato: contesto minimo con cronologia pertinente e memorie esplicite, alias eventi, risposta strutturata, anteprima pranzo/palestra mediante Planner e CoachPlanner esistenti. Nessuna scrittura calendario o cambiamento alla UI. Gateway Groq Free + Workers Free predisposto, autenticato e senza log dei prompt, non distribuito. Nessun account creato e nessun segreto ottenuto.

Verificato localmente: 10 test gateway passati con trasporto sintetico; git diff --check. Test Swift aggiunti; suite Core e compilazione iOS ancora da eseguire in Actions. Non dedurre qualità del modello da risposte simulate.

Da completare: CI Core/iOS; collegamento al Coach con credenziali nel Keychain e modalità offline; verifica delle conferme per più eventi; account Free, ZDR verificato e prova reale di comprensione/velocità. Nessuna nuova IPA o release.

Contratto: Docs/Pivot-V8-first-block.md. Configurazione gateway: Backend/coach-gateway/README.md. Questo checkpoint va aggiornato a ogni blocco verificato.
