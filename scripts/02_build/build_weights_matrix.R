rm(list = ls())

library(terra)
library(exactextractr)
library(sf)
library(Matrix)
library(ncdf4)
library(dplyr)
library(arrow)
library(readxl)
library(tidycensus)
library(tigris)
library(stringr)
library(purrr)
library(ggplot2)

RAW_GPW       <- "data/raw/gpw"
RAW_NCLIM <- "data/raw/nclimgrid"
OUT_DIR   <- "data/intermediate"
YEARS     <- 2015:2024

clim_path_temp <- file.path(RAW_NCLIM, "grids/ncdd-202007-grd-scaled.nc")
gpw_path <- file.path(RAW_GPW, "gpw_v4_population_count_rev11_2020_2pt5_min.tif")

tavg <- rast(clim_path_temp, subds = "tavg")
tmax <- rast(clim_path_temp, subds = "tmax")
tmin <- rast(clim_path_temp, subds = "tmin")

grid <- tavg[[1]]

counties <- tigris::counties(year = 2020, cb = TRUE)
data(fips_codes)

counties <- counties %>%
  filter(!STATEFP %in% c("02", "15"),     
         as.integer(STATEFP) <= 56) %>%
  mutate(GEOID = str_pad(GEOID, width = 5, side = "left", pad = "0"))

nrow(counties)
gpw_2020 <- rast(gpw_path)
gpw_us <- crop(gpw_2020, ext(grid))

pop <- gpw_us
pop_vec <- values(pop, mat = FALSE)   
sum(values(pop), na.rm = TRUE) #398267974

#pop_masked <- mask(gpw_us, grid)
#sum(values(pop_masked), na.rm = TRUE) #336464830

# ---- 4. Build W ----
build_W <- function(shapes, id_col, grid, pop_vec) {
  stopifnot(inherits(shapes, "sf"),
            st_crs(shapes) == st_crs(terra::crs(grid)),
            id_col %in% names(shapes), 
            !anyNA(shapes[[id_col]]), 
            !anyDuplicated(shapes[[id_col]]),
            is.character(shapes[[id_col]]),
            length(pop_vec) == ncell(grid))
  extracted <- exact_extract(grid, shapes, include_cell = TRUE, include_cols = id_col)
  coverage_table <- list_rbind(extracted)
  weight_table <- coverage_table %>%
    mutate(population = pop_vec[cell],
           weight = coverage_fraction * coalesce(population, 0)) %>%
    filter(weight > 0)
  W <- sparseMatrix(i = match(weight_table[[id_col]], shapes[[id_col]]), j = weight_table$cell, 
                    x =weight_table$weight, dims = c(nrow(shapes), ncell(grid)), 
                    dimnames = list(shapes[[id_col]], NULL))
  stopifnot(nnzero(W) == nrow(weight_table))
  empty_ids <- shapes[[id_col]][rowSums(W) == 0]
  return(list(W = W, ids = shapes[[id_col]], n_cells = ncell(grid), 
              grid_dim = dim(grid)[1:2], grid_ext = as.vector(ext(grid)),
         empty_ids = empty_ids))
         }

counties_g <- st_transform(counties, st_crs(terra::crs(grid)))
res <- build_W(counties_g, "GEOID", grid, pop_vec)
W <- res$W

# ---- 5. Checks

census_counts <- tidycensus::get_decennial(geography = "county",
                          variables = "P1_001N",
                          year = 2020) %>% 
  mutate(GEOID = str_pad(GEOID, width = 5, side = "left", pad = "0"))

dim(W)
w_pop <- rowSums(W)         
summary(w_pop)
sum(w_pop)  

check <- data.frame(GEOID = counties$GEOID, w_pop = as.numeric(w_pop))

census_counts_clean <- census_counts %>% left_join(counties %>% select(GEOID, STATEFP), by = "GEOID" ) %>%
  filter(!STATEFP %in% c("02", "15"),     
         as.integer(STATEFP) <= 56) %>% 
  select(!STATEFP, "GEOID", value) %>%
  full_join(check, by = "GEOID") %>%
  mutate(ratio = w_pop / value)

summary(census_counts_clean$ratio)
quantile(census_counts_clean$ratio, c(0.01, 0.05, 0.5, 0.95, 0.99), na.rm = TRUE)


hist(census_counts_clean$ratio,
     breaks = 100, xlim = c(0.5, 1.5),
     main = "W population / 2020 Census", xlab = "ratio")
abline(v = 1, col = "red")


# ---- Build one comparison table, joined by key ----
state_names <- fips_codes %>% distinct(state_code, state)

chk <- full_join(
  data.frame(GEOID = names(w_pop), w_pop = as.numeric(w_pop)),
  census_counts %>% transmute(GEOID, NAME, census_pop = value),
  by = "GEOID") %>%
  mutate(STATEFP = substr(GEOID, 1, 2)) %>%
  filter(!STATEFP %in% c("02", "15"), as.integer(STATEFP) <= 56) %>%   # CONUS only
  left_join(state_names, by = c("STATEFP" = "state_code")) %>%
  mutate(ratio = w_pop / census_pop)

# ---- 1. The 10 lowest and 10 highest ratios ----
cols <- c("NAME", "state", "census_pop", "w_pop", "ratio")
chk %>% arrange(ratio)       %>% slice_head(n = 10) %>% select(all_of(cols))
chk %>% arrange(desc(ratio)) %>% slice_head(n = 10) %>% select(all_of(cols))

# ---- 2. How many are outside the windows, and how much population ----
chk %>% summarise(
  n_counties        = n(),
  out_08_125_n      = sum(ratio < 0.8 | ratio > 1.25, na.rm = TRUE),
  out_08_125_pop    = sum(census_pop[ratio < 0.8 | ratio > 1.25], na.rm = TRUE) / sum(census_pop, na.rm = TRUE),
  out_05_15_n       = sum(ratio < 0.5 | ratio > 1.5,  na.rm = TRUE),
  out_05_15_pop     = sum(census_pop[ratio < 0.5 | ratio > 1.5], na.rm = TRUE) / sum(census_pop, na.rm = TRUE))

# ---- 3. By state: is the overshoot regional (the projection story)? ----
chk %>% group_by(state) %>%
  summarise(n = n(),
            median_ratio = median(ratio, na.rm = TRUE),
            pop_ratio    = sum(w_pop, na.rm = TRUE) / sum(census_pop, na.rm = TRUE)) %>%
  arrange(desc(pop_ratio)) %>% print(n = Inf)

# ---- 4. Where the gap between total GPW population and sum(W) goes ----
total_pop    <- sum(pop_vec, na.rm = TRUE)                      # all cells in the crop
covered <- which(colSums(W) > 0)
pop_covered  <- sum(pop_vec[covered], na.rm = TRUE)             # cells touched by any county
c(total          = total_pop,
  covered_cells  = pop_covered,
  W              = sum(W),
  outside_all_counties = total_pop - pop_covered,               # Canada, Mexico, ocean
  split_border_cells   = pop_covered - sum(W))                  # cells only partly inside counties

# ---- 5. Absent counties, three different senses ----
names(w_pop)[w_pop == 0]                               # overlap, but zero population
setdiff(chk$GEOID[!is.na(chk$census_pop)], counties$GEOID)   # in Census, not in our shapefile
setdiff(counties$GEOID, chk$GEOID[!is.na(chk$census_pop)])   # in our shapefile, not in Census

# ---- 6. Save ----
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

saveRDS(c(res, list(pop_source = basename(gpw_path))),
        file.path(OUT_DIR, "W_county_cell.rds"))

chk_w <- readRDS(file.path(OUT_DIR, "W_county_cell.rds"))
stopifnot(all(dim(chk_w$W) == c(length(chk_w$ids), chk_w$n_cells)),
          !anyNA(chk_w$W@x),
          length(chk_w$empty_ids) == 0)
