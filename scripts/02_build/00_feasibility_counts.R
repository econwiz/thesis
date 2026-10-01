# Phase 2/3: the four feasibility numbers from CLAUDE.md section 4.2, 2015-2024.
# Reads files already downloaded AND extracted by p2_01_get_eia.R and
# p2_02_get_eia861m.R -- run those two first.
#
#   1. co-op / muni / IOU utility counts in the census (Utility_Data + Short_Form)
#   2. counties with >=1 co-op in the territory file (sanity check: >2,000 is
#      right, ~165 means the old "dominant utility" bug is back)
#   3. co-op / muni utility counts, 861M vs. the DETAIL-FILER census (Short_Form
#      utilities report no residential-specific number at all -- see note below --
#      so they can't be benchmarked against 861M on a residential measure)
#   4. share of co-op/muni residential CUSTOMERS covered by 861M vs. that same
#      detail-filer census
#
# Run from the repo root (~/thesis).

library(readxl)
library(dplyr)
library(tidyr)

RAW      <- "data/raw/eia"
RAW_M    <- "data/raw/eia861m"
EXTRACTED <- file.path(RAW, "extracted")
YEARS    <- 2015:2024

if (!dir.exists(EXTRACTED) || !dir.exists(RAW_M))
  stop("Run p2_01_get_eia.R and p2_02_get_eia861m.R first.")

missing_sales <- YEARS[!file.exists(file.path(EXTRACTED, sprintf("Sales_Ult_Cust_%d.xlsx", YEARS)))]
if (length(missing_sales) > 0)
  stop("Missing Sales_Ult_Cust for: ", paste(missing_sales, collapse = ", "), " -- rerun p2_01_get_eia.R")

# ---- #1/#2 helper: combined ownership (Utility_Data + Short_Form) -----------
# 2019 is the one year EIA folded short-form filers into Utility_Data itself
# (flagged Short Form == "Y"); every other year ships them in a separate file.
# Short_Form filers report only a Total customer count -- no residential
# breakdown -- so they belong in the FULL census (#1, #2) but not in the
# detail-filer benchmark used for #3/#4.
read_ownership <- function(y, detail_filers_only = FALSE) {
  ud <- read_excel(file.path(EXTRACTED, sprintf("Utility_Data_%d.xlsx", y)), skip = 1) |>
    mutate(year = y) |>
    rename(ownership = `Ownership Type`) |>
    select(year, `Utility Number`, `Utility Name`, State, ownership,
           any_of("Short Form")) |>
    filter(!is.na(`Utility Number`))
  if ("Short Form" %in% names(ud))
    ud <- if (detail_filers_only) filter(ud, is.na(`Short Form`) | `Short Form` != "Y")
          else ud |> select(-`Short Form`)
  ud <- select(ud, -any_of("Short Form"))

  if (detail_filers_only) return(ud)   # detail-filer benchmark: stop here

  sf_path <- file.path(EXTRACTED, sprintf("Short_Form_%d.xlsx", y))
  if (file.exists(sf_path)) {
    sf <- suppressWarnings(read_excel(sf_path)) |>
      mutate(year = y) |>
      rename(ownership = Ownership) |>
      select(year, `Utility Number`, `Utility Name`, State, ownership) |>
      filter(!is.na(`Utility Number`))
    overlap <- intersect(ud$`Utility Number`, sf$`Utility Number`)
    if (length(overlap) > 0)
      warning(y, ": ", length(overlap), " Utility Numbers appear in BOTH files")
    bind_rows(ud, sf)
  } else {
    ud
  }
}

# A distinct() here: Utility Number 88888 ("Withheld", anonymized small Texas
# retail power marketers under restructuring) repeats several times per year
# with identical (year, Utility Number) -- harmless for our purposes (it's
# never Cooperative/Municipal) but it makes later joins many-to-many otherwise.
ownership_full   <- bind_rows(lapply(YEARS, read_ownership, detail_filers_only = FALSE)) |> distinct()
ownership_detail <- bind_rows(lapply(YEARS, read_ownership, detail_filers_only = TRUE)) |> distinct()

# ---- Robust column finder: locate a column by its banner + header text ----
# rather than a guessed/hardcoded name -- readxl's auto-repaired names (e.g.
# "Count...12") shift position across files/years (confirmed: Sales_Ult_Cust's
# 2019 vintage has one extra leading column vs. every other year), so we find
# the RESIDENTIAL "Count" (customers) column directly from the file's own
# banner row instead of assuming a fixed name or position.
find_residential_customers_col <- function(path, sheet = NULL) {
  banner <- suppressMessages(read_excel(path, sheet = sheet, col_names = FALSE, n_max = 3))
  row1 <- unlist(banner[1, ]); row3 <- unlist(banner[3, ])
  for (i in seq_along(row1)) if (is.na(row1[i]) && i > 1) row1[i] <- row1[i - 1]  # fill merged banner cells
  idx <- which(trimws(row1) == "RESIDENTIAL" & trimws(row3) == "Count")
  if (length(idx) != 1) stop(path, ": expected exactly one RESIDENTIAL/Count column, found ", length(idx))
  idx
}

# ---- #1: ownership counts, full census --------------------------------------
cat("\n==== #1: Ownership counts, full census (Utility_Data + Short_Form) ====\n")
t1 <- ownership_full |> count(year, ownership) |> pivot_wider(names_from = ownership, values_from = n)
print(t1)
stopifnot(all(t1$Cooperative > 700), all(t1$Municipal > 1500))   # fail loudly if this regresses

# ---- #2: counties with >=1 co-op --------------------------------------------
read_service_territory <- function(y) {
  read_excel(file.path(EXTRACTED, sprintf("Service_Territory_%d.xlsx", y))) |>
    mutate(year = y) |>
    select(year, `Utility Number`, State, County)
}
territory <- bind_rows(lapply(YEARS, read_service_territory))

# Join on (year, Utility Number, State), not just (year, Utility Number):
# EIA reports a multi-state utility as one row PER STATE (confirmed: e.g.
# Utility Number 925, "Ashley Chicot Elec Coop", has separate AR and LA rows
# every year). Joining without State would match every one of that utility's
# territory rows to BOTH its state-rows -- a real many-to-many bug, not a
# warning to silence.
coop_counties <- territory |>
  inner_join(ownership_full |> filter(ownership == "Cooperative") |> select(year, `Utility Number`, State),
             by = c("year", "Utility Number", "State"))

t2 <- coop_counties |> group_by(year) |> summarise(n_counties_with_coop = n_distinct(State, County))
cat("\n==== #2: Counties with >=1 co-op (sanity check: should be >2,000) ====\n")
print(t2)
stopifnot(all(t2$n_counties_with_coop > 2000))

# ---- #3/#4 helper: detail-filer census, residential customers ---------------
read_census_res_customers <- function(y) {
  path <- file.path(EXTRACTED, sprintf("Sales_Ult_Cust_%d.xlsx", y))
  idx  <- find_residential_customers_col(path)
  su   <- read_excel(path, skip = 2)
  names(su)[idx] <- "res_customers"
  # "Short Form" is (like Utility_Data's) a 2019-only column here too -- only
  # 2019 folds short-form filers into this file inline; drop them if present.
  if ("Short Form" %in% names(su)) su <- filter(su, is.na(`Short Form`) | `Short Form` != "Y")
  su |>
    mutate(year = y, res_customers = suppressWarnings(as.numeric(res_customers))) |>
    filter(`Service Type` == "Bundled") |>
    select(year, `Utility Number`, Ownership, res_customers)
}
census_res <- bind_rows(lapply(YEARS, read_census_res_customers))

census_res_by_year <- census_res |>
  filter(Ownership %in% c("Cooperative", "Municipal")) |>
  group_by(year, Ownership) |>
  summarise(customers = sum(res_customers, na.rm = TRUE), .groups = "drop")

# ---- #3/#4 helper: 861M, December of each year, detail filers only ---------
# The 861M archive's own ".xls" naming is sometimes a lie (e.g. f8262016.xls is
# actually xlsx content) -- p2_02_get_eia861m.R sniffs and renames to the true
# extension at download time, so we look up whatever file actually landed
# rather than assuming an extension.
m861_filename <- function(y) {
  if (y <= 2016)      sprintf("f826%d", y)
  else if (y <= 2020) sprintf("retail_sales_%d", y)
  else                sprintf("sales_ult_cust_%d", y)
}
m861_path_for_year <- function(y) {
  matches <- Sys.glob(file.path(RAW_M, paste0(m861_filename(y), ".*")))
  if (length(matches) == 0) stop("No 861M file found for year ", y, " in ", RAW_M)
  matches[1]
}
read_861m_year <- function(y) {
  path <- m861_path_for_year(y)
  idx  <- find_residential_customers_col(path, sheet = "Sales Ultimate Cust. -States")
  d    <- read_excel(path, sheet = "Sales Ultimate Cust. -States", skip = 2)
  names(d)[idx] <- "res_customers"
  d |>
    mutate(year = y, res_customers = suppressWarnings(as.numeric(res_customers))) |>
    filter(`Utility Number` != 0, `Data Status` == "Final", Month == 12) |>
    select(year, `Utility Number`, Ownership, res_customers)
}
m861 <- bind_rows(lapply(YEARS, read_861m_year))

m861_by_year <- m861 |>
  filter(Ownership %in% c("Cooperative", "Municipal")) |>
  group_by(year, Ownership) |>
  summarise(customers_861m = sum(res_customers, na.rm = TRUE),
            n_utilities_861m = n_distinct(`Utility Number`), .groups = "drop")

# ---- #3: utility-count coverage, 861M vs detail-filer census ----------------
detail_util_counts <- ownership_detail |>
  filter(ownership %in% c("Cooperative", "Municipal")) |>
  count(year, ownership, name = "n_utilities_census")

t3 <- m861_by_year |>
  rename(ownership = Ownership) |>
  left_join(detail_util_counts, by = c("year", "ownership")) |>
  mutate(pct_utilities_covered = n_utilities_861m / n_utilities_census)
cat("\n==== #3: Utility-count coverage, 861M vs. detail-filer census ====\n")
print(t3 |> select(year, ownership, n_utilities_861m, n_utilities_census, pct_utilities_covered))

# ---- #4: residential customer coverage --------------------------------------
t4 <- m861_by_year |>
  rename(ownership = Ownership) |>
  left_join(census_res_by_year |> rename(ownership = Ownership, customers_census = customers),
            by = c("year", "ownership")) |>
  mutate(pct_customers_covered = customers_861m / customers_census)
cat("\n==== #4: Residential customer coverage, 861M vs. detail-filer census ====\n")
print(t4 |> select(year, ownership, customers_861m, customers_census, pct_customers_covered))

# ---- Save for the check-in --------------------------------------------------
dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)
write.csv(t1, "output/tables/p2_ownership_counts_full_census.csv", row.names = FALSE)
write.csv(t2, "output/tables/p2_counties_with_coop.csv", row.names = FALSE)
write.csv(t3, "output/tables/p2_861m_utility_coverage.csv", row.names = FALSE)
write.csv(t4, "output/tables/p2_861m_customer_coverage.csv", row.names = FALSE)
cat("\nSaved four tables to output/tables/p2_*.csv\n")
