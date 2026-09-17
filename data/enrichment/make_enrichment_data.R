# ---------------------------------------------------------------------------
# make_enrichment_data.R
#
# Regenerates every file in data/enrichment/.
#
# The S6 and S7 lessons retrieve these results from FishEnrichr, Enrichr,
# Ensembl and STRING. Because these services are not always reachable, the
# lessons fall back to the copies written by this script.
#
# Run from the project root:   Rscript data/enrichment/make_enrichment_data.R
#
# Needs dplyr, readr, httr and jsonlite (biomaRt is optional: it is tried first
# and skipped if missing).
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

# Thresholds used in S6 and S7. These differ from the volcano plot cutoffs in S5
# (pvalue < 0.001, |lfc| > 2.5), which only control the labelled points.
PADJ_MAX <- 0.05
LFC_MIN  <- 1

message("== 1. gene lists ==")

res <- read_tsv(RES, show_col_types = FALSE)
de  <- res %>% filter(!is.na(padj), padj < PADJ_MAX, abs(log2FoldChange) > LFC_MIN)

# method = "radix" sorts independently of the locale, so the output files are
# identical when regenerated on another machine.
genes_up   <- sort(de$gene[de$log2FoldChange > 0], method = "radix")
genes_down <- sort(de$gene[de$log2FoldChange < 0], method = "radix")

writeLines(genes_up,   file.path(OUT, "genes_up.txt"))
writeLines(genes_down, file.path(OUT, "genes_down.txt"))
message("   up: ", length(genes_up), "   down: ", length(genes_down))

# ---------------------------------------------------------------------------
# Enrichr / FishEnrichr
#
# Two calls: POST the gene list, then GET the results table for one library.
# FishEnrichr and Enrichr share the same API, so these functions serve both.
# ---------------------------------------------------------------------------

# Enrichr limits the request rate (HTTP 429). Retry with an increasing pause.
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

# A service can return HTTP 200 with an error page instead of a table, so check
# that the expected columns are present.
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
# biomaRt (used in S7) is tried first. It requires a connection to Ensembl and
# valid SSL certificates, and failed on R 4.1.3 with "SSL certificate problem:
# certificate has expired".
#
# The fallback requests the same four attributes from the BioMart REST service
# with httr (HTTPS), bypassing biomaRt.
#
# Ensembl moves this endpoint. www.ensembl.org answers with a 308 redirect to a
# dated archive host (jun2026.archive.ensembl.org at the time of writing), and
# the regional mirrors have started returning 403 for it. So rather than naming
# a host, read the redirect to find the current one and fall back to a list.
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

# Ensembl has begun rejecting requests that carry libcurl's default user agent:
# the regional mirrors answer those with HTTP 403 and the same request with a
# browser user agent with HTTP 200. Sending one is therefore not cosmetic here.
BIOMART_UA <- user_agent(
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36")

# Hosts to try, in order. www.ensembl.org currently redirects this endpoint to a
# dated archive host, so ask it where it is pointing and try that first; the
# archive name changes with each Ensembl release, which is why it is discovered
# rather than hard-coded.
biomart_hosts <- function() {
  redirected <- tryCatch({
    r <- GET("https://www.ensembl.org/biomart/martservice",
             query = list(type = "registry", requestid = "biomaRt"),
             BIOMART_UA, config(followlocation = FALSE))
    loc <- headers(r)[["location"]]
    if (is.null(loc)) NULL else sub("^(https?://[^/]+).*$", "\\1", loc)
  }, error = function(e) NULL)

  unique(c(redirected,
           "https://useast.ensembl.org",
           "https://asia.ensembl.org",
           "https://www.ensembl.org"))
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
  for (host in biomart_hosts()) {
    tb <- tryCatch({
      r <- GET(paste0(host, "/biomart/martservice"), query = list(query = query),
               BIOMART_UA)
      stop_for_status(r)
      txt <- content(r, "text", encoding = "UTF-8")
      if (grepl("Query ERROR|<html|\\{\"status_code\"", txt, ignore.case = TRUE)) {
        stop("error page, not a table", call. = FALSE)
      }
      out <- read_tsv(txt, show_col_types = FALSE)
      if (ncol(out) != 4) {
        stop(sprintf("returned %d columns, expected 4", ncol(out)), call. = FALSE)
      }
      out
    }, error = function(e) {
      message("   ", host, ": ", conditionMessage(e))
      NULL
    })
    if (!is.null(tb)) {
      message("   using ", host)
      return(tb)
    }
  }
  stop("no Ensembl BioMart host answered with a table", call. = FALSE)
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
  # n_distinct rather than n(): the same (fish, human) pair can appear twice
  # with different confidence values, which would otherwise count as two.
  mutate(n_human_partners = n_distinct(human_symbol)) %>%
  ungroup() %>%
  arrange(zfish_symbol, human_symbol)

write_tsv(orth, file.path(OUT, "zfish_human_orthologs.tsv"))
message("   ", nrow(orth), " pairs for ", n_distinct(orth$zfish_symbol), " zebrafish genes")

# The filter the lessons use.
#
# Keep zebrafish genes with exactly one human ortholog (n_human_partners == 1).
#
# Ensembl's `ortholog_one2one` label is not used: because of the teleost genome
# duplication, genes such as serpinh1b and col1a1a are labelled one2many although
# each maps to a single human gene (SERPINH1, COL1A1).
#
# Several zebrafish genes may map to the same human gene; only unique human
# symbols are kept, so this cannot inflate a gene set.
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

# Unfiltered mapping, used in S7 section 6 for comparison. Here one zebrafish
# gene, mt2, maps to 12 human metallothioneins.
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
# One GET returns the interactions among the submitted genes.
# ---------------------------------------------------------------------------

message("== 6. STRING network ==")
string_network <- function(genes, species = 9606) {
  r <- GET("https://string-db.org/api/tsv/network",
           query = list(identifiers = paste(genes, collapse = "\r"),
                        species = species))
  stop_for_status(r)
  tb <- read_tsv(content(r, "text", encoding = "UTF-8"), show_col_types = FALSE)
  require_columns(tb, c("preferredName_A", "preferredName_B", "score"), "STRING")
}

edges <- string_network(human_down)
write_tsv(edges, file.path(OUT, "string_edges_human_down.tsv"))
message("   ", nrow(edges), " edges among ", length(human_down), " genes")

message("\nDone. Files written to ", OUT, "/")
