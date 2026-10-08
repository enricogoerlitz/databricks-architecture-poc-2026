---
status: offen            # offen | entwurf | freigegeben
datum: JJJJ-MM-TT
autor: agent
spec: NNNN
---

# NNNN — Technisches Design

## Ansatz

Wie wird es gebaut, in drei bis fünf Sätzen. Der Rest des Dokuments begründet und verfeinert das.

## Betroffene Bereiche

| Bereich | Änderung | Neu oder Bestand |
| --- | --- | --- |
| … | … | … |

## Datenmodell

Neue oder geänderte Entitäten, Felder, Beziehungen. Bei Änderungen an bestehenden Strukturen:
Wie kommen vorhandene Daten in den neuen Zustand?

## Schnittstellen

Endpunkte, Signaturen, Ereignisse, Verträge. Vertrag zuerst, Implementierung danach.

## Threat Model

**Pflicht.** Bei kritischen Pfaden (Authentifizierung, Berechtigungen, Sessions, Datenmigrationen,
Löschvorgänge, Zahlungsverkehr, externe Schnittstellen, Infrastruktur) ausführlich, sonst kurz.

| Was könnte schiefgehen | Wodurch | Gegenmaßnahme | Getestet durch |
| --- | --- | --- | --- |
| Unberechtigter Zugriff auf … | fehlende serverseitige Prüfung | Prüfung in … | AC-… |
| Eingabe … führt zu … | fehlende Validierung | Allowlist in … | AC-… |
| … | | | |

**Berührte kritische Pfade:** _keine_ / … 
**Personenbezogene Daten betroffen:** ja / nein — welche?

## Betrachtete Alternativen

Was wurde verworfen und warum. Wird eine Alternative später wieder interessant, entsteht daraus
ein ADR.

## Auswirkungen auf Betrieb

Konfiguration, Migrationen, Abhängigkeiten, Performance, Beobachtbarkeit, Rollback.

## Risiken

| Risiko | Auswirkung | Umgang |
| --- | --- | --- |
| … | … | … |
