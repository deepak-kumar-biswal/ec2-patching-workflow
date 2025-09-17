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

## Troubleshooting

If `python docs\diagrams\generate_architecture.py` exits with code 1, it’s usually Graphviz not being found.

1. Verify Graphviz is installed and on PATH

```cmd
dot -V
```

- If you see “'dot' is not recognized…”, add Graphviz to PATH (default install path shown):

```cmd
setx PATH "%PATH%;C:\Program Files\Graphviz\bin"
```

Then open a NEW cmd window and try `dot -V` again.

Optionally set explicit path for the diagrams backend:

```cmd
setx GRAPHVIZ_DOT "C:\Program Files\Graphviz\bin\dot.exe"
```

1. Verify Python dependencies

```cmd
pip show diagrams
python -c "import diagrams; print(diagrams.__version__)"
```

If missing, install in your active venv:

```cmd
pip install -r requirements-dev.txt
```

1. Re-run the generator with extra diagnostics

```cmd
python -X dev docs\diagrams\generate_architecture.py
```

Still stuck? Keep using the ASCII diagram in the main README while we sort out Graphviz locally—the PNG is optional.
