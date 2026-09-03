"""Download DGHS daily dengue press releases.

DGHS publishes one PDF per day at a predictable path, so there is no index to
scrape:

    https://old.dghs.gov.bd/images/docs/vpr/YYYYMMDD_dengue_all.pdf

Downloads are cached on disk. A day with no release (holidays, occasional gaps)
returns None rather than raising — the builder carries the previous day forward.
"""

from __future__ import annotations

import logging
import time
from datetime import date
from pathlib import Path

import requests

LOG = logging.getLogger(__name__)

BASE_URL = "https://old.dghs.gov.bd/images/docs/vpr"
USER_AGENT = "DengueWatchBD/1.0 (+public health data sync; contact: ops@example.org)"

# Be a considerate client of a government server: one request at a time, paced.
REQUEST_DELAY_SECONDS = 1.0
TIMEOUT_SECONDS = 45
MAX_ATTEMPTS = 3


def url_for(day: date) -> str:
    return f"{BASE_URL}/{day:%Y%m%d}_dengue_all.pdf"


def fetch_pdf(day: date, cache_dir: Path, session: requests.Session | None = None) -> Path | None:
    """Return a local path to that day's PDF, or None if DGHS published none."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    cached = cache_dir / f"{day:%Y%m%d}_dengue_all.pdf"
    if cached.exists() and cached.stat().st_size > 0:
        return cached

    missing_marker = cache_dir / f"{day:%Y%m%d}.missing"
    if missing_marker.exists():
        return None

    owns_session = session is None
    session = session or requests.Session()
    session.headers.setdefault("User-Agent", USER_AGENT)

    try:
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                response = session.get(url_for(day), timeout=TIMEOUT_SECONDS)
            except requests.RequestException as exc:
                LOG.warning("%s: request failed (attempt %d/%d): %s",
                            day, attempt, MAX_ATTEMPTS, exc)
                time.sleep(REQUEST_DELAY_SECONDS * attempt)
                continue

            if response.status_code == 404:
                LOG.info("%s: no press release published", day)
                missing_marker.touch()
                return None
            if response.status_code != 200:
                LOG.warning("%s: HTTP %d (attempt %d/%d)",
                            day, response.status_code, attempt, MAX_ATTEMPTS)
                time.sleep(REQUEST_DELAY_SECONDS * attempt)
                continue
            if not response.content.startswith(b"%PDF"):
                # An error page served with a 200 — do not cache it as data.
                LOG.warning("%s: response was not a PDF", day)
                time.sleep(REQUEST_DELAY_SECONDS * attempt)
                continue

            cached.write_bytes(response.content)
            time.sleep(REQUEST_DELAY_SECONDS)
            return cached

        LOG.error("%s: giving up after %d attempts", day, MAX_ATTEMPTS)
        return None
    finally:
        if owns_session:
            session.close()
