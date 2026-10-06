# Phase 4, step 1: build the utility x state x year ownership panel.
# Needs p2_01_get_eia.R to have already downloaded + extracted the annual 861 files.

library(readxl)
library(dplyr)
library(tidyr)
library(arrow)

RAW       <- "data/raw/eia"
EXTRACTED <- file.path(RAW, "extracted")
EXTRACTED_SF <- file.path(RAW, "extracted_sf")
OUT_DIR   <- "data/intermediate"
YEARS     <- 2015:2024

if (!dir.exists(EXTRACTED)) stop("Run p2_01_get_eia.R first.")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

read_ownership_year <- function(y) {
  ud <- read_excel(file.path(EXTRACTED, sprintf("Utility_Data_%d.xlsx",y)), skip = 1) %>%
    mutate(year = y) %>%
    rename(ownership_raw = `Ownership Type`,
           utility_id = `Utility Number`, 
           utility_name = `Utility Name`)
  
  if ("Short Form" %in% names(ud)) {
    ud <- mutate(ud, short_form = `Short Form` %in% "Y")}
  else {
    ud <- mutate(ud, short_form = FALSE)
  }
  
  ud  <- ud %>%
    select(year, utility_name, utility_id, State, ownership_raw, short_form) %>%
    filter(!is.na(utility_id))
  
  sf_path <- file.path(EXTRACTED, sprintf("Short_Form_%d.xlsx", y))
  if (file.exists(sf_path)) {
    sf <- suppressWarnings(read_excel(sf_path)) %>%
      mutate(year = y, short_form = TRUE) %>%
      rename(ownership_raw = `Ownership`,
             utility_name = `Utility Name`,
             utility_id = `Utility Number`) %>%
      select(year, utility_name, utility_id, State, ownership_raw, short_form) %>%
      filter(!is.na(utility_id))
    overlap <- intersect(ud$utility_id, sf$utility_id)
    if (length(overlap) > 0)
      warning(y, ": ", length(overlap), " Utility Numbers appear in BOTH files")
    bind_rows(ud, sf)
  } else {
    ud
  }
}

test <- read_ownership_year(2019)
names(test)
class(test$utility_id)
ownership_raw_panel <- bind_rows(lapply(YEARS, read_ownership_year))


# ---- Step 2: map EIA's raw categories into the four the thesis uses ---------
# iou <- Investor Owned
# coop <- Cooperative
# public <- Municipal, Political Subdivision, State, Municipal Marketing Authority
# federal <- Federal                                    (kept on its own -- do not merge into public)
# DROP: Retail Power Marketer, Behind the Meter, Facility
#
# TODO: write the mapping (a named vector or case_when()), apply it to create
# an `ownership` column. Rows that map to "drop" get ownership = NA for now --
# don't filter them out yet, you need their customer counts first (step 3).
map_ownership <- function(ownership_raw) {
  clean_ownership <- stringr::str_trim(ownership_raw)
  case_match(clean_ownership,
             c("Municipal", "Political Subdivision", "State", "Municipal Mktg Authority") ~ "public",
             "Investor Owned" ~ "iou",
             "Cooperative"    ~ "coop",
             "Federal"        ~ "federal",
             .default = NA_character_)
}

ownership_raw_panel <- ownership_raw_panel %>%
  mutate(ownership = map_ownership(ownership_raw))

# ---- Step 3: print residential customer counts for what's about to be dropped
# TODO: for utility_ids with ownership == NA (i.e. Retail Power Marketer /
# Behind the Meter / Facility), look up their RESIDENTIAL customer counts.
# Short_Form only has a Total (not residential) count, so you'll need
# Sales_Ult_Cust_<y>.xlsx (Service Type == "Bundled") for this, the same way
# 00_feasibility_counts.R's read_census_res_customers() does. Print a
# by-year, by-ownership_raw summary before you drop anything.

find_residential_customers_col <- function(path, sheet = NULL) {
  banner <- suppressMessages(read_excel(path, sheet = sheet, col_names = FALSE, n_max = 3))
  row1 <- unlist(banner[1, ]); row3 <- unlist(banner[3, ])
  for (i in seq_along(row1)) if (is.na(row1[i]) && i > 1) row1[i] <- row1[i - 1]  # fill merged banner cells
  idx <- which(trimws(row1) == "RESIDENTIAL" & trimws(row3) == "Count")
  if (length(idx) != 1) stop(path, ": expected exactly one RESIDENTIAL/Count column, found ", length(idx))
  idx
}

read_census_res_customers <- function(y) {
  path <- file.path(EXTRACTED, sprintf("Sales_Ult_Cust_%d.xlsx", y))
  idx  <- find_residential_customers_col(path)
  su   <- read_excel(path, skip = 2)
  names(su)[idx] <- "res_customers"
  # "Short Form" is (like Utility_Data's) a 2019-only column here too -- only
  # 2019 folds short-form filers into this file inline; drop them if present.
  if ("Short Form" %in% names(su)) su <- filter(su, is.na(`Short Form`) | `Short Form` != "Y")
  su %>%
    mutate(year = y, res_customers = suppressWarnings(as.numeric(res_customers))) %>%
    filter(`Service Type` == "Bundled") %>%
    select(year, `Utility Number`, Ownership, res_customers, `State`)
}

census_res <- bind_rows(lapply(YEARS, read_census_res_customers))

dropped_ids <- ownership_raw_panel %>% filter(is.na(ownership)) %>%
  select(utility_id) %>%
  distinct()

dropped_ids

drop_summary <- census_res %>%
  rename(utility_id = `Utility Number`,
         ownership = `Ownership`) %>% 
  inner_join(dropped_ids, by = "utility_id") %>%
  group_by(year, ownership) %>%
  summarize(
    dropped_utilities = n(),
    total_res_customers = sum(res_customers, na.rm = TRUE),
    .groups = "drop"
  )

drop_summary %>% group_by(year) %>%
  summarize(
    total_res_year = sum(total_res_customers, na.rm = TRUE)
  )

write.csv(drop_summary, file.path(OUT_DIR, "dropped_residential_counts.csv"), row.names = FALSE)
# ---- Step 4: drop the categories that don't map to one of the four ----------
# TODO: filter out ownership == NA now that you've printed what's being lost.

ownership_panel <- ownership_raw_panel %>%
  filter(!is.na(ownership)) 

nrow(ownership_raw_panel) - nrow(ownership_panel)

# ---- Step 5: deduplicate on (year, utility_id, state) ------------------------
# TODO: if a utility appears more than once for the same (year, state) --
# e.g. in both Utility_Data and Short_Form, which shouldn't normally happen --
# keep the Utility_Data (short_form == FALSE) row as the more complete record.

clean_ownership <- ownership_panel %>%
  arrange(year, State, utility_id, short_form) %>%
  distinct(year, State, utility_id, .keep_all = TRUE) %>%
  select(year, utility_id, State, utility_name, ownership_raw, ownership, short_form) %>%
  rename(state = `State`) 
  

# ---- Step 6: flag utilities whose ownership changes across years ------------
# TODO: group by utility_id, count distinct `ownership` values across all
# years/states for that utility. A handful of switchers is normal (compare
# against the ~14-15 we saw in the legacy county panel); dozens means
# something upstream is misparsing. Print the full list for a by-hand look --
# don't silently fix or drop them.

clean_ownership <- clean_ownership %>%
  group_by(utility_id) %>%
  mutate(unique_ownership = as.numeric(n_distinct(ownership))) %>%
  ungroup() %>%
  mutate(changes_ownership = if_else(unique_ownership > 1, TRUE, FALSE)) %>%
  arrange(year)

clean_ownership %>% filter(changes_ownership) %>% distinct(utility_id) %>% nrow()

switcher_ids <- ownership_raw_panel %>%
  group_by(utility_id) %>%
  mutate(unique_ownership = as.numeric(n_distinct(ownership))) %>%
  ungroup() %>%
  mutate(changes_ownership = if_else(unique_ownership > 1, TRUE, FALSE)) %>%
  arrange(year) %>% filter(changes_ownership) %>% distinct(utility_id) 

switchers <- ownership_raw_panel %>%
  semi_join(switcher_ids, by = "utility_id") %>%
  summarize(.by = c(utility_id, utility_name, ownership_raw, ownership),
            first_year = min(year), last_year = max(year)) %>%
  arrange(utility_id, first_year)
  
  
write.csv(switchers, file.path("data/intermediate/ownership_switchers.csv"), row.names = FALSE)
# ---- Step 7: tva_distributor placeholder -------------------------------------
# TODO: add a tva_distributor column, FALSE/NA for everyone for now -- this
# gets filled in properly once data/handcoded/tva_distributors.csv exists.

clean_ownership <- clean_ownership %>%
  mutate(tva_distributor = FALSE)


census_cleaned <- census_res %>%
  rename(utility_id = `Utility Number`,
         ownership = `Ownership`,
         state = `State`) %>%
  select(-ownership) %>%
  summarize(.by = c(year, utility_id, state),
            res_customers = sum(res_customers, na.rm = TRUE))

residential_counts <- clean_ownership %>%
  left_join(census_cleaned, by = c("state", "utility_id", "year")) %>%
    summarize(.by = c(year, ownership),
              utilities = n(),
              utilities_with_res = sum(!is.na(res_customers)),
              res_customers = sum(res_customers, na.rm = TRUE))

write.csv(residential_counts, file.path(OUT_DIR, "residential_counts_by_ownership_year.csv"), row.names = FALSE)



# ---- Step 8: validation (fail loudly) ----------------------------------------
# TODO: stopifnot(...) checks:
#   - co-op utility count is between 875 and 895 in every year
#   - public utility count is between 1820 and 1842 in every year
#   - no duplicate (year, utility_id, state) keys
#   - ownership is never NA (after step 4's drop)

utility_counts  <- clean_ownership %>%
  group_by(year) %>%
  summarize(coop_count = sum(ownership == "coop", na.rm = TRUE),
            iou_count = sum(ownership == "iou", na.rm = TRUE),
            muni_count = sum(ownership == "public", na.rm = TRUE))

stopifnot(
  !anyNA(clean_ownership$ownership),
  !anyDuplicated(clean_ownership[c("year", "state", "utility_id")]),
  all(utility_counts$coop_count >= 850,  utility_counts$coop_count <= 910),
  all(utility_counts$muni_count >= 1900, utility_counts$muni_count <= 2050),
  all(utility_counts$iou_count  >= 165,  utility_counts$iou_count  <= 195)
)
# ---- Step 9: save --------------------------------------------------------------
# TODO: write_parquet(..., file.path(OUT_DIR, "ownership_utility_year.parquet"))

save_ownership <- clean_ownership %>% 
  select(!c(unique_ownership, changes_ownership))

write_parquet(save_ownership, file.path(OUT_DIR, "ownership_utility_year.parquet"))
# ---- Check-in printout (per CLAUDE.md) ---------------------------------------
# TODO: print/save three things for the check-in:
#   1. utilities AND customers by ownership by year (the customers part needs
#      the same Sales_Ult_Cust residential-count join as step 3)
#   2. the full list of ownership-switchers from step 6
#   3. the dropped-category customer counts from step 3


