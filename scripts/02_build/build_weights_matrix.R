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
# ---- 0. Grid template: the nClimGrid raster defines cell numbering ----
# TODO: read ONE layer (e.g. tavg, day 1) from the July 2020 file as `grid`.
# Every cell index in this script refers to THIS raster. 825,460 cells.


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

# ---- 1. Counties (2020 cartographic, CONUS only) ----
# TODO: load counties (tigris::counties(year = 2020, cb = TRUE) or a shapefile).
# TODO: keep CONUS: drop AK (02), HI (15), territories (>56).
# TODO: make sure the CRS is EPSG:4326 to match the grid, and keep a 5-digit
#       county_fips column as a character (leading zeros!).
# CHECK: nrow(counties). Expect about 3,100.

counties <- tigris::counties(year = 2020, cb = TRUE)
data(fips_codes)

counties <- counties %>%
  filter(!STATEFP %in% c("02", "15"),     
         as.integer(STATEFP) <= 56) %>%
  mutate(GEOID = str_pad(GEOID, width = 5, side = "left", pad = "0"))

nrow(counties)


# ---- 2. Population grid: crop and check alignment ----
# TODO: read the GPW 2020 count raster; crop it to ext(grid).
# TODO: compare dim(), ext(), res() against `grid`.
#       Edges should match to ~1e-5, not ==. Use all.equal(..., tolerance) or abs().
# TODO: if they match, use the cropped raster as `pop`.
#       If not: resample onto `grid` by SUMMING (aggregate/resample with fun = "sum").
# TODO: GPW nodata -> NA, then think: should NA population become 0?
# CHECK: sum(values(pop), na.rm = TRUE). Is it close to the US population (~330M)?
#        (Canada/Mexico cells inside the extent will add to it. Why does that not
#        matter for W?)

gpw_2020 <- rast(gpw_path)

gpw_us <- crop(gpw_2020, ext(grid))

pop <- gpw_us
pop_masked <- mask(gpw_us, grid)


sum(values(pop_masked), na.rm = TRUE) #336464830

sum(values(pop), na.rm = TRUE) #398267974

# ---- 3. Coverage fractions ----
# TODO: exact_extract(grid, counties, include_cell = TRUE, include_cols = "county_fips")
#       returns one data frame per county: cell index + coverage_fraction.
# TODO: bind these into one long table (county_fips, cell, coverage_fraction).
# CHECK: counties that return zero rows (nothing overlaps the grid).

extracted <- exact_extract(grid, counties, include_cell = TRUE, include_cols = "GEOID")

coverage_table <- list_rbind(extracted)

setdiff(counties$GEOID, coverage_table$GEOID)

# ---- 4. Build W ----
# TODO: attach pop[cell] to each row.
# TODO: weight = coverage_fraction * pop (what happens to NA pop?).
# TODO: sparseMatrix(i = <row index per county>, j = <cell index>, x = weight,
#       dims = c(n_counties, ncell(grid))).
# TODO: keep the row order vector (county_fips) and note that columns = cell numbers.

pop_vec <- values(pop, mat = FALSE)   

weight_table <- coverage_table %>%
  mutate(population = pop_vec[cell],
         weight = coverage_fraction * coalesce(population, 0)) %>%
  filter(weight > 0) %>% 
  mutate(n_counties = nrow(counties))
 
W <- sparseMatrix(i = match(weight_table$GEOID, counties$GEOID), j = weight_table$cell, 
                  x =weight_table$weight, dims = c(nrow(counties), ncell(grid)), 
                  dimnames = list(counties$GEOID, NULL))

dim(W)                 # about 3108 x 825460
sum(W)                 # hundreds of millions
nnzero(W)
nrow(weight_table)

dim(gpw_us) == dim(grid)


# ---- 5. Checks (the CHECK IN) ----
# TODO: rowSums(W) vs ACS B01003 or a handful of known counties. Close, not equal.
# TODO: counties with rowSums(W) == 0 or tiny. List them with names.
# TODO: which CONUS counties are absent from W.
# TODO: a quick plot of a few counties' cells, or the sum of W's cell weights over
#       the whole grid vs. sum(pop): do they differ, and why?

census_coutns <- tidycensus::get_decennial(geography = "county",
                          variables = "P1_001N",  # This is the 2020 Decennial Total Pop variable
                          year = 2020) %>% 
  mutate(GEOID = str_pad(GEOID, width = 5, side = "left", pad = "0"))

  

dim(W)
nnzero(W) == nrow(weight_table)
w_pop <- rowSums(W)          # named by GEOID if you set dimnames
summary(w_pop)
sum(w_pop)                   # compare to sum(pop_vec, na.rm = TRUE) later

check <- data.frame(GEOID = counties$GEOID, w_pop = as.numeric(w_pop))

census_counts_clean <- census_coutns %>% left_join(counties %>% select(GEOID, STATEFP), by = "GEOID" ) %>%
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
  census_coutns %>% transmute(GEOID, NAME, census_pop = value),
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
covered      <- unique(weight_table$cell)
pop_covered  <- sum(pop_vec[covered], na.rm = TRUE)             # cells touched by any county
c(total          = total_pop,
  covered_cells  = pop_covered,
  W              = sum(W),
  outside_all_counties = total_pop - pop_covered,               # Canada, Mexico, ocean
  split_border_cells   = pop_covered - sum(W))                  # cells only partly inside counties

# ---- 5. Absent counties, three different senses ----
setdiff(counties$GEOID, coverage_table$GEOID)          # no overlap with the grid at all
names(w_pop)[w_pop == 0]                               # overlap, but zero population
setdiff(chk$GEOID[!is.na(chk$census_pop)], counties$GEOID)   # in Census, not in our shapefile
setdiff(counties$GEOID, chk$GEOID[!is.na(chk$census_pop)])   # in our shapefile, not in Census

# ---- 6. Save ----
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

saveRDS(list(W           = W,
             county_fips = counties$GEOID,             # row order of W
             n_cells     = ncell(grid),                # column count, in grid's cell order
             grid_dim    = dim(grid)[1:2],             # rows, cols: 596 x 1385
             grid_ext    = as.vector(ext(grid)),       # xmin, xmax, ymin, ymax
             pop_source  = basename(gpw_path)),
        file.path(OUT_DIR, "W_county_cell.rds"))

stopifnot(all(dim(chk_w$W) == c(length(chk_w$county_fips), chk_w$n_cells)),
          !anyNA(chk_w$W@x),
          all(rowSums(chk_w$W) > 0))