# Verifica Serie 7

Baseline 0.7.5 preservata. Commit del primo blocco: f0922919bd80df787c94e67ec8a4f0005e423ca5. Correzione percorso artefatti: 3a70c2059a91ab1aa80a5bffbe280cd277d634bd.

CI del primo blocco 37797210284: riuscita, 198 Core e 15 UI senza fallimenti.

CI intermedia 37831664233 sul commit 55a94b2c: 210 Core, build Release e packaging passati; 18 UI con due fallimenti nei test popup PR/rank.

CI finale osservata 37836724126 sul commit ceba9f0c: 210 Core, build Release e packaging passati; 18 UI con un solo fallimento. I test popup PR e rank sono passati. Il fallimento effettivo è `testCompactTrainingRowsProtectPlanAndDeleteExtraSets` alla riga 122: dopo l'importazione della scheda di prova non viene trovato `exercise-statistics-test-squat` nella pagina Palestra. Artefatti recuperati e verificati il 12 ottobre 2026; log e anteprime sono conservati fuori dal clone in `../qa/serie7-ci/ceba9f0c/`.

Nessuna release stabile sostituita. La candidata 0.7.6 (20) resta non verificata finché il test residuo e il collaudo hardware non sono chiusi.
