# Serie 7 - collaudo sul vero iPhone

Candidato Pivot 0.7.6 (20), distinto dalla baseline 0.7.5 (19). I controlli automatici sono conclusi: 303 Core e 28 UI, zero fallimenti. Questa lista riguarda soltanto ciò che simulatore e pacchetto non possono provare.

## Prima di installare

1. Esportare da Pivot un backup completo in una cartella iCloud Drive fuori da Pivot. Verificarne la presenza e non sovrascrivere copie precedenti.
2. Non disinstallare Pivot. Installare `Pivot-0.7.6-20-Serie7-5e31969.ipa` sopra l'app esistente usando lo stesso AltStore HK Test e lo stesso account Apple.
3. Dopo l'apertura, controllare subito schede, cronologia, impostazioni e profilo. Se manca qualcosa, fermarsi e non ripristinare né cancellare dati senza analisi.

## Controlli senza esercizio

4. Aprire Rank e profilo forza. Verificare tutti i livelli 1-7 con nomi, stemmi e titoli originali; nessuna immagine deve essere tagliata.
5. Aprire una giornata senza avviare l'allenamento. Il menu ⋯ deve mostrare Cambia esercizio, Segnala dolore e Segnala infortunio.
6. Usare una segnalazione chiaramente TEST, collegare due movimenti, verificare entrambi gli avvisi, segnare Non più presente e controllare che lo storico resti. Non inserire sintomi fittizi come reali.
7. Impostare una fase sulla scheda e un override sulla giornata. Nessun carico deve cambiare e nessun vecchio allenamento deve essere riscritto o avviato.
8. In Cronologia e progressi verificare Obiettivo e andamento in alto. Deve usare serie confermate, conservare gli avvisi e dichiarare che i carichi restano manuali.

## Prossimo allenamento abituale

Non aumentare carichi, non fare massimali e non eseguire movimenti che provocano fastidio soltanto per collaudare Pivot.

9. Avviare una normale sessione. Se Attività live è autorizzata, deve partire automaticamente; se iOS la nega, l'allenamento in app deve continuare.
10. Sul blocco schermo controllare nome, serie, carico/ripetizioni o secondi, target, recupero e pulsanti. Se disponibile, verificare Dynamic Island compatta/espansa.
11. Al Cable Crunch/ottavo esercizio, dopo una serie il recupero deve restare visibile in fondo. Provare pausa, reset e prossima serie; all'ultima usare Chiudi recupero. Una nuova serie confermata deve conservare il recupero effettivo precedente.
12. Toccare la Live Activity anche dopo aver chiuso Pivot: deve aprire direttamente l'allenamento corretto senza una pagina duplicata.
13. Usare esercizio non svolto o salta serie rimanenti solo quando serve davvero. Le serie già fatte devono restare. Una isometria 0+0 deve essere non svolta; campo vuoto resta assente.
14. Premere Termina e salva allenamento dal fondo: fine, salvataggio, stop recupero/Live Activity e anteprima PDF devono essere un unico flusso. Una fine manuale valida non deve cambiare.
15. Dalla cronologia della giornata riaprire il lavoro, correggere un dato reale se necessario e verificare che non parta un timer né un popup retroattivo. Non eliminare uno storico reale per fare una prova.

## Calendario e Salute

16. Creare un evento Calendario chiamato chiaramente TEST. Eliminarlo nell'app Calendario, tornare in Pivot e aggiornare la Home: non deve restare pendente. Lo storico con dati reali, se presente, deve essere conservato come Rimosso dal Calendario.
17. Su un'altra occorrenza TEST salvare inizio/fine reali: deve essere aggiornata soltanto quell'occorrenza, senza cambiare titolo, note o serie ricorrente. Non usare una lezione reale come prova.
18. In Salute e Apple Watch premere Aggiorna dati da Salute. Controllare ultima lettura, conteggi, provenienza e modifiche applicate. Abbinamenti incerti richiedono una scelta; nessuna scrittura deve comparire nell'app Salute.
19. Verificare che AltStore abbia conservato i permessi HealthKit. La sola presenza degli entitlement nel pacchetto non lo dimostra. Controllare inoltre notifiche e Live Activity dopo blocco/sblocco e ritorno in primo piano.

## Esito

Comunicare: dati precedenti presenti o no; recupero in fondo; blocco schermo; Calendario TEST; Salute; eventuale messaggio esatto. Allegare screenshot senza dati personali quando possibile. La candidata non diventa nuova baseline finché questi controlli hardware non hanno esito positivo.
