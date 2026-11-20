library(readr)
library(dplyr)
library(purrr)
library(stringr)
library(arrow)
PRCP_DIR <- "data/raw/nclimgrid/prcp_cty"
OUT_DIR   <- "data/intermediate"
files <- sort(list.files(PRCP_DIR, pattern = "\\.csv$", full.names = TRUE))  # expect 120
xwalk <- read_csv("data/raw/nclimgrid/us-state-codes_ncei-to-fips.csv",
                  col_types = cols(.default = "c"))       # characters: keep the leading zeros!
test_one <- file.path(PRCP_DIR, "prcp-201502-cty-scaled.csv")
# ---- 1. One file -> county-month ----
read_prcp_month <- function(path) {
  col_types <- c(rep("character", 6), rep("numeric", 31))
  
  df <- read.csv(path, header = FALSE, colClasses = col_types, na.strings = "-999.99")
  
  names(df)[7:37] <- sprintf("day_%02d", 1:31)
  
  processed_df <- df %>%
    rename(
      ncei_id = V2,
      year    = V4,
      month   = V5,
    ) %>%
    mutate(
      # Calculate total. Using na.rm = TRUE means a single missing day won't break the sum.
      monthly_total    = rowSums(across(day_01:day_31), na.rm = TRUE),
      missing_days     = rowSums(is.na(across(day_01:day_31))),
      non_missing_days = rowSums(!is.na(across(day_01:day_31)))
    )
  
  return(data.frame(
    ncei_id         = processed_df$ncei_id, 
    year            = as.integer(processed_df$year), 
    month           = as.integer(processed_df$month), 
    prcp_mm         = processed_df$monthly_total, 
    n_days_reported = processed_df$non_missing_days
  ))
}

prcp_month <- bind_rows(lapply(files, read_prcp_month), .id = "file")

prcp_month <- prcp_month %>% 
  mutate(state_ncei = str_sub(ncei_id, 1, 2),
         county_ncei = str_sub(ncei_id, 3, 5),
         ncei_id = if_else(state_ncei == "18" & county_ncei == "511", "11001", ncei_id))

xwalk <- xwalk %>% rename(state_ncei = NCEI_code)

prcp_month_joined <- prcp_month %>%
  left_join(xwalk, by = "state_ncei") %>%
  mutate(county_fips = paste0(FIPS_code, county_ncei))

prcp_month_joined <- prcp_month_joined %>%
  mutate(county_fips = if_else(county_fips == "24511", "11001", county_fips))

print(sum(is.na(prcp_month_joined$county_fips)))

prcp_annual_totals <- prcp_month_joined %>%
  group_by(county_fips, year) %>% 
  summarise(
    prcp_total_mm = sum(prcp_mm, na.rm = TRUE),
    n_months      = n(),
    n_days        = sum(n_days_reported),
    .groups       = "drop"
  )

prcp_total_days <- prcp_month_joined %>% 
  group_by(county_fips) %>% 
  summarise(
    total_days = sum(!is.na(prcp_mm)),
    .groups = "drop"
  )


temp_year <- read_parquet("data/intermediate/temperature_county_year.parquet")

county_year <- temp_year %>%
  left_join(prcp_annual_totals %>% select(county_fips, year, prcp_total_mm),
            by = c("county_fips", "year"))

stopifnot(!anyNA(prcp_month_joined$FIPS_code))
stopifnot(all(prcp_annual_totals$n_months == 12),
          all(prcp_annual_totals$n_days == if_else(prcp_annual_totals$year %in% c(2016, 2020, 2024), 366L, 365L)),
          !anyNA(prcp_annual_totals),
          all(prcp_annual_totals$prcp_total_mm >= 0))
stopifnot(nrow(county_year) == nrow(temp_year))
setdiff(temp_year$county_fips, prcp_annual_totals$county_fips)    # should print "51678"


temp_prcp_year <- write_parquet(county_year, file.path(OUT_DIR, "temperature_precip_county_year.parquet"))
