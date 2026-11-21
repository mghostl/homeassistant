"""Run on the Pi: python3 -m unittest discover -s tests -v."""

import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "monitor", Path(__file__).resolve().parents[1] / "scripts/monitor-host-resources.py"
)
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


class ResourceHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.collector = monitor.Collector(Path(self.temp.name) / "history.sqlite3")

    def insert(self, epoch, cpu=10, memory=20):
        payload = dict(valid=True, epoch=epoch, cpu=cpu, memory=memory)
        with self.collector.connect() as connection:
            connection.execute("INSERT INTO samples VALUES (?, ?)", (epoch, json.dumps(payload)))

    def test_snapshots_do_not_substitute_unrelated_old_data(self):
        self.insert(1000)
        self.insert(1060, cpu=30)
        self.assertEqual(self.collector.snapshot(1040)["epoch"], 1060)
        self.assertEqual(self.collector.snapshot()["epoch"], 1060)
        self.assertFalse(self.collector.snapshot(1200)["valid"])

    def test_timeline_uses_values_and_timestamp_from_same_sample(self):
        base = int(time.time()) // 300 * 300
        self.insert(base + 1, cpu=91, memory=30)
        self.insert(base + 59, cpu=12, memory=44)
        self.assertEqual(self.collector.timeline()["points"], [[base + 59, 12, 44]])

    def test_collection_enforces_seven_day_retention(self):
        self.insert(int(time.time()) - 8 * monitor.DAY)
        self.collector.previous_at = time.monotonic() - 60
        with patch.object(self.collector, "container_names"), patch.object(monitor.psutil, "process_iter", return_value=[]):
            self.collector.sample()
        with self.collector.connect() as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM samples").fetchone()[0], 1)
        self.assertGreater(self.collector.snapshot()["epoch"], time.time() - 5)

    def test_container_names_and_nested_services_are_stable(self):
        container_id = "a" * 64
        self.assertEqual(monitor.workload(f"0::/system.slice/docker-{container_id}.scope", "python", {container_id: "app"}), ("container", "app"))
        self.assertEqual(monitor.workload("0::/user.slice/user@1000.service/app.slice/worker.service\n", "python", {}), ("service", "worker.service"))
        self.assertEqual(monitor.workload("0::/user.slice/session-1.scope", "java", {}), ("process", "java"))

    def test_cpu_is_normalized_to_host_capacity_and_never_negative(self):
        self.assertEqual(monitor.process_cpu(100, 160, 60, 4), 25)
        self.assertEqual(monitor.process_cpu(None, 160, 60, 4), 0)
        self.assertEqual(monitor.process_cpu(160, 100, 60, 4), 0)

    def test_reused_pid_does_not_inherit_old_process_cpu(self):
        from contextlib import nullcontext
        from types import SimpleNamespace
        from unittest.mock import Mock
        process = Mock(pid=42)
        process.oneshot.return_value = nullcontext()
        process.name.return_value = "worker"
        process.create_time.return_value = 2000
        process.cpu_times.return_value = SimpleNamespace(user=9000, system=0)
        process.memory_info.return_value = SimpleNamespace(rss=1024**2)
        self.collector.previous = {(42, 1000): 10}
        self.collector.previous_at = time.monotonic() - 60
        with patch.object(self.collector, "container_names"), patch.object(monitor.psutil, "process_iter", return_value=[process]), patch.object(Path, "read_text", return_value="0::/system.slice/worker.service"):
            sample = self.collector.sample()
        self.assertEqual(sample["top_cpu"][0]["cpu"], 0)
        self.assertEqual(sample["groups"][0]["name"], "worker.service")


if __name__ == "__main__":
    unittest.main()
