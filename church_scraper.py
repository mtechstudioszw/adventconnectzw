#!/usr/bin/env python3
"""
Adventist Yearbook church scraper — Playwright version
========================================================

Same crawl logic as the requests-based script, but fetches pages with a
real headless Chromium browser via Playwright instead of the `requests`
library. This is needed because adventistyearbook.org returns HTTP 403
to plain HTTP clients regardless of headers — that's a TLS/JS
fingerprint check (Cloudflare-style), not a header check, and only an
actual browser engine gets past it reliably.

SETUP
-----
    pip install playwright beautifulsoup4
    playwright install chromium

USAGE
-----
    python scrape_adventist_yearbook_playwright.py --test   # ~25 entities
    python scrape_adventist_yearbook_playwright.py           # full crawl

Resumable exactly like before: stop it anytime (Ctrl+C), rerun the same
command, it picks up from visited.json/queue.json/failed.json.

BEFORE A FULL RUN: open one real church's page in your own browser and
compare it to what parse_entity_page() below expects (see comments in
that function) — I couldn't inspect the live page myself, so the field
labels may need a small tweak once you see real data.
"""

import argparse
import csv
import json
import os
import time
from collections import deque

from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

BASE = "https://www.adventistyearbook.org"
GC_ENTITY_ID = "10010"  # General Conference — root of the hierarchy

OUTPUT_CSV = "sda_churches.csv"
VISITED_FILE = "visited.json"
QUEUE_FILE = "queue.json"
FAILED_FILE = "failed.json"

REQUEST_DELAY = 2.0     # seconds between page loads — be polite
MAX_RETRIES = 3
MAX_FAILURES_PER_ENTITY = 3
PAGE_TIMEOUT_MS = 30000

FIELDNAMES = [
    "entity_id", "name", "entity_type", "address", "city", "country",
    "phone", "email", "parent_field", "union", "division", "url",
]


def list_url(parent_id):
    return f"{BASE}/list?type=administered&AFParentID={parent_id}"


def entity_url(entity_id):
    return f"{BASE}/entity?EntityID={entity_id}"


def fetch(page, url):
    """Load a URL with the shared browser page, retrying on failure."""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = page.goto(url, timeout=PAGE_TIMEOUT_MS, wait_until="domcontentloaded")
            if resp and resp.status == 200:
                # small settle time in case any client-side content loads in
                page.wait_for_timeout(500)
                return page.content()
            status = resp.status if resp else "no response"
            print(f"  [warn] {url} -> HTTP {status} (attempt {attempt})")
        except Exception as e:
            print(f"  [warn] {url} -> {e} (attempt {attempt})")
        time.sleep(REQUEST_DELAY * attempt)
    print(f"  [error] giving up on {url}")
    return None


def parse_child_links(html):
    soup = BeautifulSoup(html, "html.parser")
    children = []
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if "EntityID=" in href:
            entity_id = href.split("EntityID=")[-1].split("&")[0]
            name = a.get_text(strip=True)
            if entity_id and name:
                children.append({"id": entity_id, "name": name})
    return children


def parse_entity_page(html, entity_id, url):
    """
    Parse a single entity's detail page into a row dict.
    ADJUST THIS once you've compared to a real church page in your
    browser — grab() looks for lines starting with a label like
    "Address:", "City:", etc. If the real page uses a table layout or
    different labels, tweak the `grab()` calls below to match.
    """
    soup = BeautifulSoup(html, "html.parser")
    text_blocks = [t.get_text(" ", strip=True) for t in soup.find_all(["p", "li", "td", "div"])]

    title_el = soup.find("h1") or soup.find("h2")
    name = title_el.get_text(strip=True) if title_el else ""

    def grab(label):
        for line in text_blocks:
            if line.lower().startswith(label.lower()):
                return line.split(":", 1)[-1].strip()
        return ""

    return {
        "entity_id": entity_id,
        "name": name,
        "entity_type": "Church",
        "address": grab("Address"),
        "city": grab("City"),
        "country": grab("Country"),
        "phone": grab("Phone") or grab("Telephone"),
        "email": grab("Email"),
        "parent_field": grab("Local Field") or grab("Field"),
        "union": grab("Union"),
        "division": grab("Division"),
        "url": url,
    }


def load_json(path, default):
    if os.path.exists(path):
        with open(path, "r") as f:
            return json.load(f)
    return default


def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f)


def ensure_csv_header():
    if not os.path.exists(OUTPUT_CSV):
        with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
            csv.DictWriter(f, fieldnames=FIELDNAMES).writeheader()


def append_row(row):
    with open(OUTPUT_CSV, "a", newline="", encoding="utf-8") as f:
        csv.DictWriter(f, fieldnames=FIELDNAMES).writerow(row)


def crawl(max_entities=None):
    ensure_csv_header()

    visited = set(load_json(VISITED_FILE, []))
    queue = deque(load_json(QUEUE_FILE, [GC_ENTITY_ID]))
    failures = load_json(FAILED_FILE, {})

    churches_found = 0
    processed = 0
    consecutive_failures = 0

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            user_agent=("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"),
            viewport={"width": 1280, "height": 800},
        )
        page = context.new_page()

        while queue:
            if max_entities and processed >= max_entities:
                print(f"Reached test limit of {max_entities} entities — stopping.")
                break

            entity_id = queue.popleft()
            if entity_id in visited:
                continue

            url = entity_url(entity_id)
            print(f"[{len(visited)} done, {len(queue)} queued] fetching {url}")
            html = fetch(page, url)
            time.sleep(REQUEST_DELAY)
            processed += 1

            if html is None:
                failures[entity_id] = failures.get(entity_id, 0) + 1
                consecutive_failures += 1
                if failures[entity_id] < MAX_FAILURES_PER_ENTITY:
                    queue.append(entity_id)
                else:
                    visited.add(entity_id)
                    print(f"  [give up] {entity_id} failed {MAX_FAILURES_PER_ENTITY}x")

                save_json(VISITED_FILE, list(visited))
                save_json(QUEUE_FILE, list(queue))
                save_json(FAILED_FILE, failures)

                if consecutive_failures >= 5:
                    print("\n[stopping] 5 fetches in a row failed. Progress is "
                          "saved — fix whatever's blocking access before "
                          "re-running.")
                    break
                continue

            consecutive_failures = 0
            visited.add(entity_id)
            failures.pop(entity_id, None)

            children = parse_child_links(html)
            child_ids = [c["id"] for c in children if c["id"] not in visited]

            looks_like_church = any(
                kw in html for kw in ["Local Church", "Church Directory Info"]
            ) and not child_ids

            if looks_like_church:
                row = parse_entity_page(html, entity_id, url)
                append_row(row)
                churches_found += 1
                print(f"  -> saved church: {row['name']}")
            else:
                list_html = fetch(page, list_url(entity_id))
                time.sleep(REQUEST_DELAY)
                if list_html:
                    children += parse_child_links(list_html)

                for c in children:
                    if c["id"] not in visited and c["id"] not in queue:
                        queue.append(c["id"])

            save_json(VISITED_FILE, list(visited))
            save_json(QUEUE_FILE, list(queue))

        browser.close()

    print(f"\nDone. Entities processed this run: {processed}. "
          f"Churches saved this run: {churches_found}.")
    print(f"CSV: {os.path.abspath(OUTPUT_CSV)}")


def main():
    parser = argparse.ArgumentParser(description="Scrape SDA Yearbook churches (Playwright)")
    parser.add_argument("--test", action="store_true",
                         help="Only process ~25 entities, to sanity-check parsing")
    args = parser.parse_args()

    if args.test:
        for f in (VISITED_FILE, QUEUE_FILE, FAILED_FILE, OUTPUT_CSV):
            if os.path.exists(f):
                os.remove(f)
        crawl(max_entities=25)
    else:
        crawl()


if __name__ == "__main__":
    main()