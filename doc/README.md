# Documentation

Project documentation lives in this `doc/` directory to keep layout consistent with other Verilog repositories.

Current documentation entry points:

| Path | Audience |
|------|----------|
| `xcelium_tutorial.md` | **Start here** — step-by-step Xcelium setup and UVM simulation walkthrough. |
| `../README.md` | Repository overview and Icarus Makefile targets. |
| `../uvm/README.md` | UVM verification map, ramp-up table, component tables. |
| `../uvm/sv/README.md` | Per-subdirectory navigation under `uvm/sv/`. |
| `../uvm/GEMINI.md` | Extending tests, scoreboard/debug detail, config DB. |
| `design_contract.md` | Target behavior for RTL and verification scope. |

## Markdown to PDF

All `README.md` files in the repository are written so they convert with **pandoc** and the default **`pdflatex`** engine (see the root `Makefile` rule `%.pdf: %.md`).

| Command | Output |
|---------|--------|
| `make readme-md-pdfs` | Every `README.md` → sibling `README.pdf` (ignored by git: `*.pdf`) |
| `make readme-pdf` | Only the repo root `README.md` → `README.pdf` |

**Prerequisites:** `pandoc` and a PDF engine on `PATH` (default `pdflatex`, e.g. TeX Live `texlive-latex-recommended`).

**Authoring rules for portable PDF:**

- Avoid **Unicode box-drawing** characters (for example tree characters U+251C/U+2514) inside indented or fenced blocks; `pdflatex` errors on those. Use ASCII (`+--`, spaces) in directory trees instead.
- **` ```mermaid `** blocks are emitted as literal code in the PDF (they are not rendered as diagrams unless you use an external Mermaid pre-processor).
- For unusual symbols, you can set `PANDOC_PDF_ENGINE=xelatex` if that engine is installed.

