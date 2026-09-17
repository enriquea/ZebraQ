# ---------------------------------------------------------------------------
# make_enrichment_data.R
#
# Regenerates every file in data/enrichment/.
#
# The S6 and S7 lessons ask students to fetch these results themselves, from
# FishEnrichr, Ensembl and STRING. Those are live services: they go down, they
# time out, and university networks block them. The files this script writes are
# the committed copies the lessons fall back on so that a failed download never
# stops the class.
#
# Run from the project root:   Rscript data/enrichment/make_enrichment_data.R
#
# Everything here is deliberately plain base R + httr. It is meant to be read.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(httr)
  library(jsonlite)
})

OUT <- "data/enrichment"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

RES <- "results/DESeq2_results.tsv"

# Thresholds used throughout S6 and S7. Deliberately NOT the volcano cutoffs
# from S5 (padj < 0.001, |lfc| > 2.5): those exist to keep the plot labels
# readable, which is a different job from choosing genes for enrichment.
PADJ_MAX <- 0.05
LFC_MIN  <- 1

message("== 1. gene lists ==")

res <- read_tsv(RES, show_col_types = FALSE)
de  <- res %>% filter(!is.na(padj), padj < PADJ_MAX, abs(log2FoldChange) > LFC_MIN)

# method = "radix" sorts by byte value, independently of the machine's locale.
# Plain sort() collates differently under C and en_US.UTF-8, so regenerating
# these files elsewhere would produce a whole-file diff and nothing else.
genes_up   <- sort(de$gene[de$log2FoldChange > 0], method = "radix")
genes_down <- sort(de$gene[de$log2FoldChange < 0], method = "radix")

writeLines(genes_up,   file.path(OUT, "genes_up.txt"))
writeLines(genes_down, file.path(OUT, "genes_down.txt"))
message("   up: ", length(genes_up), "   down: ", length(genes_down))

# ---------------------------------------------------------------------------
# Enrichr / FishEnrichr
#
# Two calls: POST the gene list, then GET the results table for one library.
# FishEnrichr and Enrichr are the same software on different URLs, so one pair
# of functions serves both.
# ---------------------------------------------------------------------------

# Enrichr rate-limits. A whole classroom submitting at once will meet HTTP 429,
# and so will this script if it runs its calls back to back. Retry with a
# widening pause rather than falling over.
with_retry <- function(fn, tries = 5, wait = 3) {
  for (i in seq_len(tries)) {
    r <- tryCatch(fn(), error = function(e) e)
    if (!inherits(r, "error")) return(r)
    if (i == tries) stop(r)
    message("      retry ", i, "/", tries - 1, " after ", wait, "s (", conditionMessage(r), ")")
    Sys.sleep(wait)
    wait <- wait * 2
  }
}

enrichr_submit <- function(genes, base) {
  r <- POST(paste0(base, "/addList"),
            body = list(list = paste(genes, collapse = "\n"), description = "ZebraQ"),
            encode = "multipart")
  stop_for_status(r)
  # The server sends JSON but labels it text/html, so httr would hand back an
  # XML document if we let it guess. Parse the body ourselves.
  jsonlite::fromJSON(content(r, "text", encoding = "UTF-8"))$userListId
}

# Enrichr and BioMart both answer a bad request, a maintenance page or a captive
# portal with HTTP 200 and an HTML body, so the status code alone proves nothing.
# Check that the columns we rely on actually arrived.
require_columns <- function(tb, needed, what) {
  missing <- setdiff(needed, names(tb))
  if (length(missing)) {
    stop(sprintf("%s did not return %s (got: %s)",
                 what, paste(missing, collapse = ", "),
                 paste(utils::head(names(tb), 4), collapse = ", ")),
         call. = FALSE)
  }
  tb
}

enrichr_table <- function(list_id, library, base) {
  url <- sprintf("%s/export?userListId=%s&filename=x&backgroundType=%s",
                 base, list_id, library)
  r <- GET(url)
  stop_for_status(r)
  tb <- read_tsv(content(r, "text", encoding = "UTF-8"), show_col_types = FALSE)
  require_columns(tb, c("Term", "Overlap", "Adjusted P-value", "Genes"),
                  paste("Enrichr", library))
}

enrich <- function(genes, library, base, outfile) {
  id <- with_retry(function() enrichr_submit(genes, base))
  Sys.sleep(1)
  tb <- with_retry(function() enrichr_table(id, library, base))
  Sys.sleep(1)
  write_tsv(tb, file.path(OUT, outfile))
  n <- sum(tb$`Adjusted P-value` < 0.05)
  message(sprintf("   %-42s %4d terms, %3d significant", outfile, nrow(tb), n))
  invisible(tb)
}

FISH  <- "https://maayanlab.cloud/FishEnrichr"
HUMAN <- "https://maayanlab.cloud/Enrichr"

message("== 2. zebrafish enrichment (FishEnrichr) ==")
enrich(genes_up,   "GO_Biological_Process_2018", FISH, "fish_GO_BP_2018_up.tsv")
enrich(genes_down, "GO_Biological_Process_2018", FISH, "fish_GO_BP_2018_down.tsv")
enrich(genes_down, "KEGG_2019",                  FISH, "fish_KEGG_2019_down.tsv")

# ---------------------------------------------------------------------------
# Orthologs
#
# biomaRt is what the S7 lesson teaches, so it is what we try first. It depends
# on a live Ensembl connection and on the machine's TLS certificates being
# current, and it does fail: during course development it died with
# "SSL certificate problem: certificate has expired" on R 4.1.3.
#
# The fallback asks the same Ensembl BioMart for the same four attributes over
# plain HTTP. Note the mirror: www.ensembl.org answers this URL with a 308
# redirect, useast.ensembl.org answers it with data.
# ---------------------------------------------------------------------------

message("== 3. orthologs ==")

orthologs_biomart <- function() {
  if (!requireNamespace("biomaRt", quietly = TRUE)) stop("biomaRt not installed")
  mart <- biomaRt::useEnsembl("genes", "drerio_gene_ensembl")
  biomaRt::getBM(
    attributes = c("external_gene_name",
                   "hsapiens_homolog_associated_gene_name",
                   "hsapiens_homolog_orthology_type",
                   "hsapiens_homolog_orthology_confidence"),
    mart = mart)
}

orthologs_rest <- function() {
  query <- paste0(
    '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE Query>',
    '<Query virtualSchemaName="default" formatter="TSV" header="1" uniqueRows="1" ',
    'count="" datasetConfigVersion="0.6">',
    '<Dataset name="drerio_gene_ensembl" interface="default">',
    '<Attribute name="external_gene_name"/>',
    '<Attribute name="hsapiens_homolog_associated_gene_name"/>',
    '<Attribute name="hsapiens_homolog_orthology_type"/>',
    '<Attribute name="hsapiens_homolog_orthology_confidence"/>',
    '</Dataset></Query>')
  r <- GET("https://useast.ensembl.org/biomart/martservice",
           query = list(query = query))
  stop_for_status(r)
  txt <- content(r, "text", encoding = "UTF-8")
  if (grepl("Query ERROR|<html", txt, ignore.case = TRUE)) {
    stop("BioMart returned an error page, not a table", call. = FALSE)
  }
  tb <- read_tsv(txt, show_col_types = FALSE)
  if (ncol(tb) != 4) {
    stop(sprintf("BioMart returned %d columns, expected 4", ncol(tb)), call. = FALSE)
  }
  tb
}

orth_raw <- tryCatch({
  message("   trying biomaRt ...")
  orthologs_biomart()
}, error = function(e) {
  message("   biomaRt failed (", conditionMessage(e), ")")
  message("   falling back to the BioMart REST service ...")
  orthologs_rest()
})

names(orth_raw) <- c("zfish_symbol", "human_symbol", "orthology_type", "confidence")

orth <- orth_raw %>%
  filter(!is.na(zfish_symbol), zfish_symbol != "",
         !is.na(human_symbol),  human_symbol  != "") %>%
  distinct() %>%
  filter(zfish_symbol %in% res$gene) %>%          # only genes this experiment measured
  group_by(zfish_symbol) %>%
  # n_distinct, not n(): distinct() above dedupes on all four columns, so the
  # same (fish, human) pair reported twice with different confidence survives as
  # two rows. Counting rows would then mark an unambiguous gene as ambiguous and
  # silently drop it -- exactly the failure S7 section 4 teaches against.
  mutate(n_human_partners = n_distinct(human_symbol)) %>%
  ungroup() %>%
  arrange(zfish_symbol, human_symbol)

write_tsv(orth, file.path(OUT, "zfish_human_orthologs.tsv"))
message("   ", nrow(orth), " pairs for ", n_distinct(orth$zfish_symbol), " zebrafish genes")

# The filter the lessons use.
#
# "1:1" has to mean "unambiguous in the direction we are travelling": one
# zebrafish gene, one human gene. That is n_human_partners == 1.
#
# Ensembl's own `ortholog_one2one` label is stricter and, for a zebrafish study,
# wrong: the teleost genome duplication means serpinh1b and col1a1a are both
# labelled one2many even though each maps to exactly one human gene (SERPINH1,
# COL1A1). The "many" is on the fish side. Using the label would silently throw
# away serpinh1b, which has the third smallest adjusted p-value of the 354
# up-regulated genes.
#
# Many fish genes mapping onto the same human gene (col1a1a and col1a1b both
# give COL1A1) is harmless here: we take unique human symbols, so a gene set can
# only shrink, never inflate.
unambiguous <- orth %>% filter(n_human_partners == 1)

to_human <- function(fish_genes, table) {
  sort(unique(table$human_symbol[table$zfish_symbol %in% fish_genes]),
       method = "radix")
}

human_up   <- to_human(genes_up,   unambiguous)
human_down <- to_human(genes_down, unambiguous)

writeLines(human_up,   file.path(OUT, "genes_up_human.txt"))
writeLines(human_down, file.path(OUT, "genes_down_human.txt"))
message("   unambiguous -> human:  up ", length(human_up), "   down ", length(human_down))

# The counter-example for the S7 appraisal exercise: every ortholog, no filter.
# One zebrafish gene, mt2, carries 12 human metallothioneins into the list on
# its own, and manufactures a "cellular response to zinc ion" hit at 1e-19.
human_up_all <- to_human(genes_up, orth)
writeLines(human_up_all, file.path(OUT, "genes_up_human_ALLORTHO.txt"))
message("   unfiltered  -> human:  up ", length(human_up_all), " (for the artifact demo)")

message("== 4. human enrichment (Enrichr) ==")
enrich(human_up,   "GO_Biological_Process_2025", HUMAN, "human_GO_BP_2025_up.tsv")
enrich(human_down, "GO_Biological_Process_2025", HUMAN, "human_GO_BP_2025_down.tsv")
enrich(human_down, "Reactome_Pathways_2024",     HUMAN, "human_Reactome_2024_down.tsv")
enrich(human_up_all, "GO_Biological_Process_2025", HUMAN, "human_GO_BP_2025_up_ALLORTHO.tsv")

message("== 5. the same list against four GO releases ==")
for (year in c("2021", "2023", "2026")) {
  enrich(human_up, paste0("GO_Biological_Process_", year), HUMAN,
         paste0("human_GO_BP_", year, "_up.tsv"))
}
# 2025 was written above; the lesson reads all four together.

# ---------------------------------------------------------------------------
# STRING
#
# One GET returns the network edges among the submitted genes. The lesson uses
# the website for the picture and this table for the numbers.
# ---------------------------------------------------------------------------

message("== 6. STRING network ==")
string_network <- function(genes, species = 9606) {
  r <- GET("https://string-db.org/api/tsv/network",
           query = list(identifiers = paste(genes, collapse = "\r"),
                        species = species))
  stop_for_status(r)
  read_tsv(content(r, "text", encoding = "UTF-8"), show_col_types = FALSE)
}

edges <- string_network(human_down)
write_tsv(edges, file.path(OUT, "string_edges_human_down.tsv"))
message("   ", nrow(edges), " edges among ", length(human_down), " genes")

message("\nDone. Files written to ", OUT, "/")
