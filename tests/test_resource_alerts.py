"""Isolated alert integration tests; run inside the Home Assistant image."""

import asyncio
import copy
from pathlib import Path
import tempfile
import time
import unittest

try:
    from homeassistant.core import HomeAssistant
    from homeassistant import bootstrap, config_entries, loader
    from homeassistant.setup import async_setup_component
    from homeassistant.components import persistent_notification
except ImportError:
    raise unittest.SkipTest("Alert integration checks require the Home Assistant runtime")

import yaml

PACKAGE = Path(__file__).resolve().parents[1] / "homeassistant/packages/resource_alerts.yaml"


class ResourceAlertTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.hass = HomeAssistant(self.temp.name)
        loader.async_setup(self.hass)
        self.hass.config_entries = config_entries.ConfigEntries(self.hass, {})
        self.assertTrue(await bootstrap.async_load_base_functionality(self.hass))
        self.package = yaml.safe_load(PACKAGE.read_text())
        self.hass.states.async_set("sensor.raspberry_pi_cpu_temperature", "40")
        self.hass.states.async_set("sensor.raspberry_pi_disk_usage", "20")
        self.hass.states.async_set("sensor.raspberry_pi_disk_free", "50")
        self.hass.states.async_set("sensor.raspberry_pi_memory_usage", "50")
        self.snapshot(cpu=5)

    async def asyncTearDown(self):
        await self.hass.async_stop()
        self.temp.cleanup()

    def snapshot(self, cpu=5, age=0):
        epoch = int(time.time()) - age
        self.hass.states.async_set("sensor.raspberry_pi_resource_snapshot", str(epoch), {
            "epoch": epoch, "valid": True, "cpu": cpu,
            "timestamp": "test snapshot",
            "groups": [{"name": "busy.service", "cpu": cpu}],
        })

    async def setup_alerts(self, fast=True):
        config = copy.deepcopy(self.package)
        if fast:
            for sensor in config["template"][0]["binary_sensor"]:
                for key in ("delay_on", "delay_off"):
                    if key in sensor:
                        sensor[key] = 0
        # Runtime transitions are tested without the startup grace period.
        config["automation"][0]["triggers"] = [config["automation"][0]["triggers"][0]]
        self.assertTrue(await async_setup_component(self.hass, "persistent_notification", {}))
        self.assertTrue(await async_setup_component(self.hass, "template", config))
        self.assertTrue(await async_setup_component(self.hass, "automation", config))
        await self.hass.async_start()
        await self.settle()

    async def settle(self):
        await self.hass.async_block_till_done()
        await asyncio.sleep(0.05)
        await self.hass.async_block_till_done()

    def notifications(self):
        return persistent_notification._async_get_or_create_notifications(self.hass)

    async def set_source(self, entity_id, value):
        self.hass.states.async_set(entity_id, value)
        await self.settle()

    async def test_temperature_hysteresis_and_unavailable_are_not_recovery(self):
        await self.setup_alerts()
        await self.set_source("sensor.raspberry_pi_cpu_temperature", "80")
        self.assertIn("raspberry_pi_temperature", self.notifications())
        await self.set_source("sensor.raspberry_pi_cpu_temperature", "73")
        self.assertIn("raspberry_pi_temperature", self.notifications())
        await self.set_source("sensor.raspberry_pi_cpu_temperature", "unavailable")
        self.assertIn("raspberry_pi_temperature", self.notifications())
        await self.set_source("sensor.raspberry_pi_cpu_temperature", "65")
        self.assertNotIn("raspberry_pi_temperature", self.notifications())

    async def test_storage_severity_uses_one_notification_and_clears(self):
        await self.setup_alerts()
        await self.set_source("sensor.raspberry_pi_disk_usage", "88")
        self.assertIn("nearly full", self.notifications()["raspberry_pi_storage"]["title"])
        await self.set_source("sensor.raspberry_pi_disk_usage", "97")
        self.assertIn("critically full", self.notifications()["raspberry_pi_storage"]["title"])
        self.assertEqual(len(self.notifications()), 1)
        await self.set_source("sensor.raspberry_pi_disk_usage", "88")
        self.assertIn("nearly full", self.notifications()["raspberry_pi_storage"]["title"])
        await self.set_source("sensor.raspberry_pi_disk_usage", "78")
        self.assertNotIn("raspberry_pi_storage", self.notifications())

    async def test_cpu_message_contains_workloads_and_clears_after_recovery(self):
        await self.setup_alerts()
        self.snapshot(cpu=95)
        await self.settle()
        message = self.notifications()["raspberry_pi_cpu"]["message"]
        self.assertIn("busy.service", message)
        self.assertIn("/dashboard-raspberry-pi/resources", message)
        persistent_notification.async_dismiss(self.hass, "raspberry_pi_cpu")
        self.snapshot(cpu=96)
        await self.settle()
        self.assertNotIn("raspberry_pi_cpu", self.notifications())
        self.snapshot(cpu=60)
        await self.settle()
        self.assertNotIn("raspberry_pi_cpu", self.notifications())

    async def test_low_memory_and_stale_timestamp(self):
        await self.setup_alerts()
        await self.set_source("sensor.raspberry_pi_memory_usage", "97")
        self.assertIn("raspberry_pi_memory", self.notifications())
        await self.set_source("sensor.raspberry_pi_memory_usage", "85")
        self.assertNotIn("raspberry_pi_memory", self.notifications())
        self.snapshot(age=240)
        await self.settle()
        self.assertIn("raspberry_pi_monitoring", self.notifications())
        self.snapshot()
        await self.settle()
        self.assertNotIn("raspberry_pi_monitoring", self.notifications())

    async def test_brief_temperature_spike_does_not_notify(self):
        await self.setup_alerts(fast=False)
        await self.set_source("sensor.raspberry_pi_cpu_temperature", "80")
        self.assertNotIn("raspberry_pi_temperature", self.notifications())
        await self.set_source("sensor.raspberry_pi_cpu_temperature", "40")
        self.assertNotEqual(self.hass.states.get("binary_sensor.raspberry_pi_high_temperature").state, "on")
        self.assertNotIn("raspberry_pi_temperature", self.notifications())
