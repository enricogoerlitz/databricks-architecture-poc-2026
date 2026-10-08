---
status: offen            # offen | in-arbeit | erledigt
datum: JJJJ-MM-TT
autor: agent
spec: NNNN
---

# NNNN — Umsetzungsplan

Aufgaben in der Reihenfolge, in der sie bearbeitet werden. Jede Aufgabe ist einzeln abschließbar:
Test rot, Implementierung, Test grün, Linter grün, Commit.

## Aufgaben

### Task 1 — Kurztitel

- **Deckt ab:** AC-001
- **Berührt:** `pfad/zur/datei`
- **Testidee:** Was der Test prüft und warum er zuerst rot sein muss.
- **Fertig, wenn:** beobachtbares Ergebnis.
- **Status:** offen

### Task 2 — …

- **Deckt ab:** AC-002
- **Berührt:** …
- **Testidee:** …
- **Fertig, wenn:** …
- **Status:** offen

## Abdeckung

Jedes Akzeptanzkriterium muss in mindestens einer Aufgabe vorkommen. Diese Tabelle wird vor dem
ersten Commit geprüft.

| AC | Task | Test |
| --- | --- | --- |
| AC-001 | 1 | — |
| AC-002 | 2 | — |

## Reihenfolge und Abhängigkeiten

Was zuerst, was hängt woran, was kann parallel laufen.

## Was bewusst nicht Teil dieses Plans ist

Damit später klar ist, dass es nicht vergessen wurde.
