# tools/

`python -m tools.metadata validate` prüft JSON Schema und Querverweise, z. B. ob ein Schedule in
jeder Stage existiert und dass Keys nicht transformiert werden. `render --env <env>` zeigt die
generierten Bundle-Ressourcen. Die Generator-Logik liegt in
`bundles/ingestion/resources/generator.py`.
