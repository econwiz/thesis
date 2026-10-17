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
if (!dir.exists(EXTRACTED) || !dir.exists(RAW_M))
  stop("Run p2_01_get_eia.R and p2_02_get_eia861m.R first.")

missing_sales <- YEARS[!file.exists(file.path(EXTRACTED, sprintf("Sales_Ult_Cust_%d.xlsx", YEARS)))]
if (length(missing_sales) > 0)
  stop("Missing Sales_Ult_Cust for: ", paste(missing_sales, collapse = ", "), " -- rerun p2_01_get_eia.R")

#test_sales <- read_excel(file.path(EXTRACTED, "Sales_Ult_Cust_2019.xlsx"), col_names = TRUE)

#names(test_sales)


find_banner_col <- function(path, group, unit, sheet = NULL) {
  banner <- suppressMessages(read_excel(path, sheet = sheet, col_names = FALSE, n_max = 3))
  row1 <- unlist(banner[1, ]); row3 <- unlist(banner[3, ])
  for (i in seq_along(row1)) if (is.na(row1[i]) && i > 1) row1[i] <- row1[i - 1]  # fill merged banner cells
  idx <- which(trimws(row1) == group & trimws(row3) == unit)
  if (length(idx) != 1) stop(path, ": expected exactly one, found ", length(idx))
  idx
}
  
wanted_cols <- tibble::tribble(
  ~new_name,       ~group,        ~unit,
  "res_revenue_k", "RESIDENTIAL", "Thousand Dollars",
  "res_mwh",       "RESIDENTIAL", "Megawatthours",
  "res_customers", "RESIDENTIAL", "Count",
  "com_mwh",       "COMMERCIAL",  "Megawatthours",
  "ind_mwh",       "INDUSTRIAL",  "Megawatthours",
  "tot_mwh",       "TOTAL",       "Megawatthours"
)


read_census_res_customers_sales <- function(y) {
  path <- file.path(EXTRACTED, sprintf("Sales_Ult_Cust_%d.xlsx", y))
  su   <- read_excel(path, skip = 2)
  for (i in seq_len(nrow(wanted_cols))){
    idx  <- find_banner_col(path, wanted_cols$group[i], wanted_cols$unit[i])
    names(su)[idx] <- wanted_cols$new_name[i]
  }
  if ("Short Form" %in% names(su)) su <- filter(su, is.na(`Short Form`) | `Short Form` != "Y")
  su %>%
    mutate(year = y, across(all_of(wanted_cols$new_name), ~ suppressWarnings(as.numeric(.)))) %>%
    filter(`Service Type` %in% c("Bundled", "Delivery")) %>%
    select(year, `Utility Number`, Ownership, `Service Type`, `Part`, `State`,
           all_of(wanted_cols$new_name), grep("^Data Type", names(su), value = TRUE))
}

eia861_details <- bind_rows(lapply(YEARS, read_census_res_customers_sales))


eia861_details <- eia861_details %>%
  rename(state = `State`, 
         ownership = `Ownership`, 
         utility_id = `Utility Number`,
         service_type = `Service Type`, 
         part = `Part`)

eia861_details <-eia861_details %>%
  filter(!utility_id %in% c(99999, 88888)) %>% 
  group_by(year, state, utility_id) %>%
  summarize(across(all_of(wanted_cols$new_name), \(x) sum(x, na.rm = TRUE)),
            has_delivery = any(service_type == "Delivery"),
            ownership_sales = first(ownership),
            .groups = "drop") %>%
  mutate(kwh_per_customer = if_else(res_customers > 0,
                                    res_mwh * 1000 / res_customers,
                                    NA_real_)) %>%
  mutate(nonres_share = if_else(tot_mwh > 0,
                                (com_mwh + coalesce(ind_mwh, 0)) / tot_mwh, NA_real_)) %>%
  mutate(avg_res_price = if_else(res_mwh > 0 & !has_delivery,
                                 res_revenue_k / res_mwh * 100,
                                 NA_real_))

eia861_details <-eia861_details %>% mutate(has_residential = if_else(res_customers > 0, TRUE, FALSE)) 
  

write_parquet(eia861_details, file.path(OUT_DIR, "sales_utility_year.parquet"))

