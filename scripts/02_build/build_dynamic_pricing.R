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
THRESH <- 0.1


wanted_cols <- tibble::tribble(
  ~new_name,       ~program,        ~sector,
  "res_enrolled", "Customers Enrolled", "Residential",
  "res_tou",       "Time of Use Pricing", "Residential",
  "res_rtp", "Real Time Pricing", "Residential",
  "res_vpp",       "Variable Peak Pricing",  "Residential",
  "res_cpp",       "Critical Peak Pricing",  "Residential",
  "res_cpr",       "Critical Peak Rebate",       "Residential"
)


find_program_col <- function(path, program, sector, sheet = NULL) {
  banner <- suppressMessages(read_excel(path, sheet = sheet, col_names = FALSE, n_max = 3))
  row2 <- unlist(banner[2, ]); row3 <- unlist(banner[3, ])
  for (i in seq_along(row2)) if (is.na(row2[i]) && i > 1) row2[i] <- row2[i - 1] # fill merged banner cells
  idx <- which(trimws(row2) == program & trimws(row3) == sector)
  if (length(idx) != 1) stop(path, ": expected exactly one, found ", length(idx))
  idx
}

dp_path <- function(y) {file.path(EXTRACTED, 
  if (y <= 2016) {
    sprintf("Dynamic_Pricing%d.xlsx", y)}
  else {
    sprintf("Dynamic_Pricing_%d.xlsx", y)})}


read_dp_year <- function(y) {
  path <- dp_path(y)
  dp <- read_excel(path, sheet = "Dynamic Pricing_States", skip = 2, col_types = "text")
  
  for (i in seq_len(nrow(wanted_cols))) {
    idx <- find_program_col(path, wanted_cols$program[i], wanted_cols$sector[i],
                            sheet = "Dynamic Pricing_States")
    names(dp)[idx] <- wanted_cols$new_name[i]
  }
  
  dp %>% mutate(year = y) %>%
    rename(utility_id = `Utility Number`, state = `State`, 
           any_of(c(short_form = "Short Form", ba_code = "BA Code"))) %>%
    mutate(res_enrolled = as.numeric(na_if(res_enrolled, ".")),
           utility_id = as.numeric(utility_id)) %>%
    select(year, utility_id, state, any_of(c("short_form", "ba_code")),
           all_of(wanted_cols$new_name))
}

pricing_details <- bind_rows(lapply(YEARS, read_dp_year))

indicators <- c("res_tou", "res_rtp", "res_vpp", "res_cpp", "res_cpr")

pricing_details <- pricing_details %>%
  mutate(short_form = short_form %in% "Y") %>%
  mutate(across(all_of(indicators), ~ case_when(
    .x %in% "Y" ~ TRUE,
    .x %in% "N" ~ FALSE,
    short_form  ~ NA,      # blank on a short-form row: never asked
    TRUE        ~ FALSE    # blank on a full-form row: assumed "N" (2020+); label this
  )))

pricing_details <- pricing_details %>%
  mutate(res_any_dynamic = coalesce(res_enrolled > 0, FALSE) | 
                                      if_any(all_of(indicators), ~ .x %in% TRUE)
                                    )

any_na <- function(x) if (all(is.na(x))) NA else any(x, na.rm = TRUE)
sum_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

pricing_details_clean <- pricing_details %>%
  summarize(.by = c(utility_id, year), 
            across(all_of(indicators), any_na),
            res_any_dynamic = any(res_any_dynamic),
            res_enrolled    = sum_na(res_enrolled),
            short_form      = any(short_form),
            n_rows          = n(),
            in_dp_file      = TRUE)
              

ownership_df <- read_parquet(file.path(OUT_DIR, "ownership_utility_year.parquet"))

ownership_lookup <- ownership_df %>%
  distinct(utility_id, year, ownership, ownership_raw, short_form, utility_name,
           tva_distributor)
stopifnot(!anyDuplicated(ownership_lookup[c("year", "utility_id")]))

merged_pricing <- ownership_lookup %>%
  rename(own_short_form = short_form) %>%
  left_join(pricing_details_clean, by = c("year", "utility_id"), 
            relationship = "one-to-one") %>%
  mutate(in_dp_file = coalesce(in_dp_file, FALSE),
            tou_res = case_when(in_dp_file     ~ res_tou,   # can be NA for short-form 2020+
                                own_short_form ~ NA,
                                TRUE           ~ FALSE), 
            any_dynamic_res = case_when(in_dp_file                    ~ res_any_dynamic,
                                        own_short_form & year <= 2018 ~ NA,   # never in file then
                                        TRUE                          ~ FALSE)
  )
            

merged_pricing %>% count(own_short_form, is.na(tou_res))
            
# ---- G. Enrollment share ------------------------------------------------------
# TODO: res_customers by utility-year from panel_sales_ownership.parquet (sum over states);
#       enroll_share = res_enrolled / res_customers (NA if no customers); flag share > 1.

customer_utility_counts <- read_parquet(file.path(OUT_DIR, "sales_utility_year.parquet")) %>%
  summarize(.by = c("utility_id", "year"), 
                    res_customers = sum(res_customers, na.rm = TRUE),
            rows = n()) %>%
    select(res_customers, utility_id, year) 

merged_pricing_counts <- merged_pricing %>%
  left_join(customer_utility_counts, by = c("utility_id", "year"), 
            relationship = "one-to-one") %>%
  mutate(enroll_share = (if_else(res_customers > 0,
                                 res_enrolled / res_customers,
                                 NA_real_)))

# ---- H. Adoption variables ----------------------------------------------------
# TODO: from the full-form utility-years only:
#   first_tou_year; left_censored (TRUE in the first observed year); adopter (off -> on);
#   reversal (on -> off later); and a persistent high-share rule
#   (share >= THRESHOLD in 2 consecutive years AND tou_res TRUE). Put THRESHOLD at the top.

threshold = 0.10

hazard_sample <- merged_pricing_counts %>%
  filter(own_short_form == FALSE) %>%
  group_by(utility_id) %>%
  mutate(
    first_tou_year = if (any(tou_res %in% TRUE)) {
      min(year[res_tou %in% TRUE], na.rm = TRUE)
    } else {NA_integer_},
    
    left_censored = coalesce(first_tou_year == min(year, na.rm = TRUE), FALSE),
    
    adopter = coalesce(year == first_tou_year & !left_censored, FALSE),
    
    reversal = tou_res %in% FALSE & lag(tou_res) %in% TRUE,
    
    high_share = tou_res %in% TRUE &  coalesce(enroll_share >= THRESH, FALSE)
    

  ) %>%
  ungroup()

hazard_sample <- hazard_sample %>%
  arrange(utility_id, year) %>%
  group_by(utility_id) %>%
  mutate(persistent_high = high_share &
  ((lead(high_share) %in% TRUE & lead(year) == year + 1) |
     (lag(high_share)  %in% TRUE & lag(year)  == year - 1))) %>%
  ungroup()
  

hazard_sample %>% filter(adopter == TRUE)

# ---- I. CHECK IN table --------------------------------------------------------
# TODO: switcher counts by ownership; write.csv to output/tables/.

utility_class <- hazard_sample %>%
  summarize(.by = c(utility_id, ownership),
            n_years       = n(),
            adopted       = any(adopter),
            left_censored = any(left_censored),
            ever_on       = any(tou_res %in% TRUE),
            n_reversals   = sum(reversal))

# Step 2: counts by ownership
switch_counts <- utility_class %>%
  summarize(.by = ownership,
            utilities       = n(),
            adopters        = sum(adopted),
            already_on      = sum(left_censored),
            never_on        = sum(!ever_on),
            reverted        = sum(n_reversals > 0),
            reversal_events = sum(n_reversals)) %>%
  arrange(ownership)


write.csv(switch_counts, "output/tables/dp_switch_counts.csv", row.names = FALSE)
# ---- J. Validation, save ------------------------------------------------------
# TODO: stopifnot: unique keys; indicators NA only on short-form rows 2020+;
#       all ten years present; PG&E 14328, SCE 17609, SDG&E 16609, SMUD 16534, LADWP 11208
#       have tou_res TRUE every year. write_parquet to data/intermediate/.
  


stopifnot(with(switch_counts, utilities == adopters + already_on + never_on))





# ---- J. Validation, save ------------------------------------------------------
KEY_UTILITIES <- c(PGE = 14328, SCE = 17609, SDGE = 16609, SMUD = 16534, LADWP = 11208)

stopifnot(
  # skeleton: one row per ownership-panel utility-year, no duplicates, all years
  nrow(merged_pricing_counts) == nrow(ownership_lookup),
  !anyDuplicated(merged_pricing_counts[c("year", "utility_id")]),
  setequal(unique(merged_pricing_counts$year), YEARS),
  
  # tou_res: never missing for full-form filers, missing only on short-form rows
  !anyNA(merged_pricing_counts$tou_res[!merged_pricing_counts$own_short_form]),
  
  # in_dp_file has no missing values and matches only utility-years in the file
  !anyNA(merged_pricing_counts$in_dp_file),
  sum(merged_pricing_counts$in_dp_file) <= nrow(pricing_details_clean),
  
  # share: no NaN / Inf (shares above 1 are flagged below, not an error)
  !any(is.nan(merged_pricing_counts$enroll_share) | is.infinite(merged_pricing_counts$enroll_share)),
  
  # hazard sample: full-form only, unique, flags never missing
  all(!hazard_sample$own_short_form),
  !anyDuplicated(hazard_sample[c("year", "utility_id")]),
  !anyNA(hazard_sample$adopter), !anyNA(hazard_sample$reversal), !anyNA(hazard_sample$left_censored),
  
  # at most one first adoption per utility, and never a left-censored one
  max(summarize(hazard_sample, .by = utility_id, n = sum(adopter))$n) <= 1,
  !any(hazard_sample$adopter & hazard_sample$left_censored),
  
  # sanity anchors: the big California utilities, SMUD and LADWP are on TOU in every year
  all(merged_pricing_counts$tou_res[merged_pricing_counts$utility_id %in% KEY_UTILITIES] %in% TRUE),
  n_distinct(merged_pricing_counts$utility_id[merged_pricing_counts$utility_id %in% KEY_UTILITIES]) == length(KEY_UTILITIES)
)

n_over_1 <- sum(merged_pricing_counts$enroll_share > 1, na.rm = TRUE)
if (n_over_1 > 0) message(n_over_1, " utility-years have enroll_share > 1 (flagged, not dropped)")

write_parquet(merged_pricing_counts, file.path(OUT_DIR, "dp_utility_year.parquet"))
write_parquet(hazard_sample,         file.path(OUT_DIR, "dp_hazard_sample.parquet"))



