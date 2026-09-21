import requests
import os
from datetime import datetime, timedelta
import time

# ── CONFIG ───────────────────────────────────────────────────────────────────
BASE_DIR  = "/Users/aliabonanno/public_policy_project/prism"
BASE_URL  = "https://services.nacse.org/prism/data/public/4km"

# We need 2015-2024 for the main panel
# Starting 2012 for robustness but 2015+ is what matters
START_DATE = datetime(2015, 1, 1)
END_DATE   = datetime(2024, 12, 31)

VARIABLES = ["tmean", "tmax"]

# ── DOWNLOAD ─────────────────────────────────────────────────────────────────
for var in VARIABLES:
    var_dir = os.path.join(BASE_DIR, var)
    os.makedirs(var_dir, exist_ok=True)

    current = START_DATE
    downloaded = 0
    skipped    = 0
    failed     = []

    print(f"\nDownloading {var} from {START_DATE.date()} to {END_DATE.date()}")
    total_days = (END_DATE - START_DATE).days + 1
    print(f"Total days: {total_days}")

    while current <= END_DATE:
        date_str  = current.strftime("%Y%m%d")
        filename  = f"PRISM_{var}_{date_str}.zip"
        outpath   = os.path.join(var_dir, filename)

        # Skip if already downloaded and valid size
        if os.path.exists(outpath) and os.path.getsize(outpath) > 100000:
            skipped += 1
            current += timedelta(days=1)
            continue

        url = f"{BASE_URL}/{var}/{date_str}"

        try:
            r = requests.get(url, timeout=30)
            if r.status_code == 200 and len(r.content) > 100000:
                with open(outpath, "wb") as f:
                    f.write(r.content)
                downloaded += 1
                if downloaded % 100 == 0:
                    print(f"  {var}: {downloaded} downloaded, "
                          f"{skipped} skipped, date: {date_str}")
            else:
                failed.append((date_str, r.status_code, len(r.content)))

        except Exception as e:
            failed.append((date_str, "ERROR", str(e)))

        time.sleep(0.1)  # be polite to server
        current += timedelta(days=1)

    print(f"\n{var} complete: {downloaded} downloaded, "
          f"{skipped} skipped, {len(failed)} failed")
    if failed:
        print(f"First 5 failures: {failed[:5]}")

print("\nAll downloads complete.")