# Phase 1, step 4: wild cluster bootstrap (by state) for the three co-op triples,
# in the CORRECTED (saturated) model -- SPEC5_sat, not the seminar's SPEC5.
# fwildclusterboot 0.14.3 breaks on fixest models with fixed effects, so we remove
# the FEs once with demean() and bootstrap a plain model on the demeaned data
# (same coefficients and state-clustered t-stats; checked below).
# Writes output/tables/p1_coop_wild_bootstrap_sat.csv.

source("scripts/03_analysis/p1_00_setup.R")
library(fwildclusterboot)

B <- as.integer(Sys.getenv("BOOT_B", "9999"))   # override to test quickly

panel <- load_panel()
df    <- add_interactions(panel, "poverty_dm")
m5    <- fit_spec(df, SPEC5_sat)
stopifnot(nobs(m5) == nrow(df))                 # rows line up with df$state

# 1. Remove the fixed effects from y and X once
y  <- model.matrix(m5, type = "lhs")
X  <- model.matrix(m5, type = "rhs")
fe <- model.matrix(m5, type = "fixef")
Z  <- demean(cbind(y, X), fe)
colnames(Z)[1] <- "y_dm"

dd <- as.data.table(Z)
setnames(dd, make.names(names(dd)))             # factor(month)2 -> factor.month.2
dd[, state := df$state]

# 2. Plain regression on the demeaned data, no fixed effects
rhs <- setdiff(names(dd), c("y_dm", "state"))
m0  <- feols(as.formula(paste("y_dm ~", paste(rhs, collapse = " + "), "- 1")), data = dd)

# 3. Bootstrap each co-op triple (Rademacher weights, null imposed)
set.seed(123); dqrng::dqset.seed(123)
res <- lapply(COOP_TRIPLES, function(p)
  boottest(m0, param = p, clustid = "state", B = B))

# 4. Check against fixest's own state-clustered t-stats, then save
out <- rbindlist(lapply(seq_along(COOP_TRIPLES), function(i) {
  s <- summary(res[[i]])
  data.table(term = COOP_TRIPLES[i], estimate = s$estimate, t_stat = s$statistic,
             p_boot = s$p.value, ci_low = s$conf.low, ci_high = s$conf.high, B = B)
}))
t_fixest <- coeftable(m5, vcov = ~state)[COOP_TRIPLES, "t value"]
stopifnot(all(abs(out$t_stat - t_fixest) < 0.01))

print(out)
fwrite(out, file.path(OUT_DIR, "p1_coop_wild_bootstrap_sat.csv"))
