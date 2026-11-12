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

# ---- 0. Inputs ----
W_path <- "data/intermediate/W_county_cell.rds"
w_obj  <- readRDS(W_path)            # W, county_fips, n_cells, grid_dim, grid_ext
W   <- w_obj$W


RAW_GPW       <- "data/raw/gpw"
RAW_NCLIM <- "data/raw/nclimgrid/grids"
OUT_DIR   <- "data/intermediate"
YEARS     <- 2015:2024

EDGES <- list(
  tavg = c(-Inf, -5, 0, 5, 10, 15, 20, 25, 30, Inf),     # reference (15,20]
  tmax = c(-Inf,  5, 10, 15, 20, 25, 30, 35, 40, Inf))   # reference (20,25]

bin_labels <- list(
  tavg_names = c("bin_neg_inf", "bin_m5_0", "bin_0_5", "bin_5_10", "bin_10_15", "bin_15_20",
                 "bin_20_25", "bin_25_30", "bin_pos_inf"),
  tmax_names = c("bin_neg_inf", "bin_5_10", "bin_10_15", "bin_15_20",
                 "bin_20_25", "bin_25_30", "bin_30_35", "bin_35_40", "bin_pos_inf")
)

temperature_bins <- list(
  tavg = list(breaks = EDGES$tavg, labels = bin_labels$tavg_names),
  tmax = list(breaks = EDGES$tmax, labels = bin_labels$tmax_names)
)


bin_month <- function(nc_path, measure, W, edges) {
  r <- rast(nc_path, subds = measure)

  stopifnot(
    as.integer(dim(r)[1:2]) == as.integer(w_obj$grid_dim),
    as.vector(terra::ext(r)) == as.vector(w_obj$grid_ext)
  )
  
  x <- values(r)          # matrix: cells (rows) x days (columns), in the grid's cell order
  # TODO: valid <- !is.na(x)           (cells x days, logical)
  # TODO: denominator: W %*% valid, giving counties x days.
  #       (Matrix multiplication needs numeric; what do you have to convert?)
  valid <- !is.na(x)
  storage.mode(valid) <- "numeric"
  
  denom <- W %*% valid
  
  edges <- temperature_bins[[measure]]$breaks
  labels <- temperature_bins[[measure]]$labels 
  
  n_bins <- length(edges) - 1
  
  bin_shares <- vector("list", n_bins)
  names(bin_shares) <- labels 
  
  bin_days <- matrix(NA_real_, nrow = nrow(W), ncol = n_bins)
  colnames(bin_days) <- labels
  rownames(bin_days) <- rownames(W)
  
  for (b in seq_len(n_bins)) {
    lo <- edges[b]
    hi <- edges[b+1]
    
    in_bin <- (x>lo) & (x<= hi)
    in_bin[is.na(in_bin)] <- FALSE
    storage.mode(in_bin) <- "numeric"
    
    num <- W %*% in_bin #counties x days in a bin 
    share <- num / denom #pop share in the particular bin, per each county-day (county days in a bin divided by total bins)
    
    bin_shares[[b]] <- share 
    bin_days[, b]   <- rowSums(share)

  }
  
  return(list(
    daily_shares = bin_shares,
    bin_days = bin_days))
  
  # TODO return a list: daily shares per bin (to check), and bin-days = rowSums over days
}


res <- bin_month(file.path(RAW_NCLIM, "ncdd-202007-grd-scaled.nc"), "tavg", W, EDGES$tavg)

# ---- 3. Checks (the CHECK IN) ----
# TODO: for every county-day, shares across the bins sum to 1 (within tolerance).

county_day_sums <- Reduce("+", res$daily_shares)

range(county_day_sums, na.rm = TRUE)

# TODO: for every county, bin-days across the bins sum to 31.

bd <- as.data.frame(res$bin_days) # counties x bins, row_names = GEOID 
bd$county_fips <- rownames(res$bin_days)
bd$year <- 2020 
bd$month <- 7
bd$measure <- "tavg"

bin_cols <- grep("^bin_", names(bd), value = TRUE)    # only the bin columns
bd$n_days <- rowSums(bd[, bin_cols])
range(bd$n_days)                                       # want 31 and 31, within ~1e-9
all(abs(bd$n_days - 31) < 1e-8)

bd[bd$county_fips %in% c("01001", "04013", "23003"), c("county_fips", bin_cols)]

range(bd$n_days)                       # all 3,108 counties
all(abs(bd$n_days - 31) < 1e-8)


monthly_file_names <- sort(list.files(RAW_NCLIM, pattern = "*.nc", full.names = TRUE))

tavg_results <- setNames(lapply(monthly_file_names, bin_month, measure = "tavg", W = W, 
                                 edges = EDGES$tavg), basename(monthly_file_names))

tmax_results <-  setNames(lapply(monthly_file_names, bin_month, measure = "tmax", W = W, 
                                 edges = EDGES$tmax), basename(monthly_file_names))


tavg_res_list <- lapply(tavg_results, function(tavg_results) {
  bd <- as.data.frame(tavg_results$bin_days) # counties x bins, row_names = GEOID 
  bd$county_fips <- rownames(tavg_results$bin_days)
  bd
})

tmax_res_list <- lapply(tmax_results, function(tmax_results) {
  bd <- as.data.frame(tmax_results$bin_days) # counties x bins, row_names = GEOID 
  bd$county_fips <- rownames(tmax_results$bin_days)
  bd
})

tavg_res <- bind_rows(tavg_res_list, .id = "file") %>%
  mutate(
    date = str_extract(basename(file), "\\d{6}"),
    year  = as.integer(substr(date, 1, 4)),
    month = as.integer(substr(date, 5, 6))
  )

tmax_res <- bind_rows(tmax_res_list, .id = "file") %>%
  mutate(
    date = str_extract(basename(file), "\\d{6}"),
    year  = as.integer(substr(date, 1, 4)),
    month = as.integer(substr(date, 5, 6))
  )

tavg_year <- tavg_res %>%
  mutate(measure = "tavg") %>%
  group_by(county_fips, year, measure) %>%
  summarise(across(starts_with("bin_"), sum), .groups = "drop") %>%
  mutate(n_days = rowSums(across(starts_with("bin_")))) %>%
  rename_with(~ paste0("tavg_", .x), starts_with("bin_"))

tmax_year <- tmax_res %>%
  mutate(measure = "tmax") %>%
  group_by(county_fips, year, measure) %>%
  summarise(across(starts_with("bin_"), sum), .groups = "drop") %>%
  mutate(n_days = rowSums(across(starts_with("bin_")))) %>%
  rename_with(~ paste0("tmax_", .x), starts_with("bin_"))


nrow(tavg_year)
nrow(tmax_year)
range(tavg_year$n_days)
range(tmax_year$n_days)

temp_year <- full_join(
  tavg_year %>% select(-measure, tavg_n_days = n_days),
  tmax_year %>% select(-measure, tmax_n_days = n_days),
  by = c("county_fips", "year"))


write_parquet(temp_year, file.path(OUT_DIR, "temperature_county_year.parquet"))

