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
#     source("setup/install_r.R")        # from inside RStudio, with the
#                                        # ZebraQ.Rproj project open
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
## The course is built and tested on R 4.6 with Bioconductor 3.23. If you are on
## an older R the script still works, but it has to use the Bioconductor release
## that matches your R - that pairing is fixed by Bioconductor, not by us - so
## you will get older analysis packages. It will tell you when that happens.
PREFERRED_R <- "4.6"

## R series -> newest stable Bioconductor release for it.
BIOC_FOR_R <- c("4.1" = "3.14", "4.2" = "3.16", "4.3" = "3.18",
                "4.4" = "3.20", "4.5" = "3.22", "4.6" = "3.23")

CRAN_SNAPSHOT <- "2026-09-01"
CRAN_BASE <- "https://packagemanager.posit.co/cran"

## tidyverse is required by lessons-r/S6 (which also uses readr::, pulled in by
## tidyverse). Keep this list in step with the library() calls in lessons-r/.
CRAN_PKGS <- c(
  "tidyverse", "ggplot2", "ggpubr", "dplyr", "RColorBrewer",
  "readxl", "openxlsx", "pheatmap", "matrixStats", "microbenchmark"
)
BIOC_PKGS <- c("DESeq2", "EnhancedVolcano")

## ------------------------------------------------------------ R version ---
current <- paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1]][1], sep = ".")

if (!current %in% names(BIOC_FOR_R)) {
  message(sprintf(paste0(
    "\n  You are running R %s, which this course cannot install for.\n",
    "  Supported: R %s. Please install R %s.x from https://cran.r-project.org\n",
    "  and select it in RStudio under Tools > Global Options > General.\n"),
    current, paste(names(BIOC_FOR_R), collapse = ", "), PREFERRED_R))
  stop("unsupported R version", call. = FALSE)
}

BIOC_VERSION <- unname(BIOC_FOR_R[current])

if (current != PREFERRED_R) {
  message(sprintf(paste0(
    "\n  ----------------------------------------------------------------\n",
    "  You are on R %s, so you will get Bioconductor %s.\n",
    "  The lessons were written against R %s / Bioconductor %s.\n\n",
    "  Everything will install and run, but some results and plots may\n",
    "  differ from the committed outputs - DESeq2 in particular moves a\n",
    "  long way between these releases. If you can install R %s, do.\n",
    "  Both versions can sit side by side; you switch in RStudio under\n",
    "  Tools > Global Options > General.\n",
    "  ----------------------------------------------------------------\n"),
    current, BIOC_VERSION, PREFERRED_R, unname(BIOC_FOR_R[PREFERRED_R]), PREFERRED_R))
}

## ------------------------------------------------------------- repository ---
## Posit Package Manager serves prebuilt binaries for Windows and macOS (Intel
## and Apple Silicon), and - unlike CRAN - for Linux too. Pointing at a dated
## snapshot rather than "latest" is what makes the install reproducible.
##
## On Linux, P3M decides whether to hand back a binary or a source tarball by
## reading the User-Agent. R's own default is discarded by its libcurl code
## (anything starting with "R (" is dropped), so without the line below every
## Linux install silently falls back to compiling from source - exactly what
## this script exists to avoid. This is Posit's documented workaround.
options(HTTPUserAgent = sprintf(
  "R/%s R (%s)", getRversion(),
  paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])
))

snapshot_repo <- file.path(CRAN_BASE, CRAN_SNAPSHOT)
os <- tolower(Sys.info()[["sysname"]])

## How many packages does the current repo setting actually offer? Used to tell
## a working configuration from one that resolves to an empty index.
n_available <- function() {
  suppressWarnings(tryCatch(nrow(available.packages()), error = function(e) 0L))
}

if (os == "linux") {
  # /etc/os-release permits the value to be quoted, and sub() alone would leave
  # the quotes in the URL.
  codename <- tryCatch({
    rel <- readLines("/etc/os-release", warn = FALSE)
    hit <- grep("^VERSION_CODENAME=", rel, value = TRUE)[1]
    if (is.na(hit)) NA_character_ else gsub('^"|"$|^\'|\'$', "", sub("^VERSION_CODENAME=", "", hit))
  }, error = function(e) NA_character_)

  # P3M only builds for the distributions it supports. Rather than trust the
  # codename, set the URL and check that it returns a populated index; fall
  # back to the plain snapshot (source packages) if it does not.
  if (!is.na(codename) && nzchar(codename)) {
    options(repos = c(CRAN = file.path(CRAN_BASE, "__linux__", codename, CRAN_SNAPSHOT)),
            pkgType = "source")
    if (n_available() < 1000) {
      message(sprintf(paste0(
        "  Posit Package Manager has no binary build for '%s'.\n",
        "  Falling back to source packages - installing will take longer and\n",
        "  needs a compiler (build-essential / gcc-c++ and gfortran).\n"), codename))
      options(repos = c(CRAN = snapshot_repo))
    } else {
      message(sprintf("  Linux detected (%s): using prebuilt binaries.", codename))
    }
  } else {
    message("  Could not detect the Linux release; falling back to source packages.")
    options(repos = c(CRAN = snapshot_repo), pkgType = "source")
  }
} else {
  options(repos = c(CRAN = snapshot_repo), pkgType = "binary")
}

message(sprintf("  R %s | Bioconductor %s | CRAN snapshot %s",
                current, BIOC_VERSION, CRAN_SNAPSHOT))
message(sprintf("  repository: %s\n", getOption("repos")[["CRAN"]]))

## Not every R version has prebuilt binaries for every platform - CRAN retires
## old ones. Warn up front rather than letting the student discover it when a
## compile fails halfway through.
avail <- suppressWarnings(tryCatch(available.packages(), error = function(e) NULL))
if (is.null(avail) || nrow(avail) < 1000) {
  message(sprintf(paste0(
    "\n  Warning: only %s packages are available for R %s on this platform.\n",
    "  Packages may be built from source and need a compiler. Moving to\n",
    "  R %s would avoid this.\n"),
    format(if (is.null(avail)) 0L else nrow(avail), big.mark = ","), current, PREFERRED_R))
}

## ---------------------------------------------------------------- install ---
## Install a package if it is absent OR if the installed version differs from
## the one the snapshot pins. Checking only for presence - which is the obvious
## thing to write - would leave anyone with a pre-existing library on their old
## versions, i.e. exactly the students the pinning is meant to help.
installed_version <- function(p) {
  path <- suppressWarnings(system.file(package = p))
  if (!nzchar(path)) return(NA_character_)
  tryCatch(as.character(packageVersion(p)), error = function(e) NA_character_)
}

target_version <- function(p) {
  if (is.null(avail) || !p %in% rownames(avail)) return(NA_character_)
  unname(avail[p, "Version"])
}

same_version <- function(a, b) {
  # "1.1-3" and "1.1.3" are the same version; compare parsed, not as strings.
  isTRUE(tryCatch(package_version(a) == package_version(b), error = function(e) FALSE))
}

needs_install <- function(pkgs) {
  out <- character(0)
  absent <- character(0)
  for (p in pkgs) {
    have <- installed_version(p)
    want <- target_version(p)
    if (is.na(want)) absent <- c(absent, p)
    if (is.na(have)) {
      out <- c(out, p)
    } else if (!is.na(want) && !same_version(have, want)) {
      message(sprintf("    %s: have %s, snapshot pins %s - updating", p, have, want))
      out <- c(out, p)
    }
  }
  # Older R series do not have a complete binary set: CRAN stops building for
  # them as new versions arrive. Name the gaps instead of letting the install
  # fail with "package is not available".
  if (length(absent)) {
    message(sprintf(paste0(
      "\n    Note: %s not available for R %s on this platform (%s).\n",
      "    R %s has the full set.\n"),
      paste(absent, collapse = ", "), current, .Platform$pkgType, PREFERRED_R))
  }
  out
}

message("  CRAN packages")
todo <- needs_install(c("BiocManager", CRAN_PKGS))
if (length(todo)) {
  message("    installing: ", paste(todo, collapse = ", "))
  install.packages(todo, quiet = TRUE)
} else {
  message("    all present at the pinned versions")
}

## Bioconductor is pinned to a release, not to a date: BiocManager resolves
## against the live 3.x repository, which receives patch updates through the
## release cycle. Two people installing months apart can therefore differ in
## DESeq2's patch version even though every CRAN package matches. There is no
## dated Bioconductor snapshot on Posit Package Manager to point at.
message("  Bioconductor packages")
suppressMessages(BiocManager::install(version = BIOC_VERSION, ask = FALSE, update = FALSE))
bioc_todo <- BIOC_PKGS[!vapply(BIOC_PKGS, function(p) nzchar(system.file(package = p)), logical(1))]
if (length(bioc_todo)) {
  message("    installing: ", paste(bioc_todo, collapse = ", "))
  BiocManager::install(bioc_todo, ask = FALSE, update = FALSE)
} else {
  message("    all present")
}

## ----------------------------------------------------------------- verify ---
## Report rather than assume. A package that failed to install is worth seeing
## now, not halfway through a lesson.
message("\n  installed versions")
all_pkgs <- c(CRAN_PKGS, BIOC_PKGS)
failed <- character(0)
for (p in all_pkgs) {
  v <- installed_version(p)
  if (is.na(v)) failed <- c(failed, p)
  message(sprintf("    %-18s %s", p, ifelse(is.na(v), "FAILED", v)))
}

if (length(failed)) {
  stop(sprintf("\n  %d package(s) did not install: %s\n",
               length(failed), paste(failed, collapse = ", ")), call. = FALSE)
}
message("\n  All set. Open ZebraQ.Rproj in RStudio and start with lessons-r/S1.\n")
