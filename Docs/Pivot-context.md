# Contesto e prossimi passi

## Richieste confermate dell’utente

Pivot è parte di un progetto personale più ampio: semplificare la vita, migliorare le abitudini e tenere traccia degli impegni. Il lavoro non riguarda soltanto l’app. La precedente chat era «orari esami chimica»; gli obiettivi e i consigli non recuperati verranno ripresentati dall’utente quando servono, senza inventarli.

Dispositivo principale: iPhone 15. Il modello AI locale è stato scaricato. La 0.7.0 è molto lenta; il touch risponde, ma con ritardo. Le cause del codice sono verificabili; il contributo effettivo di ciascuna va misurato sul telefono.

Quando registra una ripetizione e il guadagno, lo studente deve essere ricavato dal titolo del calendario, senza riscrivere il nome. Un cliente esistente va riutilizzato solo se il riconoscimento è univoco. Importo e incasso restano scelte esplicite.

Pagamenti: alcuni studenti pagano sempre settimanalmente, altri a ogni lezione. È richiesta un’abitudine persistente per studente e una scelta separata per una sola lezione: prossima lezione o data scelta. Il residuo di un pagamento parziale non scompare. I settimanali non sono in ritardo prima dell’ultima lezione prevista della settimana, da lunedì a domenica. Promemoria locali e saldo dello studente; un incasso può coprire più lezioni, dalla più vecchia, ma non viene mai inventato alla scadenza. Un anticipo superiore al saldo già guadagnato non viene registrato come compenso.

## Intervento 0.7.1

- Salvataggi locali seriali, atomici, raggruppati e fuori dal thread dell’interfaccia; stato visibile, retry e attesa prima di esportazioni/ripristino/modifiche al calendario.
- Agenda condivisa calcolata in background; modificare lo storico non rilancia ogni volta Calendario e Salute. Import e notifiche vengono limitati e accorpati.
- Riepiloghi e pianificatore Coach in background. Nessun questionario automatico che copra la schermata; conferme disponibili dall’agenda/Coach e dalle notifiche aperte volontariamente.
- AI locale con contesto e risposta limitati; memoria liberata lasciando il Coach, in background, per pressione memoria/calore/risparmio energia e dopo inattività. Il file AI non viene cancellato.
- Riconoscimento studenti dal calendario, gestione esplicita dell’ambiguità e riutilizzo del cliente nei pagamenti.
- Abitudini di pagamento e rinvii per lezione, scadenze dal calendario e promemoria sul saldo ancora dovuto. Pagamenti cumulativi/partiali con registrazioni in centesimi; il denaro conta solo alla ricezione esplicita.
- Impostazioni → Prestazioni e salvataggio mostra tempi e contatori senza contenuti personali.

## Da affrontare dopo la stabilità

AI esterna: valutare un servizio online oppure un server su computer/iPad. Nessun backend, account, costo o invio di dati personali è stato attivato in questa versione. Per un server personale servono modello/hardware disponibili, connessione e disponibilità del dispositivo; non si presume che il computer possa restare sempre acceso.

Recuperare progressivamente con l’utente i restanti obiettivi personali, le abitudini, lo studio/esami e le funzionalità future. Questa nota non è un elenco completo della precedente conversazione.

## Verifica e installazione

I test core e i test di interazione sul simulatore sono nel workflow macOS. La misura della fluidità reale e dell’AI richiede ancora l’iPhone 15. Prima dell’aggiornamento verificare/esportare il backup. Installare sopra Pivot esistente con lo stesso metodo/account, senza disinstallare: la cancellazione dell’app elimina la copia locale e il modello scaricato.
