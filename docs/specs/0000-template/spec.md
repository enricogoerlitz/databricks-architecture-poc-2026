---
status: entwurf          # entwurf | in-review | freigegeben | umgesetzt | verworfen
datum: JJJJ-MM-TT
autor: agent             # agent | mensch
quelle: docs/product/discovery/<slug>.md, docs/product/prototypes/<slug>/
---

# NNNN — Feature-Titel

## Problem

Welches Problem wird für wen gelöst? Zwei bis vier Sätze, in der Sprache der Fachseite.
Keine Lösung, kein Technikbegriff.

## Ziel

Woran erkennt man, dass es gelöst ist? Beobachtbar formuliert.

## Nicht-Ziele

Was dieses Feature ausdrücklich **nicht** tut. Mindestens zwei Punkte — dieser Abschnitt
verhindert die meisten Missverständnisse.

- …
- …

## Nutzer und Rollen

| Rolle | Was sie hier tun | Was sie nicht dürfen |
| --- | --- | --- |
| … | … | … |

## Anforderungen und Akzeptanzkriterien

Jede `REQ-ID` stammt aus dem Klickdummy (`data-req`) oder wird hier vergeben. Zu jeder Anforderung
gehört mindestens ein Kriterium in Gherkin. Ein Kriterium ist gut, wenn ein Test daraus
geschrieben werden kann, ohne nachzufragen.

### REQ-001 — Kurztitel

> Ein Satz in Fachsprache, was gefordert ist.

**AC-001**

```gherkin
Angenommen  <Ausgangszustand>
Wenn        <Handlung>
Dann        <beobachtbares Ergebnis>
```

**AC-002 — Fehlerfall**

```gherkin
Angenommen  <Ausgangszustand>
Wenn        <ungültige Handlung>
Dann        <definierte Reaktion, keine stille Annahme>
```

### REQ-002 — …

…

## Daten

Welche Daten werden gelesen, geschrieben, gelöscht? Sind personenbezogene Daten dabei? Wo kommen
sie her, wie lange bleiben sie?

## Randbedingungen

Technische, zeitliche, rechtliche oder organisatorische Vorgaben, die nicht verhandelbar sind.

## Abhängigkeiten

Was muss vorher da sein? Welche anderen Specs, Systeme oder Entscheidungen hängen damit zusammen?

## Offene Punkte

Verweis auf `questions.md`. Blocker werden hier zusätzlich genannt, damit sie nicht übersehen
werden.

## Rückverfolgbarkeit

| REQ | Klickdummy | AC | Umgesetzt in Task | Test |
| --- | --- | --- | --- | --- |
| REQ-001 | `<slug>/screens/…#…` | AC-001, AC-002 | — | — |
