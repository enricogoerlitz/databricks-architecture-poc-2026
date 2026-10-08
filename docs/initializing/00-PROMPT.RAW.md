databricks => Databricks Native Connectors; Data plane private und vnet Integration , databricks Public ; Deployment Pipelines; Connections; envs; secrets; Job Compute Architecture; zentrale Funktionen registrieren; shortcuts; cdc Pipelines ...


## Prompt

Ich möchte ein End-2-End modernes Databricks Projekt planen und umsetzten. Es ist ein PoC, weil ich länger nicht mit Databricks gearbeitet habe.
Es geht mir hier nicht um fancy datenmodellierung, sondern primär um eine Enterprise Architektur und wie man eine moderne databricks umgebung managed (mit git etc.).

Folgende (grob-) Anfordeurngen habe ich:
- ich will keine Azure Data Factory nutzen, sondern in Databricks auch die Orchestrierung machen (also Databricks native connectors) => hier will ich herausfinden, sind die gut? Wir können gerne ne SQL Server in Azure hochfahren und mit Daten beladen und dann nutzen wir nen connector; gerne auch nen Storage Account als Source, aber mit sowas wie copy data activity aus databricks will ich nach bronze schieben; ah und sind shortcuts unterstützt? für bronze-zero-copy?
- Ich will verstehen, wie man mehrere umgebungen (dev, test, prod) managed, deployed und dabei:
    - Connections ausstauscht
    - sensible Secrets etc sicher verwart und umgebungsübergreifend auch diese secrets quasi austauscht, weil dev und tst und prd haben zB unterschiedliche connectionstrings und access tokens etc
    - wie deployed man denn von dev -> tst -> prd? mit einem databricks cli cmd in devops action? (für den PoC nutzen wir GitHub) -> welche möglichkeiten gibt es da? Was ist best practice
    - das konzept sollte vorsehen, dass man die umgebungen in verschiedenen subscriptions hat, aber für den PoC trennen wir innerhalb einer subcription über resoruce groups
- ich möchte für silver python functions und ggf Klassen zentral registerieren können (im Unity Catalog?) und diese in unterschiedlichen Workspaces wiederverwenden können -> zB eine Datentransformierung (in echt-betrieb würde ich gerne SCD2 umsetzen, für unseren PoC reichen einfache funktionen, um einfach zu checken, wie man diese funktionen registriert und wiederverwendbar macht); geht das denn?
- wie könnte man ein metadatenmagement umsetzen, wo man metadaten zu metadata-driven-pipelines speichert
    - beispiel aus meiner fabric welt:
        - in fabric speichere ich in einer cosmosdb metadaten die beschreiben, wie eine pipeline gesteurt werden soll; also ich sage zB integriere diese 5 tabellen (name, source, destination etc (ohne secrets!)), sag dann noch, was von bronze nach silver passiert und dann sag ich noch wo gold getroggert werden soll
        - also sone pipeline würde dann zB nen SQL Server abfragen und nach bornze mit copy data activity kopieren, dann wpürde ein metadata-driven spark notebook getriggert werden, welches scd2 von bronze nach silver macht und dann trigert man noch custom gold notebooks / pipelines.
        - du verstehst?
    - und so eine standardisierte pipeline steuerung für zumindest von source zu brinze und von bronze nach silver würde ich auch gerne in databricks haben wollen
        - wenn möglich
        - und dann muss man die metadaten natürlich auch deployen können
- ich hätte gerne auch vnet integration (also für zB private integration von sources) und databricks sollte an sich public sein (also von außen zu erreichen), aber die ADLS2 (also Data Plane) sollte private sein
- ah und welche job compute, databricks spark einstellungen (serverless etc) gibt es; wir werden (wenn möglich) serverless nutzen, aber ich möchte auch wissen, welche alternativen es gibt und wann man welche einsetzt.

- ich will alles in einem Repo verwalten; also IaC, databricks definitionen, databricks notebooks etc; also git integration in ordnern, sodass deployment sauber laufen kann; aber ich will auch wissen, ob das best practice wäre. mono-repo ist halt leichter zu managen

Also wie du siehst, geht es mir wirklich sehr zentral um die verwaltung, Deployment Pipelines, Best Practices und co, weniger um komplexe Daten. Bronze, Silver und Gold können sehr simpel gestrickt sein.
