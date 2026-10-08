---
status: offen            # offen | bestanden | mit-abweichungen | nicht-bestanden
datum: JJJJ-MM-TT
autor: agent
spec: NNNN
---

# NNNN — Nachweis

Erzeugt von `/review`. Nicht von Hand schönschreiben: was nicht erfüllt ist, steht hier als nicht
erfüllt.

## Ergebnis

**Gesamt:** offen

| Prüfung | Ergebnis |
| --- | --- |
| Spec-Konformität | — |
| Codequalität (`/code-review`) | — |
| Sicherheit (`/security-check`, `/security-review`) | — |
| Definition of Done | — |

## Akzeptanzkriterien

| AC | Ergebnis | Nachweis | Anmerkung |
| --- | --- | --- | --- |
| AC-001 | erfüllt / abgewichen / nicht erfüllt | Testname, Datei:Zeile | … |

**Abweichungen** — je Abweichung: was wurde anders gebaut, warum, wer hat es entschieden.

## Rückverfolgbarkeit

- **Anforderungen ohne Umsetzung:** _keine_ / REQ-…
- **Code ohne Anforderung (Scope Creep):** _keiner_ / …

## Sicherheitsbefunde

| Schwere | Fund | Ort | Umgang |
| --- | --- | --- | --- |
| — | _keine Befunde_ | — | — |

**Kritischer Pfad berührt:** ja / nein
Falls ja — Threat Model geprüft: ja/nein · Negativtests vorhanden: ja/nein · Prüfvermerk im PR: ja/nein

## Tests

- **Suite:** grün / rot — Kommando und Ergebnis.
- **Neue Tests:** Anzahl, und für jeden der Nachweis, dass er zuerst rot war.
- **Übersprungene oder entschärfte Tests:** _keine_ / … mit Begründung.

## Definition of Done

Die Checkliste aus `docs/process/definition-of-done.md`, Punkt für Punkt abgehakt. Nicht erfüllte
Punkte bleiben offen sichtbar.

## Empfehlung

`freigeben` · `freigeben mit Auflagen` · `nacharbeiten` — mit Begründung in einem Satz.
