# Phase 2: download EIA-861M (monthly, utility-level residential sales/customers --
# the outcome data). Downloads to data/raw/eia861m/, logs to data/raw/MANIFEST.csv.
# Run from the repo root (~/thesis). Idempotent: skips a year already on disk.
#
# The EIA-861M archive changed its filename convention TWICE across 2015-2024:
#   2015-2016: f826YYYY.xls          (the old EIA form number)
#   2017-2020: retail_sales_YYYY.xlsx
#   2021-2024: sales_ult_cust_YYYY.xlsx
# All three were checked by hand and have IDENTICAL internal structure: sheets
# "Sales Ultimate Cust. -States" / "-Territory", a 2-row banner then the real
# header (skip = 2), same column layout throughout.
#
# "sales_revenue.xlsx" (also on the landing page) is a DIFFERENT, decoy product:
# state-level aggregates back to 1990, no Utility Number / Ownership columns.
# Do not use it here.

library(digest)
library(readxl)
library(dplyr)

if (!file.exists("data/raw/MANIFEST.csv") && !dir.exists("data/raw"))
  stop("Run from the repo root (~/thesis).")

YEARS    <- 2015:2024
RAW_M    <- "data/raw/eia861m"
MANIFEST <- "data/raw/MANIFEST.csv"
dir.create(RAW_M, recursive = TRUE, showWarnings = FALSE)

append_manifest <- function(source, url, path, notes = "") {
  row <- data.frame(source = source, url = url, local_path = path,
                    downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                    sha256 = digest(path, algo = "sha256", file = TRUE),
                    notes = notes)
  write.table(row, MANIFEST, sep = ",", row.names = FALSE,
              col.names = !file.exists(MANIFEST),
              append = file.exists(MANIFEST))
}

m861_filename <- function(y) {
  if (y <= 2016)      sprintf("f826%d.xls", y)
  else if (y <= 2020) sprintf("retail_sales_%d.xlsx", y)
  else                sprintf("sales_ult_cust_%d.xlsx", y)
}

m861_candidate_urls <- function(y) {
  fname <- m861_filename(y)
  base  <- "https://www.eia.gov/electricity/data/eia861m"
  c(sprintf("%s/archive/xls/%s", base, fname),
    sprintf("%s/xls/%s", base, fname))    # fallback: current (not-yet-archived) year
}

# EIA's own ".xls" extension is sometimes a lie -- e.g. the file served as
# f8262016.xls is actually xlsx (zip-based) content. readxl picks its parser
# by extension, so a mismatch makes it fail with a cryptic "libxls" error.
# Sniff the real signature and rename to match before we ever try to read it.
detect_true_extension <- function(path) {
  con <- file(path, "rb"); sig <- readBin(con, "raw", n = 2); close(con)
  if (identical(as.integer(sig), c(0x50L, 0x4bL))) "xlsx" else "xls"   # 'PK' = zip = xlsx
}

# The file may have been renamed to its true extension on a previous run.
m861_path_for_year <- function(y) {
  base <- sub("\\.[^.]+$", "", m861_filename(y))
  matches <- Sys.glob(file.path(RAW_M, paste0(base, ".*")))
  if (length(matches) == 0) NA_character_ else matches[1]
}

get_861m_year <- function(y, force = FALSE) {
  existing <- m861_path_for_year(y)
  if (!is.na(existing) && !force) { message(y, ": already have it, skipping"); return(invisible(existing)) }

  dest <- file.path(RAW_M, m861_filename(y))
  for (url in m861_candidate_urls(y)) {
    ok <- tryCatch({ download.file(url, dest, mode = "wb", quiet = TRUE); TRUE },
                   error = function(e) FALSE)
    if (ok && file.exists(dest) && file.info(dest)$size > 5e5) {
      true_ext <- detect_true_extension(dest)
      final <- sub("\\.[^.]+$", paste0(".", true_ext), dest)
      renamed <- final != dest
      if (renamed) file.rename(dest, final)
      append_manifest("EIA-861M monthly", url, final,
                       notes = if (renamed) sprintf("server extension (.%s) did not match content; renamed to .%s",
                                                     tools::file_ext(dest), true_ext)
                               else "")
      message(y, ": downloaded (", round(file.info(final)$size / 1e6, 1), " MB)",
              if (renamed) paste0(" [renamed to ", basename(final), "]") else "")
      return(invisible(final))
    }
    if (file.exists(dest)) file.remove(dest)   # delete the failed/tiny attempt
  }
  warning(y, ": all URLs failed")
  invisible(NULL)
}

for (y in YEARS) { get_861m_year(y); Sys.sleep(1) }

# ---- Validation: fail loudly if any year is missing -------------------------
got <- vapply(YEARS, function(y) !is.na(m861_path_for_year(y)), logical(1))
if (!all(got)) stop("Missing 861M files for: ", paste(YEARS[!got], collapse = ", "))
message("\nAll ", length(YEARS), " years of EIA-861M present in ", RAW_M)
