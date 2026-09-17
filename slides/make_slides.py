#!/usr/bin/env python3
"""
make_slides.py — build the day-2 slide decks.

Three .pptx files, one per lesson, deliberately plain: white background, no
template, no logos, one idea per slide. They are meant to be projected next to
a live RStudio session, not read on their own.

Exercises follow a fixed three-slide rhythm:

    question  -> one question, large, nothing else
    hint      -> one or two nudges, small
    answer    -> the point, plus the command or number that shows it

Run from the project root:   python3 slides/make_slides.py

The script is the source of truth until you first edit a deck by hand; after
that, re-running it will overwrite your edits.
"""

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.util import Emu, Inches, Pt

OUT = Path("slides")

FONT = "Helvetica"
INK = RGBColor(0x1A, 0x1A, 0x1A)
MUTED = RGBColor(0x66, 0x66, 0x66)
ACCENT = RGBColor(0xB2, 0x18, 0x2B)
PAPER = RGBColor(0xFF, 0xFF, 0xFF)

W, H = Inches(13.333), Inches(7.5)          # 16:9
MARGIN = Inches(0.9)
BODY_W = W - 2 * MARGIN


def deck():
    prs = Presentation()
    prs.slide_width, prs.slide_height = W, H
    return prs


def blank(prs):
    """A slide with nothing on it but a white background."""
    s = prs.slides.add_slide(prs.slide_layouts[6])
    fill = s.background.fill
    fill.solid()
    fill.fore_color.rgb = PAPER
    return s


def text(slide, s, top, height, size, *, color=INK, bold=False,
         align=PP_ALIGN.LEFT, italic=False, space_after=10, left=MARGIN,
         width=None):
    box = slide.shapes.add_textbox(left, top, width or BODY_W, height)
    tf = box.text_frame
    tf.word_wrap = True
    for i, line in enumerate(s.split("\n")):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.space_after = Pt(space_after)
        run = p.add_run()
        run.text = line
        f = run.font
        f.name, f.size, f.bold, f.italic = FONT, Pt(size), bold, italic
        f.color.rgb = color
    return box


def rule(slide, top):
    """A thin accent line, used to mark answer slides."""
    line = slide.shapes.add_shape(1, MARGIN, top, Inches(1.4), Emu(22860))
    line.fill.solid()
    line.fill.fore_color.rgb = ACCENT
    line.line.fill.background()
    line.shadow.inherit = False


# --- slide kinds -----------------------------------------------------------

def title_slide(prs, title, subtitle):
    s = blank(prs)
    text(s, title, Inches(2.7), Inches(1.4), 40, bold=True)
    text(s, subtitle, Inches(4.0), Inches(1.0), 22, color=MUTED)
    return s


def section(prs, label):
    s = blank(prs)
    text(s, label, Inches(3.1), Inches(1.5), 38, bold=True)
    return s


def statement(prs, heading, body=None, *, size=30):
    s = blank(prs)
    text(s, heading, Inches(1.0), Inches(1.8), size, bold=True)
    if body:
        text(s, body, Inches(2.9), Inches(3.6), 20, color=MUTED, space_after=14)
    return s


def question(prs, q):
    s = blank(prs)
    text(s, "question", Inches(0.7), Inches(0.4), 15, color=ACCENT, bold=True)
    text(s, q, Inches(2.3), Inches(3.4), 30, bold=True, space_after=16)
    return s


def hint(prs, *hints):
    s = blank(prs)
    text(s, "hint", Inches(0.7), Inches(0.4), 15, color=MUTED, bold=True)
    text(s, "\n".join("— " + h for h in hints), Inches(2.4), Inches(3.4), 21,
         color=MUTED, space_after=18)
    return s


def answer(prs, heading, body=None, code=None):
    s = blank(prs)
    rule(s, Inches(0.85))
    text(s, heading, Inches(1.3), Inches(1.8), 26, bold=True)
    top = Inches(3.1)
    if body:
        box = text(s, body, top, Inches(2.4), 19, color=MUTED, space_after=12)
        top = Inches(5.0)
    if code:
        box = text(s, code, top, Inches(1.4), 17)
        for p in box.text_frame.paragraphs:
            for r in p.runs:
                r.font.name = "Menlo"
    return s


def save(prs, name):
    OUT.mkdir(exist_ok=True)
    path = OUT / name
    prs.save(path)
    print(f"  {path}  ({len(prs.slides.__iter__.__self__._sldIdLst)} slides)")


# --- S6 --------------------------------------------------------------------

def build_s6():
    p = deck()
    title_slide(p, "S6 — From gene lists to biology",
                "What 942 gene names are, and are not, telling you")

    statement(p, "Yesterday ended here",
              "A volcano plot. A few hundred genes that changed between mutant and wild type.\n"
              "That is a list of names.\n"
              "It is not yet a statement about biology.")

    question(p, "You have 942 gene names.\nWhat is the first thing you do with them?")
    hint(p, "You cannot read 942 gene cards one at a time",
            "What do these genes have in common, other than being on your list?",
            "Somebody has already written down what most genes do")
    answer(p, "Ask whether the list is unusually full of anything",
           "That is all enrichment analysis is. Everything else is bookkeeping.")

    statement(p, "Where a gene list can be taken",
              "NCBI Gene — what is this gene?\n"
              "Ensembl — where is it, and what is its equivalent in another species?\n"
              "ZFIN — everything zebrafish: expression, mutants, phenotypes\n"
              "UniProt — what does the protein do?\n"
              "GO — controlled vocabulary of processes and functions\n"
              "KEGG / Reactome — curated pathway maps\n"
              "STRING — which proteins interact\n"
              "Enrichr — is my list unusually full of any of the above?", size=28)

    question(p, "S5 drew the volcano with\npadj < 0.001 and |log2FC| > 2.5.\n\n"
                "Should we use the same cutoffs\nto pick genes for enrichment?")
    hint(p, "Those cutoffs keep 48 up and 55 down genes",
            "What was the volcano's cutoff actually for?",
            "What is this cutoff for?")
    answer(p, "No. Different job, different decision.",
           "The volcano's cutoffs exist so the labels stay readable on a crowded figure.\n"
           "Choosing genes for enrichment is a different question and gets its own answer.\n\n"
           "Be suspicious of any analysis that reuses a threshold without saying why.",
           "padj < 0.05  |  |log2FC| > 1      ->  354 up, 588 down")

    statement(p, "Enrichment is one question, asked ten thousand times",
              "Of my 588 genes, 21 are annotated 'extracellular matrix organization'.\n"
              "The genome has 92 such genes.\n"
              "Is 21 more than chance?\n\n"
              "Coloured balls in an urn. Thousands of tests, so the p-values need\n"
              "the same multiple-testing correction you met in S4.")

    answer(p, "The down-regulated genes: 5 terms from 918 tested",
           None,
           "extracellular matrix organization      21/92    1.8e-10\n"
           "response to light stimulus             14/84    4.5e-05\n"
           "skeletal system development           18/137    4.5e-05\n"
           "notochord morphogenesis                 6/15    5.8e-04\n"
           "cellular response to radiation          8/47    1.1e-02")

    question(p, "The up-regulated genes return nothing.\n"
                "354 genes, zero significant terms.\n\nIs that a result, or a failure?")
    hint(p, "The genes are real: strong fold changes, tiny adjusted p-values",
            "How old is FishEnrichr's GO library?",
            "Who decides what a zebrafish gene is annotated with?")
    answer(p, "Hold that thought until S7.",
           "There is more than one explanation, and they lead to different actions.")

    section(p, "Now the part most tutorials skip")

    question(p, "'cellular response to radiation', padj = 0.011.\n\n"
                "There was no radiation in this experiment.\nWhere did this come from?")
    hint(p, "Every enrichment table has a Genes column",
            "Read it",
            "opn1sw1, opn1sw2, rhol, rho, opn4a, opn1lw2, opn1mw1, bbc3")
    answer(p, "Seven opsins and a rhodopsin.",
           "Light is electromagnetic radiation, so photoreceptor genes are annotated\n"
           "to a radiation term. The statistics are correct. The label is misleading.\n\n"
           "The same genes also drive 'response to light stimulus' — one finding,\n"
           "counted twice.")

    statement(p, "Never report a GO term\nbefore reading the genes that produced it.",
              "It takes ten seconds and it is the single most useful habit in this course.", size=34)

    question(p, "These are dissected hearts at 48 hpf.\n\n"
                "Rhodopsin sits at baseMean 2,100.\ncrx sits at 2,900.\n\n"
                "Discovery, or problem?")
    hint(p, "crx is the master regulator of photoreceptor identity",
            "What tissue is definitely in the tube?",
            "Now look at per1a, per2, per3, nr1d1, npas2 — all down together")
    answer(p, "Neither set is about the mutation.",
           "The opsins tell you what tissue is in the tube: eye, or whole embryo.\n"
           "The clock genes moving together tell you the samples were collected\n"
           "at different times of day.\n\n"
           "Finding them is not the analysis failing. It is the analysis working.")

    save(p, "S6_slides.pptx")


# --- S7 --------------------------------------------------------------------

def build_s7():
    p = deck()
    title_slide(p, "S7 — Orthologs, networks\nand pathways",
                "Rescuing a gene list that enriched in nothing")

    statement(p, "Where S6 left off",
              "354 genes up. Strong fold changes. Tiny adjusted p-values.\n"
              "Zero significant GO terms.")

    question(p, "Two explanations fit.\n\n"
                "1. These genes genuinely share nothing.\n"
                "2. Nobody has written down what they do.\n\nHow would you tell them apart?")
    hint(p, "FishEnrichr's GO library is dated 2018. The human one is current.",
            "Far more money has been spent annotating human genes",
            "Most zebrafish genes have a human counterpart")
    answer(p, "Ask a database that knows more.",
           "Map the genes to their human orthologs and ask the human GO library\n"
           "the identical question.")

    statement(p, "Orthologs",
              "Two genes are orthologs if they descend from the same gene in the\n"
              "common ancestor of the two species.\n\n"
              "Zebrafish is awkward: an extra whole-genome duplication means one human\n"
              "gene often has two zebrafish copies, named a and b.\n\n"
              "Human COL1A1  ->  zebrafish col1a1a and col1a1b")

    question(p, "serpinh1b is labelled ortholog_one2many.\n\n"
                "A strict one2one filter would drop it.\nShould it?")
    hint(p, "serpinh1b maps to exactly one human gene: SERPINH1",
            "The 'many' is that SERPINH1 has two zebrafish partners, a and b",
            "Which direction are we travelling?")
    answer(p, "No. The ambiguity is on the side we are leaving.",
           "'1:1' has to mean one zebrafish gene, one human gene: n_human_partners == 1.\n\n"
           "Ensembl's one2one label would silently delete serpinh1b — the single most\n"
           "strongly induced gene in the experiment — and every other gene the teleost\n"
           "duplication touched.",
           "serpinh1b   log2FC +3.72   padj 1e-112")

    answer(p, "In zebrafish: nothing.\nIn human: the unfolded protein response.",
           "131 human genes, from 354 zebrafish ones. Fewer genes, and now a signal.\n"
           "The limit was never the statistics. It was how much had been written down.",
           "Response to Unfolded Protein     6/44    4.2e-04\n"
           "HSPA5  PDIA4  PDIA6  HSP90B1  HYOU1  UBXN10")

    question(p, "This result only appeared after\nwe transformed the data.\n\n"
                "How do you know the transformation\ndid not create it?")
    hint(p, "You need something whose answer you already know",
            "The down-regulated list already worked in zebrafish",
            "What should happen to it after the same mapping?")
    answer(p, "Run the control.",
           "The down list gave extracellular matrix organization in zebrafish.\n"
           "After mapping it gives extracellular matrix organization in human.\n\n"
           "The mapping reproduces what we already knew, so the new finding is\n"
           "more believable.")

    section(p, "How the same mapping can lie")

    question(p, "Keep every ortholog instead,\nand the up-list returns\n\n"
                "Cellular Response to Zinc Ion,  padj = 1.8e-19\n"
                "60 significant terms instead of 2.\n\nWhy is this worse, not better?")
    hint(p, "Read the genes: MT1A MT1B MT1E MT1F MT1G MT1H MT1HL1 MT1M MT1X MT2A MT3 MT4",
            "How many zebrafish genes did those twelve come from?",
            "What does a hypergeometric test assume about its genes?")
    answer(p, "One gene, mt2, became twelve.",
           "Every metallothionein entered through a single zebrafish gene. The test\n"
           "assumes independent draws, so it believed twelve independent observations.\n\n"
           "The same happens on the down side: four ugt genes expand to nineteen each\n"
           "and manufacture a steroid metabolism story.")

    statement(p, "An ortholog mapping that expands genes\nwill invent findings.",
              "Check how many partners each gene brought with it.", size=34)

    section(p, "How much does the database itself move?")

    answer(p, "The same 131 genes, four GO releases",
           None,
           "release   terms tested   significant   top term\n"
           "2021           1264            18       response to unfolded protein\n"
           "2023           1044            10       Response To Unfolded Protein\n"
           "2025           1034             2       Response to Unfolded Protein\n"
           "2026           1129            11       Response to Unfolded Protein")

    question(p, "18 significant terms in 2021.\n2 in 2025. 11 in 2026.\n\n"
                "Identical genes. Identical code.\nWhich conclusion do you trust?")
    hint(p, "Which term appears in all four rows?",
            "IRE1-mediated UPR was significant in 2021 and is gone by 2025",
            "Bone mineralization appears in 2023, vanishes, returns in 2026")
    answer(p, "The one that survives every release.",
           "Response to unfolded protein is significant in all four, even though the\n"
           "size of the GO term itself changes from 49 genes to 44 to 45.\n\n"
           "Everything else is a property of the annotation, not of your experiment.")

    statement(p, "A conclusion that survives the database version\nis robust.",
              "Re-running against another release costs one changed string.\n"
              "It is the cheapest robustness check you have.", size=32)

    statement(p, "Two more tools, one more question",
              "STRING asks whether these proteins touch each other.\n"
              "Reactome asks which curated pathway they sit in.\n\n"
              "Both take the same list. Neither replaces reading the genes.")

    question(p, "Collagens down. ER folding machinery up.\n"
                "SERPINH1 up thirteen-fold.\n\n"
                "SERPINH1 is HSP47.\nIt folds collagen, and nothing else.\n\n"
                "Write the two sentences that connect these.")
    hint(p, "What happens in a cell that cannot fold what it is trying to secrete?",
            "Which came first — is this cause, or consequence?",
            "Then: what experiment would distinguish the two?")

    save(p, "S7_slides.pptx")


# --- S8 --------------------------------------------------------------------

def build_s8():
    p = deck()
    title_slide(p, "S8 — Bonus: a dataset\nyou have never seen",
                "Human fetal heart, four chambers, GSE106118")

    statement(p, "Everything until now has been guided",
              "This is not.\n\n"
              "You have the workflow from S6, a new dataset and a different species.\n"
              "The data is already human, so no ortholog step is needed.")

    statement(p, "Two lists, deliberately different",
              "A — the 50 most highly expressed genes in the left atrium\n"
              "B — the 50 genes most specific to left atrium versus right\n\n"
              "Submit both to Enrichr, GO Biological Process 2025.")

    question(p, "Before you look:\n\nwrite down what you expect each list to return.")
    hint(p, "How many genes do the two lists even share?",
            "What are the most highly expressed genes in any human tissue?",
            "Which list could distinguish one chamber from another?")
    answer(p, "One list describes the tissue.\nThe other describes the chamber.",
           "The top-expressed list of almost any human tissue returns ribosomes,\n"
           "mitochondria and muscle contraction. It is not wrong — it is just not\n"
           "an answer to the question you asked.")

    question(p, "For the list that gave\nthe more interesting answer,\n"
                "open the Genes column of the top five terms.\n\n"
                "What would you actually defend?")
    hint(p, "Is any term driven by a single gene family?",
            "Do two or three terms rest on the same genes under different names?",
            "Is any term obviously mislabelled for this tissue?")

    statement(p, "Report the two or three findings you would defend.",
              "Then say plainly which ones you discarded, and why.\n\n"
              "That last sentence is the part that makes it science.", size=32)

    save(p, "S8_slides.pptx")


if __name__ == "__main__":
    print("building decks:")
    build_s6()
    build_s7()
    build_s8()
