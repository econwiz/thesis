# Phase 2: download the annual EIA-861 census (ownership, territory, sales),
# 2015-2024, and extract the four files the build needs from each zip.
# Downloads to data/raw/eia/, logs to data/raw/MANIFEST.csv. Idempotent: skips
# a year already on disk. Run from the repo root (~/thesis).
#
# This script only downloads and extracts. Reading these files and computing
# anything from them (ownership counts, county coverage, etc.) happens in
# scripts/02_build/00_feasibility_counts.R.

library(digest)

if (!dir.exists("data/raw"))
  stop("Run from the repo root (~/thesis).")

YEARS    <- 2015:2024
RAW      <- "data/raw/eia"
MANIFEST <- "data/raw/MANIFEST.csv"
dir.create(RAW, recursive = TRUE, showWarnings = FALSE)

# The current year lives at .../eia861/zip/; once EIA archives it, it moves to
# .../eia861/archive/zip/. Try the current-year path first, then the archive.
base <- "https://www.eia.gov/electricity/data/eia861"
candidate_urls <- function(y) c(sprintf("%s/zip/f861%d.zip", base, y),
                                sprintf("%s/archive/zip/f861%d.zip", base, y))

append_manifest <- function(source, url, path, notes = "") {
  row <- data.frame(source = source, url = url, local_path = path,
                    downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                    sha256 = digest(path, algo = "sha256", file = TRUE),
                    notes = notes)
  write.table(row, MANIFEST, sep = ",", row.names = FALSE,
              col.names = !file.exists(MANIFEST),   # header only if the file is new
              append = file.exists(MANIFEST))
}

get_year <- function(y, force = FALSE) {
  dest <- file.path(RAW, sprintf("f861%d.zip", y))
  if (file.exists(dest) && !force) { message(y, ": already have it, skipping"); return(invisible(dest)) }

  for (url in candidate_urls(y)) {
    ok <- tryCatch({ download.file(url, dest, mode = "wb", quiet = TRUE); TRUE },
                   error = function(e) FALSE)
    # EIA sometimes returns a small error page with a 200 status, so also check size
    if (ok && file.exists(dest) && file.info(dest)$size > 1e6) {
      append_manifest("EIA-861 annual", url, dest)
      message(y, ": downloaded (", round(file.info(dest)$size / 1e6, 1), " MB)")
      return(invisible(dest))
    }
    if (file.exists(dest)) file.remove(dest)   # delete the failed/tiny attempt
  }
  warning(y, ": all URLs failed")
  invisible(NULL)
}

for (y in YEARS) { get_year(y); Sys.sleep(1) }

# ---- Extract the four files the build needs ---------------------------------
# Utility_Data / Service_Territory / Sales_Ult_Cust exist every year.
# Short_Form exists every year EXCEPT 2019, when EIA folded short-form filers
# into Utility_Data itself instead of shipping them separately (see
# 00_feasibility_counts.R for how that's handled when reading).
extract_needed <- function(y) {
  zip_path <- file.path(RAW, sprintf("f861%d.zip", y))
  files <- c(sprintf("Utility_Data_%d.xlsx", y),
             sprintf("Service_Territory_%d.xlsx", y),
             sprintf("Sales_Ult_Cust_%d.xlsx", y))
  if (y != 2019) files <- c(files, sprintf("Short_Form_%d.xlsx", y))
  out_dir <- file.path(RAW, "extracted")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  unzip(zip_path, files = files, exdir = out_dir, junkpaths = TRUE)
}
for (y in YEARS) extract_needed(y)

# ---- Validation: fail loudly if any year is missing --------------------------
got_zip <- vapply(YEARS, function(y) file.exists(file.path(RAW, sprintf("f861%d.zip", y))), logical(1))
if (!all(got_zip)) stop("Missing annual 861 zips for: ", paste(YEARS[!got_zip], collapse = ", "))
message("\nAll ", length(YEARS), " years of EIA-861 present in ", RAW)
