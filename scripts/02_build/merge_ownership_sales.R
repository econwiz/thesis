library(readxl)
library(dplyr)
library(tidyr)
library(arrow)

# setwd("/users/aliabonanno/thesis")
RAW      <- "data/raw/eia"
RAW_M    <- "data/raw/eia861m"
EXTRACTED <- file.path(RAW, "extracted")
YEARS    <- 2015:2024
OUT_DIR   <- "data/intermediate"

ownership_df <- read_parquet(file.path(OUT_DIR, "ownership_utility_year.parquet"))
sales_df <- read_parquet(file.path(OUT_DIR, "sales_utility_year.parquet"))

ownership_lookup <- ownership_df %>%
  distinct(utility_id, year, ownership, ownership_raw, short_form, utility_name,
           tva_distributor)
stopifnot(!anyDuplicated(ownership_lookup[c("year", "utility_id")]))

merged <- sales_df %>%
  left_join(ownership_lookup, by = c("year", "utility_id"), 
            relationship = "many-to-one")

nrow(merged) == nrow(sales_df)

sum(is.na(merged$ownership))

merged %>% filter(is.na(ownership)) %>% count(ownership_sales)

dropped_summary <- merged %>% filter(is.na(ownership)) %>%
  summarize(.by = c(year, ownership_sales),
            rows = n(), 
            res_customers = sum(res_customers, na.rm = TRUE)) %>%
  arrange(year, ownership_sales)

write.csv(dropped_summary, file.path(OUT_DIR, "nomatch_sales.csv"), row.names = FALSE)

merged <- merged %>%
  filter(!is.na(ownership))

coverage <- ownership_lookup %>%
  filter(short_form == FALSE) %>%
  anti_join(sales_df, by = c("year", "utility_id")) %>%
  summarize(.by = c(year, ownership),
            rows = n(),
  )
sum(coverage$rows)


write.csv(coverage, file.path(OUT_DIR, "no_sales_row.csv"), row.names = FALSE)


stopifnot(
  !anyDuplicated(merged[c("year", "state", "utility_id")]),
  !anyNA(merged$ownership),
  nrow(merged) == 16742,
  merged$ownership_sales == merged$ownership_raw,
  sum(merged$res_customers) + sum(dropped_summary$res_customers) == sum(sales_df$res_customers)
 )


summary_panel <- merged %>%
  summarize(.by = c(year, ownership),
            rows = n(), 
            res_customers = sum(res_customers, na.rm = TRUE),
            utilities = n_distinct(utility_id)) %>%
  arrange(year, ownership)


write_parquet(merged, file.path(OUT_DIR, "panel_sales_ownership.parquet"))



