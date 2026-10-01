# Phase 1 shared setup: load the frozen seminar panel, build variables, define Spec 5.
# Sourced by p1_01, p1_02 and p1_03. Run from the repo root (~/thesis).

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
})

if (!file.exists("data/legacy/master_panel_monthly_fc.csv"))
  stop("Run from the repo root (~/thesis): open it as an RStudio project, or setwd() there.")

OUT_DIR <- Sys.getenv("P1_OUT", "output/tables")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

HOT_BINS <- c("bin7_20to25", "bin8_25to30", "bin9_over30")
COOP_TRIPLES <- paste0(HOT_BINS, "_x_pov_coop")

bins <- c("bin1_under_neg5", "bin2_neg5to0", "bin3_0to5", "bin4_5to10", "bin5_10to15", HOT_BINS)

# ---- Panel ------------------------------------------------------------------
# Rows are kept only if the regression uses them (matches the legacy PanelOLS drop):
# 333,127 rows / 2,793 counties.
load_panel <- function() {
  df <- fread("data/legacy/master_panel_monthly_fc.csv",
              colClasses = list(character = "FIPS"))
  df[, FIPS  := sprintf("%05d", as.integer(FIPS))]   # pad to 5-digit county FIPS
  df[, state := substr(FIPS, 1, 2)]                  # cluster variable

  key <- c("log_res_sales_per_customer", "pct_below_150pct_poverty", "prcp_monthly_mm",
           "bin1_under_neg5", "bin2_neg5to0", "bin3_0to5", "bin4_5to10",
           "bin5_10to15", HOT_BINS)
  demo <- c("median_hh_income", "pct_white", "pct_black", "pct_hispanic",
            "pct_bachelors_plus", "unemployment_rate")
  df <- na.omit(df, cols = c(key, demo))

  df[, is_coop := as.integer(dominant_ownership_type == "Cooperative")]
  df[, is_muni := as.integer(dominant_ownership_type == "Municipal")]
  df[, prcp_sq := prcp_monthly_mm^2]

  # Poverty: yearly ACS 5-yr value (the seminar's version), raw and demeaned over the sample.
  df[, poverty_raw := pct_below_150pct_poverty]
  df[, poverty_dm  := pct_below_150pct_poverty - mean(pct_below_150pct_poverty)]

  # Alternative: each county's 2019 value (ACS 2015-19), fixed over time.
  # Lookup by match() keeps the row order (a merge would reorder rows).
  pov19 <- df[year == 2019, .(pov2019 = mean(pct_below_150pct_poverty)), by = FIPS]
  df[, pov2019  := pov19$pov2019[match(FIPS, pov19$FIPS)]]
  df[, pov19_dm := pov2019 - mean(pov2019, na.rm = TRUE)]

  stopifnot(nrow(df) == 333127, uniqueN(df$FIPS) == 2793, all(nchar(df$FIPS) == 5))
  df
}

# ---- Interactions -----------------------------------------------------------
# Adds pv (the poverty main effect), bin x pv, bin x pv x coop / muni, bin x coop / muni,
# and pv x coop / muni. `povvar` is the name of any poverty column ("poverty_raw",
# "poverty_dm", "pov19_dm", ...). Returns a copy.
add_interactions <- function(dat, povvar) {
  d  <- copy(dat)
  pv <- d[[povvar]]
  set(d, j = "pv", value = pv)
  for (b in bins) {
    set(d, j = paste0(b, "_x_pov"),      value = d[[b]] * pv)
    set(d, j = paste0(b, "_x_pov_coop"), value = d[[b]] * pv * d$is_coop)
    set(d, j = paste0(b, "_x_pov_muni"), value = d[[b]] * pv * d$is_muni)
    set(d, j = paste0(b, "_x_coop"), value = d[[b]] * d$is_coop)
    set(d, j = paste0(b, "_x_muni"), value = d[[b]] * d$is_muni)
  }
  set(d, j = "pov_x_coop", value = pv * d$is_coop)
  set(d, j = "pov_x_muni", value = pv * d$is_muni)
  d
}

# ---- Spec 5 (seminar): county FE + year FE + month dummies -------------------
SPEC5 <- log_res_sales_per_customer ~
  bin1_under_neg5 + bin2_neg5to0 + bin3_0to5 + bin4_5to10 + bin5_10to15 +
  bin7_20to25 + bin8_25to30 + bin9_over30 +
  bin7_20to25_x_pov + bin8_25to30_x_pov + bin9_over30_x_pov +
  bin7_20to25_x_pov_coop + bin8_25to30_x_pov_coop + bin9_over30_x_pov_coop +
  bin7_20to25_x_pov_muni + bin8_25to30_x_pov_muni + bin9_over30_x_pov_muni +
  prcp_monthly_mm + prcp_sq + factor(month) +
  median_hh_income + pct_white + pct_black + pct_hispanic +
  pct_bachelors_plus + unemployment_rate |
  FIPS + year

SPEC5_sat <- log_res_sales_per_customer ~
  bin1_under_neg5 + bin2_neg5to0 + bin3_0to5 + bin4_5to10 + bin5_10to15 +
  bin7_20to25 + bin8_25to30 + bin9_over30 +
  bin7_20to25_x_pov + bin8_25to30_x_pov + bin9_over30_x_pov +
  bin7_20to25_x_coop + bin8_25to30_x_coop + bin9_over30_x_coop +
  bin7_20to25_x_muni + bin8_25to30_x_muni + bin9_over30_x_muni +
  pv + is_coop + is_muni + pov_x_coop + pov_x_muni +
  bin7_20to25_x_pov_coop + bin8_25to30_x_pov_coop + bin9_over30_x_pov_coop +
  bin7_20to25_x_pov_muni + bin8_25to30_x_pov_muni + bin9_over30_x_pov_muni +
  prcp_monthly_mm + prcp_sq + factor(month) +
  median_hh_income + pct_white + pct_black + pct_hispanic +
  pct_bachelors_plus + unemployment_rate |
  FIPS + year

fit_spec <- function(d, spec = SPEC5, cluster = ~state) feols(spec, data = d, cluster = cluster)

# Seminar reports co-op triples of about -0.025 (bin 8) and -0.038 (bin 9).
check_replication <- function(m) {
  stopifnot(abs(coef(m)["bin8_25to30_x_pov_coop"] - (-0.0248)) < 0.001,
            abs(coef(m)["bin9_over30_x_pov_coop"] - (-0.0378)) < 0.001)
}
