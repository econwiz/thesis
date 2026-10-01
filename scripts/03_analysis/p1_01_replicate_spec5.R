# Phase 1, step 1-2: replicate the seminar's Spec 5 on the frozen legacy panel,
# then compare county- vs state-clustered standard errors.
# Run from the repo root (~/thesis), in a fresh R session.

source("scripts/03_analysis/p1_00_setup.R")
panel <- load_panel()

df    <- add_interactions(panel, "poverty_dm")
cat("Rows:", nrow(df), "| Counties:", uniqueN(df$FIPS), "| States:", uniqueN(df$state), "\n")

m5 <- fit_spec(df)
check_replication(m5)

# Same fit, county-clustered (seminar's SEs) vs state-clustered
etable(m5, m5, vcov = list(~FIPS, ~state),
       keep = "x_pov", headers = c("County clusters", "State clusters"))

etable(fit_spec(df), fit_spec(df, SPEC5_sat), keep = "x_pov_coop",
       headers = c("Spec 5", "Spec 5 + lower-order terms"))

m_dm  <- fit_spec(add_interactions(panel, "poverty_dm"),  SPEC5_sat)
m_raw <- fit_spec(add_interactions(panel, "poverty_raw"), SPEC5_sat)
cat("Invariant to poverty centering (should be TRUE now that SPEC5_sat has",
    "is_coop + is_muni):", isTRUE(all.equal(coef(m_dm)[COOP_TRIPLES], coef(m_raw)[COOP_TRIPLES])), "\n")

# Muni sign flip: does it hold up once we're not assuming iid errors?
MUNI_TRIPLES <- sub("coop", "muni", COOP_TRIPLES)
etable(m_dm, m_dm, vcov = list("iid", ~state), keep = "x_pov_muni",
       headers = c("IID (no clustering)", "State clusters"))
cat("\nbin8_25to30_x_pov_muni  IID p:",   round(coeftable(m_dm, vcov = "iid")[MUNI_TRIPLES[2], "Pr(>|t|)"], 4),
    " | state-clustered p:", round(coeftable(m_dm, vcov = ~state)[MUNI_TRIPLES[2], "Pr(>|t|)"], 4), "\n")