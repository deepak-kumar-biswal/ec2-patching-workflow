# Architecture Diagrams (AWS Icons)

We generate a full architecture diagram using the `diagrams` Python library (mingrammer/diagrams) and Graphviz.

## Prerequisites

- Graphviz installed and on PATH
  - Windows: [graphviz.org/download](https://graphviz.org/download/)
- Python package `diagrams`
  - Already listed in `requirements-dev.txt`

## How to render

```cmd
:: Install prerequisites (Windows cmd)
pip install -r requirements-dev.txt

:: Generate PNG in this folder (architecture.png)
python docs\diagrams\generate_architecture.py
```

The output file will be `docs/diagrams/architecture.png`.

## Notes

- This is documentation-only; it does not affect runtime.
- Icons map to resources deployed by the CFN stacks (hub/spokes).
- If you update the architecture, please re-generate and commit the PNG.
