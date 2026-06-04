"""Apply a SQL file to Supabase via the Management API.

Usage: python apply_sql.py <path-to-sql>
Reads the PAT from the SUPABASE_PAT env var (do NOT hardcode).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

REF = "eqbyvasteolqyktbqbem"
PAT = os.environ.get("SUPABASE_PAT", "")


def main() -> int:
    if not PAT:
        print("ERROR: set SUPABASE_PAT env var")
        return 2
    if len(sys.argv) < 2:
        print("usage: python apply_sql.py <file.sql>")
        return 2
    sql = open(sys.argv[1], "r", encoding="utf-8").read()
    body = json.dumps({"query": sql}).encode()
    url = f"https://api.supabase.com/v1/projects/{REF}/database/query"
    headers = {
        "Authorization": f"Bearer {PAT}",
        "Content-Type": "application/json",
        "User-Agent": "mgmt/1.0",
        "Accept": "application/json",
    }
    for attempt in range(5):
        req = urllib.request.Request(url, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                print("HTTP", r.status, r.read().decode()[:300])
                return 0
        except urllib.error.HTTPError as e:
            print("HTTP", e.code, e.read().decode()[:600])
            return 1
        except Exception as e:  # noqa: BLE001 - network retry
            print(f"net attempt {attempt + 1}: {e}")
            time.sleep(4)
    print("failed after retries")
    return 1


if __name__ == "__main__":
    sys.exit(main())
