# ============================================================
# 13_update_recent_data.R - Phase 7f: Recent Data Refresh
#
# Purpose:
#   Extend the original energy dataset beyond December 2022 so that
#   later scripts can evaluate post-2022 external-holdout forecasts.
#
# Important distinction:
#   - Historical pseudo-OOS: Jan 2015-Dec 2022, already completed.
#   - Post-2022 external holdout: actual CPI values observed after 2022.
#   - True forward forecast: months beyond observed CPI values, requiring
#     WTI assumptions or scenarios.
#
# This script does NOT estimate forecasting models. It only downloads,
# transforms, aligns, documents, and saves refreshed data.
# ============================================================

library(quantmod)
library(xts)
library(zoo)
library(tseries)

setwd("c:/Users/steve/OneDrive - IE University/Term 3/Research Capstone/midas_capstone")

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)

set.seed(42)

sample_start <- as.Date("2000-01-01")
original_end <- as.Date("2022-12-31")
recent_start <- as.Date("2023-01-01")
download_end <- Sys.Date()

cat("=== Phase 7f: Recent Data Refresh ===\n")
cat("Download window:", format(sample_start), "to", format(download_end), "\n")
cat("Original capstone sample ends:", format(original_end), "\n\n")

# FRED sometimes returns temporary 504 gateway timeouts, especially for
# daily series such as DCOILWTICO. Download each series separately, retry,
# and cache successful downloads so a later failure does not force us to
# start from zero.
get_fred_cached <- function(symbol, cache_file, label,
                            max_tries = 4L, sleep_seconds = 8L) {
  for (attempt in seq_len(max_tries)) {
    cat(sprintf("  %s attempt %d/%d...\n", label, attempt, max_tries))

    result <- tryCatch(
      getSymbols(symbol, src = "FRED", from = sample_start, to = download_end,
                 auto.assign = FALSE),
      error = function(e) e
    )

    if (inherits(result, "xts")) {
      saveRDS(result, cache_file)
      cat(sprintf("  %s downloaded and cached: %s\n", label, cache_file))
      return(result)
    }

    cat(sprintf("  %s download failed: %s\n", label, conditionMessage(result)))
    if (attempt < max_tries) {
      cat(sprintf("  Waiting %d seconds before retry...\n", sleep_seconds))
      Sys.sleep(sleep_seconds)
    }
  }

  if (file.exists(cache_file)) {
    cat(sprintf("  Using cached %s file because FRED is unavailable: %s\n",
                label, cache_file))
    return(readRDS(cache_file))
  }

  stop(sprintf(
    paste(
      "%s could not be downloaded and no cache exists.",
      "This is usually a temporary FRED/server issue.",
      "Run this script again later, or manually download the FRED CSV."
    ),
    label
  ))
}

# ============================================================
# STEP 1 - Download latest data from FRED
# ============================================================
cat("Downloading latest data from FRED...\n")

cpi_download <- get_fred_cached(
  "CPIENGSL",
  "data/raw/fred_CPIENGSL_latest.rds",
  "CPIENGSL"
)

wti_source <- "DCOILWTICO daily from FRED, converted to weekly last price"
wti_download <- tryCatch(
  get_fred_cached(
    "DCOILWTICO",
    "data/raw/fred_DCOILWTICO_latest.rds",
    "DCOILWTICO"
  ),
  error = function(e) {
    cat("\nDCOILWTICO daily download failed after retries.\n")
    cat("Falling back to WCOILWTICO, FRED's official weekly WTI series.\n")
    cat("Original error:", conditionMessage(e), "\n\n")
    wti_source <<- "WCOILWTICO weekly from FRED fallback"
    get_fred_cached(
      "WCOILWTICO",
      "data/raw/fred_WCOILWTICO_latest.rds",
      "WCOILWTICO"
    )
  }
)

imf_download <- get_fred_cached(
  "PNRGINDEXM",
  "data/raw/fred_PNRGINDEXM_latest.rds",
  "PNRGINDEXM"
)

cat("Download complete.\n\n")

# ============================================================
# STEP 2 - Clean levels data
# ============================================================
cpi_raw <- cpi_download
colnames(cpi_raw) <- "cpi_energy"
cpi_raw <- window(cpi_raw, start = sample_start, end = download_end)

wti_daily <- wti_download
colnames(wti_daily) <- "wti_usd_bbl"
wti_daily <- window(wti_daily, start = sample_start, end = download_end)
wti_daily <- na.locf(wti_daily, na.rm = FALSE)
wti_daily <- na.omit(wti_daily)

wti_weekly <- apply.weekly(wti_daily, last)
wti_weekly <- window(wti_weekly, start = sample_start, end = download_end)
colnames(wti_weekly) <- "wti_usd_bbl"

# Save the weekly WTI level series as a raw cache for the future-forecast
# extension. This is the stable high-frequency input used by the MIDAS design:
# 4 weekly WTI observations per monthly CPI observation.
saveRDS(wti_weekly, "data/raw/fred_WTI_weekly_latest.rds")
saveRDS(
  list(
    series = wti_weekly,
    source = wti_source,
    saved_on = Sys.Date(),
    note = paste(
      "Weekly WTI level series used for Phase 7f.",
      "If DCOILWTICO daily is available, this is daily WTI converted to weekly last price.",
      "If the daily endpoint times out, this is FRED WCOILWTICO official weekly WTI."
    )
  ),
  "data/raw/fred_WTI_weekly_latest_with_metadata.rds"
)

imf_raw <- imf_download
colnames(imf_raw) <- "imf_energy_idx"
imf_raw <- window(imf_raw, start = sample_start, end = download_end)

cat("Latest available observations:\n")
cat("  CPIENGSL monthly:", format(end(cpi_raw), "%Y-%m"), "| n =", nrow(cpi_raw), "\n")
cat("  WTI weekly:      ", format(end(wti_weekly), "%Y-%m-%d"), "| n =", nrow(wti_weekly), "\n")
cat("  WTI source:      ", wti_source, "\n")
cat("  WTI raw cache:   data/raw/fred_WTI_weekly_latest.rds\n")
cat("  PNRGINDEXM:      ", format(end(imf_raw), "%Y-%m"), "| n =", nrow(imf_raw), "\n\n")

# ============================================================
# STEP 3 - Transform to log-differences
# ============================================================
cpi_monthly <- diff(log(cpi_raw))
cpi_monthly <- na.omit(cpi_monthly)
colnames(cpi_monthly) <- "d_log_cpi_energy"

wti_wk <- diff(log(wti_weekly))
wti_wk <- na.omit(wti_wk)
colnames(wti_wk) <- "d_log_wti"

imf_monthly <- diff(log(imf_raw))
imf_monthly <- na.omit(imf_monthly)
colnames(imf_monthly) <- "d_log_imf_energy"

# Post-2022 subsets are created AFTER differencing so that Jan 2023
# correctly uses Dec 2022 as its previous observation.
cpi_post2022 <- window(cpi_monthly, start = recent_start)
wti_post2022 <- window(wti_wk, start = recent_start)
imf_post2022 <- window(imf_monthly, start = recent_start)

# ============================================================
# STEP 4 - Build exactly m = 4 weekly WTI matrix by CPI month
# ============================================================
build_week_matrix <- function(wti_series, cpi_index, m = 4L) {
  months <- as.yearmon(cpi_index)
  wti_dates <- as.Date(index(wti_series))
  wti_vals <- as.numeric(wti_series)
  n <- length(months)
  x_mat <- matrix(NA_real_, nrow = n, ncol = m)

  for (i in seq_len(n)) {
    m_start <- as.Date(months[i])
    m_end <- as.Date(months[i] + 1 / 12) - 1L
    in_month <- which(wti_dates >= m_start & wti_dates <= m_end)

    if (length(in_month) >= m) {
      sel <- tail(in_month, m)
    } else {
      before <- which(wti_dates < m_start)
      pad <- tail(before, m - length(in_month))
      sel <- c(pad, in_month)
    }

    if (length(sel) == m) {
      x_mat[i, ] <- wti_vals[sel]
    }
  }

  colnames(x_mat) <- paste0("wti_m0_w", seq_len(m))
  rownames(x_mat) <- format(as.Date(months), "%Y-%m")
  x_mat
}

x_mat_full <- build_week_matrix(wti_wk, index(cpi_monthly), m = 4L)
x_all_full <- as.vector(t(x_mat_full))
x_monthly_full <- rowMeans(x_mat_full, na.rm = TRUE)

post_rows <- as.Date(index(cpi_monthly)) >= recent_start
x_mat_post2022 <- x_mat_full[post_rows, , drop = FALSE]
x_monthly_post2022 <- x_monthly_full[post_rows]

# Keep only months where CPI actual and WTI weekly design are complete.
complete_post <- !is.na(as.numeric(cpi_post2022)) &
  complete.cases(x_mat_post2022)

post2022_design <- list(
  y_actual = as.numeric(cpi_post2022)[complete_post],
  dates = as.Date(index(cpi_post2022))[complete_post],
  x_mat = x_mat_post2022[complete_post, , drop = FALSE],
  x_monthly = x_monthly_post2022[complete_post],
  train_end = original_end,
  m = 4L,
  note = paste(
    "Post-2022 external holdout design.",
    "Actual CPI values are observed and can be used for evaluation."
  )
)

full_recent_design <- list(
  y_all = as.numeric(cpi_monthly),
  dates = as.Date(index(cpi_monthly)),
  x_mat = x_mat_full,
  x_all = x_all_full,
  x_monthly = x_monthly_full,
  m = 4L,
  original_end = original_end,
  latest_cpi_month = as.Date(end(cpi_monthly)),
  latest_wti_week = as.Date(end(wti_wk))
)

# ============================================================
# STEP 5 - Stationarity checks on refreshed sample
# ============================================================
adf_safe <- function(x) {
  out <- tryCatch(adf.test(na.omit(as.numeric(x))), error = function(e) NULL)
  if (is.null(out)) return(NA_real_)
  round(out$p.value, 4)
}

stationarity_tbl <- data.frame(
  Series = c(
    "CPI Energy levels",
    "CPI Energy log-diff",
    "WTI weekly levels",
    "WTI weekly log-diff",
    "IMF Energy levels",
    "IMF Energy log-diff"
  ),
  ADF_p_value = c(
    adf_safe(cpi_raw),
    adf_safe(cpi_monthly),
    adf_safe(wti_weekly),
    adf_safe(wti_wk),
    adf_safe(imf_raw),
    adf_safe(imf_monthly)
  )
)
stationarity_tbl$Interpretation <- ifelse(
  stationarity_tbl$ADF_p_value < 0.05,
  "stationary",
  "non-stationary"
)

# ============================================================
# STEP 6 - Save refreshed data separately from original files
# ============================================================
saveRDS(cpi_raw, "data/processed/recent_cpi_energy_levels_monthly.rds")
saveRDS(wti_weekly, "data/processed/recent_wti_levels_weekly.rds")
saveRDS(imf_raw, "data/processed/recent_imf_energy_levels_monthly.rds")

saveRDS(cpi_monthly, "data/processed/recent_cpi_energy_log_diff_monthly.rds")
saveRDS(wti_wk, "data/processed/recent_wti_log_diff_weekly.rds")
saveRDS(imf_monthly, "data/processed/recent_imf_energy_log_diff_monthly.rds")

saveRDS(cpi_post2022, "data/processed/post2022_cpi_energy_log_diff_monthly.rds")
saveRDS(wti_post2022, "data/processed/post2022_wti_log_diff_weekly.rds")
saveRDS(imf_post2022, "data/processed/post2022_imf_energy_log_diff_monthly.rds")

saveRDS(full_recent_design, "data/processed/recent_midas_design_full.rds")
saveRDS(post2022_design, "data/processed/post2022_external_holdout_design.rds")

summary_tbl <- data.frame(
  Item = c(
    "Download date",
    "Original sample end",
    "Latest CPI month",
    "Latest WTI week",
    "WTI source",
    "WTI weekly raw cache",
    "Latest IMF month",
    "Full monthly log-diff observations",
    "Post-2022 evaluable months",
    "MIDAS weekly observations per month"
  ),
  Value = c(
    format(Sys.Date(), "%Y-%m-%d"),
    format(original_end, "%Y-%m-%d"),
    format(end(cpi_monthly), "%Y-%m"),
    format(end(wti_wk), "%Y-%m-%d"),
    wti_source,
    "data/raw/fred_WTI_weekly_latest.rds",
    format(end(imf_monthly), "%Y-%m"),
    nrow(cpi_monthly),
    length(post2022_design$y_actual),
    "4"
  )
)

write.csv(summary_tbl, "output/tables/recent_data_summary.csv", row.names = FALSE)
write.csv(stationarity_tbl, "output/tables/recent_stationarity_tests.csv", row.names = FALSE)

# ============================================================
# STEP 7 - Console summary
# ============================================================
cat("=== Recent data summary ===\n")
print(summary_tbl, row.names = FALSE)

cat("\n=== ADF stationarity tests on refreshed sample ===\n")
print(stationarity_tbl, row.names = FALSE)

cat("\nSaved refreshed data files:\n")
cat("  data/processed/recent_* files\n")
cat("  data/processed/post2022_* files\n")
cat("  data/processed/recent_midas_design_full.rds\n")
cat("  data/processed/post2022_external_holdout_design.rds\n")
cat("  output/tables/recent_data_summary.csv\n")
cat("  output/tables/recent_stationarity_tests.csv\n")

cat("\nNext script:\n")
cat("  R/14_future_forecast_extension.R will train on 2000-2022 and\n")
cat("  evaluate the post-2022 external holdout.\n")
