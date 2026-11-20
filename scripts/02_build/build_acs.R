library(terra)
library(Matrix)
library(sf)
library(ncdf4)
library(dplyr)
library(arrow)
library(tidycensus)
library(tigris)
library(stringr)
library(purrr)
library(ggplot2)

setwd("/Users/aliabonanno/thesis")

OUT_DIR   <- "data/intermediate"

BASE_YEAR <- 2019   

map <- c(pov_total = "C17002_001", pov_u50 = "C17002_002", pov_99 = "C17002_003",
         pov_125 = "C17002_004", pov_150= "C17002_005", hous_btotal = "B25034_001", 
         hous_b1979 = "B25034_007", hous_b1969 = "B25034_008", hous_b1959 = "B25034_009", 
         hous_b1949 = "B25034_010", hous_b1939 = "B25034_011",heat_fuel_total = "B25040_001", 
         heat_elec = "B25040_004", tenure_tot = "B25003_001",
         tenure_rent = "B25003_003", pop = "B01003_001", inc = "B19013_001")

# ---- 2. Pull ----

acs_table <- get_acs(
  geography = "county",
  variables = map, 
  year = BASE_YEAR,
  survey = "acs5",
  output = "wide"
)

# ---- 3. Build the shares ----
acs_table_clean <- acs_table %>%
  mutate(pov_150 = (pov_u50E + pov_99E + pov_125E + pov_150E)/(pov_totalE),
         old_housing_share = (hous_b1979E + hous_b1969E + hous_b1959E + hous_b1949E + hous_b1939E )/(hous_btotalE), 
         electric_heat_share = heat_elecE/heat_fuel_totalE,
         renter_share = tenure_rentE/tenure_totE) %>%
  filter(!(substr(GEOID, 0, 2)) %in% c("02","15"),
         as.integer(substr(GEOID, 0, 2)) <= 56)

# ---- 4. Checks ----

acs_table_checks <- acs_table_clean %>%
  summarize(rows = nrow(acs_table_clean),
            missing = sum(is.na(incE)))
            
shares <- c("pov_150", "old_housing_share", "electric_heat_share", "renter_share")
stopifnot(all(sapply(acs_table[shares], function(v) all(v >= 0 & v <= 1, na.rm = TRUE))))

acs_table_clean %>% filter(electric_heat_share == 1)
# ---- 5. Save ----

write_parquet(acs_table_clean, file.path(OUT_DIR, "acs_county_2019.parquet"))

