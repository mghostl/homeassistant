#!/usr/bin/env python3
"""Read-only, loopback-only host process sampling for Home Assistant."""

import argparse
from collections import defaultdict
from contextlib import contextmanager
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
from pathlib import Path
import re
import sqlite3
import subprocess
import threading
import time
from urllib.parse import parse_qs, urlsplit

import psutil

DOCKER_ID = re.compile(r"docker[-/]([0-9a-f]{64})(?:\.scope)?")
DAY = 86400


def workload(cgroup, name, containers):
    """Use stable service/container names; never collect command lines or env."""
    cgroup = cgroup.strip()
    match = DOCKER_ID.search(cgroup)
    if match:
        container_id = match[1]
        return "container", containers.get(container_id, container_id[:12])
    units = [part for part in cgroup.split("/") if part.endswith(".service")]
    units = [part for part in units if not part.startswith("user@")]
    if units:
        return "service", units[-1]
    if cgroup.rstrip().endswith("::/") and not name.startswith("systemd"):
        return "kernel", "Kernel threads"
    return "process", name


def process_cpu(previous, current, elapsed, cpu_count):
    if previous is None or elapsed <= 0:
        return 0.0
    return max(0.0, current - previous) / elapsed / cpu_count * 100


class Collector:
    def __init__(self, database):
        self.database = database
        self.previous = {}
        self.previous_at = None
        self.containers = {}
        self.names_checked = 0
        self.initialize()

    @contextmanager
    def connect(self):
        connection = sqlite3.connect(self.database, timeout=10)
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def initialize(self):
        self.database.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("CREATE TABLE IF NOT EXISTS samples "
                               "(ts INTEGER PRIMARY KEY, payload TEXT NOT NULL)")

    def container_names(self):
        if time.monotonic() - self.names_checked < 300:
            return
        self.names_checked = time.monotonic()
        try:
            result = subprocess.run(
                ["docker", "ps", "--no-trunc", "--format", "{{.ID}}\t{{.Names}}"],
                capture_output=True, text=True, timeout=5, check=True,
            )
            self.containers = dict(line.split("\t", 1)
                                   for line in result.stdout.splitlines())
        except (OSError, subprocess.SubprocessError, ValueError):
            logging.warning("Container names unavailable; using container IDs")

    def sample(self):
        self.container_names()
        sampled_at = time.monotonic()
        elapsed = sampled_at - self.previous_at if self.previous_at else 0
        cpu_count = psutil.cpu_count() or 1
        total_memory = psutil.virtual_memory().total
        current = {}
        groups = defaultdict(lambda: {"cpu": 0.0, "rss_mib": 0.0, "processes": 0})
        processes = []
        unreadable = 0
        # psutil 6+ caches Process objects without checking PID reuse. Refresh
        # those objects so each identity includes the current process start time.
        psutil.process_iter.cache_clear()
        for process in psutil.process_iter():
            try:
                with process.oneshot():
                    name = process.name()
                    identity = (process.pid, process.create_time())
                    times = process.cpu_times()
                    cpu_time = times.user + times.system
                    rss = process.memory_info().rss / 1024**2
                cgroup = Path(f"/proc/{process.pid}/cgroup").read_text()
                kind, label = workload(cgroup, name, self.containers)
                cpu = process_cpu(self.previous.get(identity), cpu_time, elapsed, cpu_count)
                current[identity] = cpu_time
                group = groups[(kind, label)]
                group["cpu"] += cpu
                group["rss_mib"] += rss
                group["processes"] += 1
                processes.append({"pid": process.pid, "name": name, "workload": label,
                                  "kind": kind, "cpu": round(cpu, 2),
                                  "rss_mib": round(rss, 1)})
            except (psutil.NoSuchProcess, psutil.ZombieProcess, FileNotFoundError, ProcessLookupError):
                continue
            except (psutil.AccessDenied, OSError):
                unreadable += 1

        self.previous = current
        self.previous_at = sampled_at
        epoch = int(time.time())
        workloads = [dict(kind=kind, name=name, cpu=round(values["cpu"], 2),
                          rss_mib=round(values["rss_mib"], 1), processes=values["processes"])
                     for (kind, name), values in groups.items()]
        container_cpu = sum(row["cpu"] for row in workloads if row["kind"] == "container")
        container_rss = sum(row["rss_mib"] for row in workloads if row["kind"] == "container")
        payload = {
            "valid": elapsed > 0,
            "epoch": epoch,
            "timestamp": datetime.fromtimestamp(epoch, timezone.utc).isoformat(),
            "interval_seconds": round(elapsed, 1),
            "cpu": psutil.cpu_percent(),
            "memory": psutil.virtual_memory().percent,
            "container_cpu": round(container_cpu, 2),
            "host_process_cpu": round(sum(row["cpu"] for row in workloads
                                          if row["kind"] != "container"), 2),
            "container_rss_mib": round(container_rss, 1),
            "host_process_rss_mib": round(sum(row["rss_mib"] for row in workloads
                                              if row["kind"] != "container"), 1),
            "total_memory_mib": round(total_memory / 1024**2, 1),
            "groups": sorted(workloads, key=lambda row: row["cpu"], reverse=True),
            "top_cpu": sorted(processes, key=lambda row: row["cpu"], reverse=True)[:20],
            "top_memory": sorted(processes, key=lambda row: row["rss_mib"], reverse=True)[:20],
            "process_count": len(processes),
            "unreadable_processes": unreadable,
        }
        if elapsed:
            with self.connect() as connection:
                connection.execute("INSERT OR REPLACE INTO samples VALUES (?, ?)",
                                   (epoch, json.dumps(payload, separators=(",", ":"))))
                connection.execute("DELETE FROM samples WHERE ts < ?", (epoch - 7 * DAY,))
        return payload

    def snapshot(self, at=None):
        with self.connect() as connection:
            if at is None:
                row = connection.execute("SELECT payload FROM samples ORDER BY ts DESC LIMIT 1").fetchone()
            else:
                row = connection.execute(
                    "SELECT payload FROM samples WHERE ts BETWEEN ? AND ? "
                    "ORDER BY ABS(ts - ?) LIMIT 1", (at - 90, at + 90, at),
                ).fetchone()
        return json.loads(row[0]) if row else {"valid": False, "error": "No sample within 90 seconds of this time"}

    def timeline(self):
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT MAX(ts), payload FROM samples WHERE ts >= ? GROUP BY CAST(ts / 300 AS INTEGER) "
                "ORDER BY ts", (int(time.time()) - DAY,),
            ).fetchall()
            bounds = connection.execute("SELECT MIN(ts), MAX(ts) FROM samples").fetchone()
        # SQLite's MAX(ts) selects the payload from the same row in each bucket.
        points = [[ts, json.loads(payload)["cpu"], json.loads(payload)["memory"]]
                  for ts, payload in rows]
        return {"valid": bool(points), "epoch": bounds[1] or 0,
                "earliest": bounds[0], "points": points}


def make_handler(collector):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            url = urlsplit(self.path)
            try:
                if url.path == "/latest":
                    result = collector.snapshot()
                elif url.path == "/history":
                    at = float(parse_qs(url.query)["at"][0])
                    if not 0 <= at <= 2**40:
                        raise ValueError("Invalid timestamp")
                    result = collector.snapshot(at)
                    result["requested_epoch"] = at
                elif url.path == "/timeline":
                    result = collector.timeline()
                else:
                    self.send_error(404)
                    return
            except (ValueError, KeyError):
                self.send_error(400, "Expected a numeric at timestamp")
                return
            body = json.dumps(result, separators=(",", ":")).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    return Handler


def collect_forever(collector):
    psutil.cpu_percent()
    try:
        collector.sample()
    except Exception:
        logging.exception("Initial process scan failed")
    time.sleep(1)
    while True:
        started = time.monotonic()
        try:
            collector.sample()
        except Exception:
            logging.exception("Resource sampling failed")
        time.sleep(max(1, 60 - (time.monotonic() - started)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=Path.home() / ".local/share/ha-resource-monitor/history.sqlite3")
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    collector = Collector(args.database)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(collector))
    threading.Thread(target=collect_forever, args=(collector,), daemon=True).start()
    server.serve_forever()


if __name__ == "__main__":
    main()
