# Phase 1, step 3: robustness of the co-op triples.
#   - leave out the states that carry most of the co-op variation
#   - poverty fixed at each county's 2019 value
# All columns use state-clustered SEs. Writes output/tables/p1_coop_robustness.tex.

source("scripts/03_analysis/p1_00_setup.R")

panel <- load_panel()
df    <- add_interactions(panel, "poverty_dm")

# Uses SPEC5_sat (the corrected model: bin x coop/muni, pov x coop/muni, and the
# ownership main effects, on top of the seminar's triples). Pass spec = SPEC5 to
# get the old, unsaturated numbers instead.
m_all <- fit_spec(df, SPEC5_sat)
check_replication(fit_spec(df, SPEC5))   # sanity check against the seminar spec only

# Leave-out fits (FIPS state codes: 48 TX, 20 KS, 47 TN)
drop_and_fit <- function(states, spec = SPEC5_sat) fit_spec(df[!state %in% states], spec)
m_noTX   <- drop_and_fit("48")
m_noTXKS <- drop_and_fit(c("48", "20"))
m_noTN   <- drop_and_fit("47")
m_noTop3 <- drop_and_fit(c("47", "20", "48"))

# Poverty fixed at 2019 (a few counties have no 2019 row, so N is slightly smaller)
cat("Rows without 2019 poverty:", sum(is.na(df$pov19_dm)),
    "| counties:", uniqueN(df[is.na(pov19_dm), FIPS]), "\n")
m_pov19 <- fit_spec(add_interactions(panel, "pov19_dm"), SPEC5_sat)

models <- list(m_all, m_noTX, m_noTXKS, m_noTN, m_noTop3, m_pov19)
heads  <- c("All", "No TX", "No TX,KS", "No TN", "No TN,KS,TX", "Poverty 2019")

etable(models, keep = "x_pov_coop", headers = heads)   # print
etable(models, keep = "x_pov_coop", headers = heads,
       file = file.path(OUT_DIR, "p1_coop_robustness.tex"), replace = TRUE)
