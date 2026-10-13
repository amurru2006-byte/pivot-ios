# Verifica Serie 7

Baseline 0.7.5 preservata. Commit del primo blocco: f0922919bd80df787c94e67ec8a4f0005e423ca5. Correzione percorso artefatti: 3a70c2059a91ab1aa80a5bffbe280cd277d634bd.

CI del primo blocco 37797210284: riuscita, 198 Core e 15 UI senza fallimenti.

CI intermedia 37831664233 sul commit 55a94b2c: 210 Core, build Release e packaging passati; 18 UI con due fallimenti nei test popup PR/rank.

CI finale osservata 37836724126 sul commit ceba9f0c: 210 Core, build Release e packaging passati; 18 UI con un solo fallimento. I test popup PR e rank sono passati. Il fallimento effettivo è `testCompactTrainingRowsProtectPlanAndDeleteExtraSets` alla riga 122: dopo l'importazione della scheda di prova non viene trovato `exercise-statistics-test-squat` nella pagina Palestra. Artefatti recuperati e verificati il 12 ottobre 2026; log e anteprime sono conservati fuori dal clone in `../qa/serie7-ci/ceba9f0c/`.

Checkpoint Calendario, CI 38340745732: 216 Core, build Release, confezionamento IPA e tutti i 18 UI passati.

Checkpoint Salute, CI 38379904044, commit remoto 30c9816ac759a30e4f38ccca38cb3e88311c4f18, albero 5e3ce36cca4a39e67fdac881c2650f025fcf0934: 218 Core, build Release, confezionamento IPA e tutti i 18 UI passati. Il residuo del test galleria è chiuso; gli swipe dopo l'importazione ora tornano verso la galleria, che si trova sopra il controllo di importazione.

13 ottobre: aggiunti sei test Core per contesto serie/recupero e conservazione del tempo effettivo, un test UI per recupero all'ottavo esercizio/ultima serie/persistenza e un test UI per altezza e pulsanti della Live Activity condivisa. Verifica completa del nuovo blocco da concludere.

Nessuna release stabile sostituita. La candidata 0.7.6 (20) richiede ancora il collaudo hardware prima di essere promossa.
