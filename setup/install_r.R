#!/usr/bin/env Rscript
#
# ZebraQ - R track setup
# =====================
#
# Installs every package the R lessons need, as PREBUILT BINARIES, at versions
# frozen to a fixed date, so that every laptop on the course ends up with the
# same thing regardless of operating system or chip.
#
# Run it either way:
#     Rscript setup/install_r.R
#     source("setup/install_r.R")        # from inside RStudio
#
# Why not plain install.packages()? Two reasons, both of which cause the
# failures people hit on their own machines:
#
#   1. Without a pinned date, everyone gets whatever CRAN published today, so
#      the course drifts apart from itself over a semester.
#   2. With pkgType = "both" (the R default on macOS and Windows), R offers to
#      build from source whenever the source version is newer than the binary.
#      Saying yes needs a compiler toolchain - Rtools on Windows, the Xcode
#      command line tools on macOS - which most people do not have. Forcing
#      "binary" removes the question entirely.

## ---------------------------------------------------------------- pinned ---
## Bioconductor 3.23 requires R 4.6.x. Change these three together, never one
## on its own, and re-knit the lessons afterwards.
R_SERIES <- "4.6"
BIOC_VERSION <- "3.23"
CRAN_SNAPSHOT <- "2026-09-01"

CRAN_BASE <- "https://packagemanager.posit.co/cran"

CRAN_PKGS <- c(
  "ggplot2", "ggpubr", "dplyr", "RColorBrewer",
  "readxl", "openxlsx", "pheatmap", "matrixStats", "microbenchmark"
)
BIOC_PKGS <- c("DESeq2", "EnhancedVolcano")

## ------------------------------------------------------------ R version ---
current <- paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1]][1], sep = ".")
if (current != R_SERIES) {
  message(sprintf(paste0(
    "\n  This course is pinned to R %s (Bioconductor %s).\n",
    "  You are running R %s.\n\n",
    "  Bioconductor %s will not install on R %s, so please install R %s.x from\n",
    "    https://cran.r-project.org\n",
    "  and select it in RStudio under Tools > Global Options > General.\n"),
    R_SERIES, BIOC_VERSION, current, BIOC_VERSION, current, R_SERIES))
  stop("wrong R version", call. = FALSE)
}

## ------------------------------------------------------------- repository ---
## Posit Package Manager serves prebuilt binaries for Windows and macOS (Intel
## and Apple Silicon), and - unlike CRAN - for Linux too. Pointing at a dated
## snapshot rather than "latest" is what makes the install reproducible.
os <- tolower(Sys.info()[["sysname"]])

if (os == "linux") {
  # On Linux, P3M serves binaries from a distribution-specific path and R
  # installs them through the "source" code path, so pkgType stays "source".
  codename <- tryCatch({
    rel <- readLines("/etc/os-release", warn = FALSE)
    sub('^VERSION_CODENAME=', "", grep("^VERSION_CODENAME=", rel, value = TRUE)[1])
  }, error = function(e) NA_character_)

  if (is.na(codename) || !nzchar(codename)) {
    message("  Could not detect the Linux release; falling back to source packages.")
    repo <- file.path(CRAN_BASE, CRAN_SNAPSHOT)
  } else {
    repo <- file.path(CRAN_BASE, "__linux__", codename, CRAN_SNAPSHOT)
    message(sprintf("  Linux detected (%s): using prebuilt binaries.", codename))
  }
  options(repos = c(CRAN = repo), pkgType = "source")
} else {
  options(repos = c(CRAN = file.path(CRAN_BASE, CRAN_SNAPSHOT)), pkgType = "binary")
}

message(sprintf("  R %s | Bioconductor %s | CRAN snapshot %s",
                current, BIOC_VERSION, CRAN_SNAPSHOT))
message(sprintf("  repository: %s\n", getOption("repos")[["CRAN"]]))

## ---------------------------------------------------------------- install ---
install_missing <- function(pkgs, installer) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (!length(missing)) {
    message("  already present: ", paste(pkgs, collapse = ", "))
    return(invisible(NULL))
  }
  message("  installing: ", paste(missing, collapse = ", "))
  installer(missing)
}

install_missing(c("BiocManager", CRAN_PKGS),
                function(p) install.packages(p, quiet = TRUE))

BiocManager::install(version = BIOC_VERSION, ask = FALSE, update = FALSE)
install_missing(BIOC_PKGS,
                function(p) BiocManager::install(p, ask = FALSE, update = FALSE))

## ----------------------------------------------------------------- verify ---
## Report rather than assume. A package that failed to install is worth seeing
## now, not halfway through a lesson.
message("\n  installed versions")
all_pkgs <- c(CRAN_PKGS, BIOC_PKGS)
failed <- character(0)
for (p in all_pkgs) {
  v <- tryCatch(as.character(packageVersion(p)), error = function(e) NA_character_)
  if (is.na(v)) failed <- c(failed, p)
  message(sprintf("    %-18s %s", p, ifelse(is.na(v), "FAILED", v)))
}

if (length(failed)) {
  stop(sprintf("\n  %d package(s) did not install: %s\n",
               length(failed), paste(failed, collapse = ", ")), call. = FALSE)
}
message("\n  All set. Open ZebraQ.Rproj in RStudio and start with lessons-r/S1.\n")
