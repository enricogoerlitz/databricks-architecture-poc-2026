# src/

| Pfad | Zweck |
| --- | --- |
| [`dbxpoc_common/`](dbxpoc_common/README.md) | Wiederverwendbares Python-Paket (Wheel), genutzt von Pipelines, Jobs und UC Python UDFs |

Bauen: `uv build --wheel src/dbxpoc_common -o dist`. Hochladen in die Stage übernimmt die CI, siehe
`bundles/README.md`.
