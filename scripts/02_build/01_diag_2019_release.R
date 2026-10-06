# Diagnostics on EIA's 2019 release: where do short-form respondents live, which
# utilities are missing in 2019, does the ownership panel agree with EIA's own Frame
# file, and how many co-op counties are served only by short-form co-ops?
# This is the evidence behind the "2019" paragraph of the data section (CLAUDE.md 3.4).
#
# Reads the annual zips in data/raw/eia/ (run p2_01_get_eia.R first). Reads each file
# straight from its zip into a temp folder. Run from the repo root (~/thesis).

library(readxl)
library(dplyr)
library(tidyr)

RAW   <- "data/raw/eia"
YEARS <- 2015:2024
if (!file.exists(file.path(RAW, "f8612019.zip"))) stop("Run p2_01_get_eia.R first.")
dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)

TMP <- file.path(tempdir(), "eia861_diag"); dir.create(TMP, showWarnings = FALSE)
rd  <- function(...) suppressWarnings(suppressMessages(read_excel(...)))

# Path to one file inside a year's zip (extracted on demand), or NA if the year lacks it.
get_file <- function(y, pattern) {
  zp <- file.path(RAW, sprintf("f861%d.zip", y)); f <- sprintf(pattern, y)
  if (!f %in% unzip(zp, list = TRUE)$Name) return(NA_character_)
  unzip(zp, files = f, exdir = file.path(TMP, y), junkpaths = TRUE)
  file.path(TMP, y, f)
}
ids_of <- function(d) unique(na.omit(suppressWarnings(as.numeric(d[["Utility Number"]]))))

# Column index of the RESIDENTIAL customer "Count" column, found from the banner rows.
res_col <- function(path) {
  b <- suppressMessages(read_excel(path, col_names = FALSE, n_max = 3)); r1 <- unlist(b[1, ]); r3 <- unlist(b[3, ])
  for (i in seq_along(r1)) if (is.na(r1[i]) && i > 1) r1[i] <- r1[i - 1]
  which(trimws(r1) == "RESIDENTIAL" & trimws(r3) == "Count")
}

# ---- Read everything once ----------------------------------------------------
keys <- list(); ud_n <- sf_n <- su_n <- fr_n <- st_n <- list(); frame <- list(); terr <- list(); sfres <- list()
for (y in YEARS) {
  ud <- rd(get_file(y, "Utility_Data_%d.xlsx"), skip = 1)
  ud <- ud |> mutate(short_form = if ("Short Form" %in% names(ud)) `Short Form` %in% "Y" else FALSE) |>
    filter(!is.na(`Utility Number`)) |>
    transmute(year = y, utility_id = `Utility Number`, State, ownership_raw = trimws(`Ownership Type`), short_form)
  sfp <- get_file(y, "Short_Form_%d.xlsx"); sf <- NULL
  if (!is.na(sfp)) {
    sf <- rd(sfp) |> filter(!is.na(`Utility Number`))
    ud <- bind_rows(ud, transmute(sf, year = y, utility_id = `Utility Number`, State, ownership_raw = trimws(Ownership), short_form = TRUE))
  }
  keys[[as.character(y)]] <- ud

  sup <- get_file(y, "Sales_Ult_Cust_%d.xlsx"); idx <- res_col(sup)
  su  <- rd(sup, skip = 2); names(su)[idx] <- "res"
  su  <- mutate(su, uid = suppressWarnings(as.numeric(`Utility Number`)), res = suppressWarnings(as.numeric(res)))
  frp <- get_file(y, "Frame_%d.xlsx"); fr <- if (is.na(frp)) NULL else rd(frp) |> filter(!is.na(`Utility Number`))
  st  <- rd(get_file(y, "Service_Territory_%d.xlsx")) |> filter(!is.na(`Utility Number`))

  sf_ids <- unique(if (y == 2019) filter(ud, short_form)$utility_id else if (is.null(sf)) numeric() else sf$`Utility Number`)
  sfres[[as.character(y)]] <- data.frame(year = y, short_form_utils = length(sf_ids),
    in_Sales_Ult_Cust = sum(sf_ids %in% su$uid), with_residential = length(unique(su$uid[su$uid %in% sf_ids & !is.na(su$res) & su$res > 0])))
  frame[[as.character(y)]] <- fr
  terr[[as.character(y)]]  <- transmute(st, utility_id = `Utility Number`, State, County)
  ud_n[[as.character(y)]] <- length(ids_of(rd(get_file(y, "Utility_Data_%d.xlsx"), skip = 1)))
  sf_n[[as.character(y)]] <- if (is.null(sf)) NA else length(ids_of(sf))
  su_n[[as.character(y)]] <- length(unique(su$uid[!is.na(su$uid)]))
  fr_n[[as.character(y)]] <- if (is.null(fr)) NA else length(ids_of(fr))
  st_n[[as.character(y)]] <- length(unique(st$`Utility Number`))
}
keys <- bind_rows(keys)

# ---- 1. Where do short-form respondents live? (distinct utility ids per file) ----
cat("\n==== 1. Distinct utility ids per file and year ====\n")
t1 <- data.frame(year = YEARS, Utility_Data = unlist(ud_n), Short_Form_file = unlist(sf_n),
                 Sales_Ult_Cust = unlist(su_n), Frame = unlist(fr_n), Service_Territory = unlist(st_n))
print(t1, row.names = FALSE); write.csv(t1, "output/tables/p2_diag_ids_by_file.csv", row.names = FALSE)

# ---- 2. 'Holes': present the year before and after, missing in the year -----------
k <- distinct(keys, year, utility_id, State)
at <- function(y) k |> filter(year == y) |> select(utility_id, State)
holes_in <- function(y) anti_join(inner_join(at(y - 1), at(y + 1), by = c("utility_id", "State")), at(y), by = c("utility_id", "State"))
cat("\n==== 2. Utility-states present in year-1 and year+1 but missing in year ====\n")
t2 <- data.frame(year = 2016:2023, holes = sapply(2016:2023, function(y) nrow(holes_in(y))))
print(t2, row.names = FALSE)

# ---- 3. The 2019 holes: what are they, and are they anywhere in the 2019 release? ----
h19    <- holes_in(2019)
absent <- filter(h19, !utility_id %in% at(2019)$utility_id)
cat("\n==== 3. The", nrow(h19), "2019 holes ====\n")
cat("  listed in 2019 under a DIFFERENT state (state-code mismatch):", nrow(h19) - nrow(absent), "\n")
cat("  not in the 2019 panel under any state:", nrow(absent), "utility-states /", n_distinct(absent$utility_id), "ids\n")
cat("  composition (2018 labels):\n")
print(as.data.frame(h19 |> left_join(filter(keys, year == 2018), by = c("utility_id", "State")) |> count(short_form, ownership_raw)), row.names = FALSE)

zp19 <- file.path(RAW, "f8612019.zip")
xl <- grep("\\.xlsx$", unzip(zp19, list = TRUE)$Name, value = TRUE); xl <- xl[!grepl("Form\\.xlsx$", xl)]
unzip(zp19, files = xl, exdir = file.path(TMP, "all2019"), junkpaths = TRUE)
n_sheets <- 0; found <- numeric()
for (f in file.path(TMP, "all2019", xl)) for (sh in excel_sheets(f)) {
  raw <- tryCatch(rd(f, sheet = sh, col_names = FALSE, n_max = 6), error = function(e) NULL)
  if (is.null(raw) || nrow(raw) == 0) next
  hdr <- which(apply(raw, 1, function(r) any(trimws(as.character(r)) == "Utility Number")))[1]
  if (is.na(hdr)) next
  d <- rd(f, sheet = sh, skip = hdr - 1); if (!"Utility Number" %in% names(d)) next
  n_sheets <- n_sheets + 1; found <- union(found, intersect(ids_of(d), absent$utility_id))
}
cat("  searched", n_sheets, "sheets in", length(xl), "spreadsheets of the 2019 release;",
    "absent ids found in any of them:", length(found), "of", n_distinct(absent$utility_id), "\n")

# ---- 4. Do short-form respondents have residential data? (Sales_Ult_Cust) ------------
cat("\n==== 4. Short-form utilities in Sales_Ult_Cust, with a residential customer count > 0 ====\n")
t4 <- bind_rows(sfres); print(t4, row.names = FALSE)

# ---- 5. Does the panel match EIA's own Frame file? (distinct ids per ownership_raw) ----
cats <- c("Cooperative", "Municipal", "Investor Owned", "Political Subdivision", "State", "Municipal Mktg Authority", "Federal")
t5 <- bind_rows(lapply(2016:2024, function(y) {
  fr <- frame[[as.character(y)]]
  f <- fr |> mutate(own = trimws(Ownership)) |> filter(own %in% cats) |> group_by(own) |> summarise(frame = n_distinct(`Utility Number`), .groups = "drop")
  p <- keys |> filter(year == y, ownership_raw %in% cats) |> group_by(own = ownership_raw) |> summarise(panel = n_distinct(utility_id), .groups = "drop")
  full_join(f, p, by = "own") |> mutate(year = y, diff = panel - frame)
}))
cat("\n==== 5. Panel minus Frame, distinct utility ids (0 = exact match) ====\n")
print(as.data.frame(t5 |> select(year, own, diff) |> pivot_wider(names_from = own, values_from = diff)), row.names = FALSE)
write.csv(t5, "output/tables/p2_diag_frame_check.csv", row.names = FALSE)

# ---- 6. Co-op counties served ONLY by short-form co-ops (state-aware join) --------------
t6 <- bind_rows(lapply(YEARS, function(y) {
  coop <- filter(keys, year == y, ownership_raw == "Cooperative"); tt <- terr[[as.character(y)]]
  cn <- function(c) inner_join(tt, distinct(c, utility_id, State), by = c("utility_id", "State")) |> distinct(State, County)
  all <- cn(coop); det <- cn(filter(coop, !short_form))
  data.frame(year = y, counties_any_coop = nrow(all), counties_with_detail_coop = nrow(det),
             only_short_form = nrow(anti_join(all, det, by = c("State", "County"))))
})) |> mutate(share_only_short_form = round(only_short_form / counties_any_coop, 3))
cat("\n==== 6. Co-op counties served only by short-form co-ops ====\n")
print(t6, row.names = FALSE); write.csv(t6, "output/tables/p2_diag_shortform_only_counties.csv", row.names = FALSE)

# ---- 7. 2019 -> 2020: who moved between the detail form and the short form? ------------
# Utility-states present in BOTH years, kept ownership categories only (as in the panel).
kept <- c("Cooperative", "Municipal", "Investor Owned", "Political Subdivision", "State", "Municipal Mktg Authority", "Federal")
ykeys <- function(y) keys |> filter(year == y, ownership_raw %in% kept) |> distinct(utility_id, State, ownership_raw, short_form)
a <- ykeys(2019) |> rename(sf19 = short_form); b <- ykeys(2020) |> rename(sf20 = short_form) |> select(-ownership_raw)
j <- inner_join(a, b, by = c("utility_id", "State"))
cat("\n==== 7. 2019 -> 2020, utility-states present in both years ====\n")
print(table(`2019` = ifelse(j$sf19, "short_form", "detail"), `2020` = ifelse(j$sf20, "short_form", "detail")))
cat("detail -> short_form, by raw label:\n"); print(as.data.frame(count(filter(j, !sf19, sf20), ownership_raw)), row.names = FALSE)
cat("present only in 2019 (exit):", nrow(anti_join(a, b, by = c("utility_id", "State"))),
    "| only in 2020 (entry):", nrow(anti_join(b, a, by = c("utility_id", "State"))), "\n")
