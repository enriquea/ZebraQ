# Setting up the Python track

There are three ways to run the ZebraQ Python lessons. Pick one.

If you are new to programming, **use Google Colab**. It requires no installation
at all and works on any machine with a browser, including a Chromebook or a
tablet.

---

## Option 1 — Google Colab (nothing to install)

1. Open the repository's main [README](../../README.md).
2. Click the **Open in Colab** badge next to the lesson you want.
3. Run the cells from top to bottom with `Shift + Enter`.

The first cell of every notebook installs anything Colab is missing. That takes
about a minute for the lessons that use PyDESeq2 (S4 and S5) and no time at all
for the others.

Every notebook is self-contained: it downloads the data it needs directly from
this repository, and no lesson depends on you having run a previous one. You can
open S5 without having opened S4.

**Two things to know about Colab:**

- Your changes are not saved back to this repository. Use *File → Save a copy in
  Drive* to keep your work.
- If a session sits idle too long it disconnects and you lose the variables. Just
  re-run the notebook from the top.

---

## Option 2 — A virtual environment (recommended for local work)

You need Python 3.10 or newer. Check with `python3 --version`.

```bash
git clone https://github.com/enriquea/ZebraQ.git
cd ZebraQ

python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate

pip install -r setup/python/requirements.txt

jupyter lab
```

Then open any notebook in `lessons-py/`.

To leave the environment later, run `deactivate`.

---

## Option 3 — conda

```bash
git clone https://github.com/enriquea/ZebraQ.git
cd ZebraQ

conda env create -f setup/python/environment.yml
conda activate zebraq-py

jupyter lab
```

---

## Checking it worked

Run this in a Python shell or a notebook cell:

```python
import pandas, numpy, matplotlib, seaborn, scipy, sklearn, pydeseq2
print("pandas  ", pandas.__version__)
print("numpy   ", numpy.__version__)
print("pydeseq2", pydeseq2.__version__)
```

If that runs without an error, you are ready.

---

## Troubleshooting

**`ModuleNotFoundError` even though pip said it installed.**
Your notebook is probably using a different Python than the one you installed
into. Check with:

```python
import sys; print(sys.executable)
```

If that is not the Python inside your `.venv`, register the environment as a
kernel and select it in Jupyter:

```bash
python -m ipykernel install --user --name zebraq-py --display-name "ZebraQ (Python)"
```

**PyDESeq2 fails to install.**
It needs Python 3.10 or newer. On older versions pip will either fail outright or
silently install an ancient release whose API does not match these lessons.

**A notebook cannot find the data files.**
Run Jupyter from the repository root, and open notebooks from `lessons-py/`. The
notebooks look for `../data/`, and fall back to downloading from GitHub if that
path does not exist — so an unexpected download usually means your working
directory is wrong.

**Plots do not appear.**
Make sure you are in Jupyter and not a plain Python shell. If a figure still does
not render, add `%matplotlib inline` at the top of the notebook.

---

## Which package replaces which R package

| R / Bioconductor | Python |
| --- | --- |
| base vectors, lists | `list`, `dict`, `tuple`, `set` |
| matrix, array | `numpy` |
| data.frame, dplyr, tidyr | `pandas` |
| factor | `pandas.Categorical` |
| ggplot2 | `matplotlib` + `seaborn` |
| ggpubr | `scipy.stats` + manual annotation |
| readxl, openxlsx | `pandas` + `openpyxl` |
| microbenchmark | `%timeit` |
| **DESeq2** | **PyDESeq2** |
| EnhancedVolcano | `matplotlib` + `adjustText` |
| pheatmap | `seaborn.clustermap` |
| `sessionInfo()` | `session_info.show()` |
