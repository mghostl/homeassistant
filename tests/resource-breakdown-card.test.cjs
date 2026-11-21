const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const test = require("node:test");

let Card;
const context = {
  HTMLElement: class {
    attachShadow() { this.shadowRoot = { innerHTML: "", querySelectorAll: () => [], querySelector: () => null }; }
  },
  customElements: { define: (_, constructor) => { Card = constructor; } },
  window: { customCards: [], history: { pushState() {} }, dispatchEvent() {} },
  Event: class {},
};
vm.runInNewContext(fs.readFileSync("homeassistant/www/resource-breakdown-card.js", "utf8"), context);

function fixture() {
  const card = new Card();
  card.setConfig({});
  card.hass = { states: {
    "input_boolean.raspberry_pi_resource_history": { state: "off" },
    "sensor.raspberry_pi_resource_snapshot": { state: "1000", attributes: {
      valid: true, epoch: 1000, process_count: 1, interval_seconds: 60,
      groups: [{ name: '<img src=x onerror="alert(1)">', kind: "service", cpu: 1, rss_mib: 2, processes: 1 }],
    } },
  } };
  return card;
}

test("process names cannot inject HTML into the dashboard", () => {
  const html = fixture().shadowRoot.innerHTML;
  assert.ok(html.includes("&lt;img"));
  assert.ok(!html.includes("<img"));
});

test("chart leaves a gap when sampling stopped", () => {
  const card = fixture();
  const graph = card.graph([[1000, 10, 20], [1300, 20, 30], [2500, 40, 50]]);
  assert.equal((graph.match(/<polyline/g) || []).length, 2);
});

test("selecting a historical point sets time before fetching attribution", async () => {
  const card = fixture();
  const calls = [];
  card._hass.callService = async (domain, service, data) => { calls.push([domain, service, data]); };
  await card.selectTime(12345);
  assert.equal(calls[0][2].timestamp, 12345);
  assert.deepEqual(calls.map((call) => call.slice(0, 2)), [
    ["input_datetime", "set_datetime"], ["input_boolean", "turn_on"], ["homeassistant", "update_entity"],
  ]);
});

test("does not display a previous selection as the requested historical sample", () => {
  const card = fixture();
  card._hass.states["input_boolean.raspberry_pi_resource_history"] = { state: "on" };
  card._hass.states["input_datetime.raspberry_pi_resource_time"] = { attributes: { timestamp: 2000 } };
  card._hass.states["sensor.raspberry_pi_resource_history"] = { attributes: { requested_epoch: 1000, valid: true } };
  assert.match(card.breakdown(), /Loading/);
});
