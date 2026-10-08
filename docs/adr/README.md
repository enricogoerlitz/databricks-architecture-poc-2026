# Architecture Decision Records

Eine Entscheidung, die schwer rückgängig zu machen ist oder die jemand später hinterfragen wird,
bekommt einen Eintrag. Format: MADR, ein Dokument je Entscheidung, `NNNN-titel.md`.

**Wann ein ADR?**

- Die Wahl zwischen zwei Technologien, Bibliotheken oder Mustern.
- Eine Schnittstelle oder ein Datenmodell, das andere Teile bindet.
- Eine bewusste Abweichung von einer Konvention.
- Eine Entscheidung, die Geld, Betrieb oder Sicherheit betrifft.

**Wann kein ADR?** Wenn die Antwort aus dem Code folgt oder nur diese eine Aufgabe betrifft —
dann gehört sie in `questions.md` des Features.

Ein ADR wird nicht gelöscht und nicht umgeschrieben. Wird eine Entscheidung revidiert, bekommt
sie den Status `abgelöst durch ADR-NNNN`, und das neue ADR verweist zurück.

Anlegen: `/adr <titel>` oder `0000-template.md` kopieren.

## Übersicht

| Nr. | Titel | Status | Datum |
| --- | --- | --- | --- |
| — | _noch keine Entscheidungen_ | — | — |
