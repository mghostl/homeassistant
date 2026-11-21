// Local Lovelace card. All data comes through authenticated Home Assistant
// entities; the host collector has no browser-facing network port.
const SNAPSHOT = "sensor.raspberry_pi_resource_snapshot";
const HISTORY = "sensor.raspberry_pi_resource_history";
const TIMELINE = "sensor.raspberry_pi_resource_timeline";
const TIME = "input_datetime.raspberry_pi_resource_time";
const HISTORICAL = "input_boolean.raspberry_pi_resource_history";
const WATCHED = [SNAPSHOT, HISTORY, TIMELINE, TIME, HISTORICAL];
const escapeHTML = (value) => String(value ?? "").replace(/[&<>"']/g,
  (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
const number = (value) => Number(value || 0).toFixed(1);

class ResourceBreakdownCard extends HTMLElement {
  setConfig(config) {
    this.config = config;
    this.metric = config.metric || "cpu";
    this.sort = "cpu";
    this.attachRoot();
  }

  attachRoot() {
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  set hass(hass) {
    const changed = !this._hass || WATCHED.some((id) => this._hass.states[id] !== hass.states[id]);
    this._hass = hass;
    if (changed) this.render();
  }

  getCardSize() { return this.config?.compact ? 4 : 12; }

  async selectTime(epoch) {
    if (!Number.isFinite(epoch)) return;
    this.error = null;
    try {
      await this._hass.callService("input_datetime", "set_datetime", { entity_id: TIME, timestamp: epoch });
      await this._hass.callService("input_boolean", "turn_on", { entity_id: HISTORICAL });
      await this._hass.callService("homeassistant", "update_entity", { entity_id: HISTORY });
      if (this.config.compact) this.navigate();
    } catch (error) {
      this.error = error.message || String(error);
      this.render();
    }
  }

  navigate() {
    window.history.pushState(null, "", "/dashboard-raspberry-pi/resources");
    window.dispatchEvent(new Event("location-changed"));
  }

  graph(points) {
    if (!points.length) return '<p class="muted">Waiting for resource history…</p>';
    const column = this.metric === "cpu" ? 1 : 2;
    const first = points[0][0];
    const span = Math.max(300, points.at(-1)[0] - first);
    const coordinates = points.map((point) =>
      `${40 + (point[0] - first) / span * 700},${150 - Math.min(100, Math.max(0, point[column])) * 1.3}`);
    const segments = [];
    points.forEach((point, index) => {
      if (!index || point[0] - points[index - 1][0] > 600) segments.push([]);
      segments.at(-1).push(coordinates[index]);
    });
    const line = segments.map((segment) => `<polyline points="${segment.join(" ")}"/>`).join("");
    const selected = this._hass.states[TIME]?.attributes.timestamp;
    const selectedX = selected && 40 + (selected - first) / span * 700;
    return `<svg viewBox="0 0 760 190" role="group" aria-label="${this.metric === "cpu" ? "CPU" : "Memory"} percentage over 24 hours. Select a point for its process breakdown.">
      <text x="0" y="24">100%</text><text x="10" y="154">0%</text>
      <path class="axis" d="M40 20 H740 M40 85 H740 M40 150 H740"/>
      <g class="line">${line}</g>
      ${points.map((point, i) => `<circle class="point" tabindex="0" role="button" aria-label="${escapeHTML(new Date(point[0] * 1000).toLocaleString())}: ${number(point[column])}%" data-time="${point[0]}" cx="${coordinates[i].split(",")[0]}" cy="${coordinates[i].split(",")[1]}" r="4"><title>${escapeHTML(new Date(point[0] * 1000).toLocaleString())}: ${number(point[column])}%</title></circle>`).join("")}
      ${this._hass.states[HISTORICAL]?.state === "on" && selectedX >= 40 && selectedX <= 740 ? `<path class="selection" d="M${selectedX} 20 V150"/>` : ""}
      <text x="40" y="180">${escapeHTML(new Date(first * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }))}</text>
      <text x="740" y="180" text-anchor="end">${escapeHTML(new Date(points.at(-1)[0] * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }))}</text>
    </svg><p class="muted">Last 24 hours · select a dot to inspect that sample</p>`;
  }

  table(headers, rows) {
    return `<div class="scroll"><table><thead><tr>${headers.map((value) => `<th>${escapeHTML(value)}</th>`).join("")}</tr></thead>
      <tbody>${rows.map((row) => `<tr>${row.map((value) => `<td>${escapeHTML(value)}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
  }

  breakdown() {
    const historical = this._hass.states[HISTORICAL]?.state === "on";
    const entity = this._hass.states[historical ? HISTORY : SNAPSHOT];
    const data = entity?.attributes;
    if (historical && data?.requested_epoch !== this._hass.states[TIME]?.attributes.timestamp) {
      return '<p role="status">Loading the selected snapshot…</p>';
    }
    if (!data?.valid || ["unavailable", "unknown"].includes(entity?.state)) {
      return `<p role="status">${escapeHTML(data?.error || "Waiting for the host collector. The first sample takes a few seconds.")}</p>`;
    }
    const stale = !historical && Date.now() / 1000 - data.epoch > 180;
    const groups = [...(data.groups || [])].sort((a, b) => b[this.sort] - a[this.sort]);
    const processes = this.sort === "cpu" ? data.top_cpu || [] : data.top_memory || [];
    return `<h3>${historical ? "Recorded breakdown" : "Live breakdown"}</h3>
      <p>${escapeHTML(new Date(data.epoch * 1000).toLocaleString())} · ${data.process_count} processes · CPU averaged over ${number(data.interval_seconds)} seconds</p>
      ${stale ? '<p role="alert">Collector data is stale. Check the host monitoring service.</p>' : ""}
      ${data.unreadable_processes ? `<p role="alert">${data.unreadable_processes} processes could not be read.</p>` : ""}
      <p class="muted">CPU: share of the Pi’s total CPU capacity. Memory: resident memory (RSS); shared pages may be counted in multiple processes. RSS totals differ from overall RAM usage, which includes kernel memory and caches.</p>
      <div class="buttons"><button data-sort="cpu" aria-pressed="${this.sort === "cpu"}">Sort by CPU</button><button data-sort="rss_mib" aria-pressed="${this.sort === "rss_mib"}">Sort by memory</button></div>
      <h3>Services, containers, and other processes</h3>
      ${this.table(["Workload", "Type", "CPU %", "RSS MiB", "Processes"], groups.map((row) => [row.name, row.kind, number(row.cpu), number(row.rss_mib), row.processes]))}
      <h3>Top 20 individual processes by ${this.sort === "cpu" ? "CPU" : "memory"}</h3>
      ${this.table(["Process", "PID", "Workload", "CPU %", "RSS MiB"], processes.map((row) => [row.name, row.pid, row.workload, number(row.cpu), number(row.rss_mib)]))}`;
  }

  render() {
    if (!this.config || !this._hass) return;
    this.attachRoot();
    const points = this._hass.states[TIMELINE]?.attributes.points || [];
    const earliest = this._hass.states[TIMELINE]?.attributes.earliest;
    const stale = points.length && Date.now() / 1000 - Number(this._hass.states[TIMELINE]?.state || 0) > 180;
    this.shadowRoot.innerHTML = `<style>
      :host { display:block; } ha-card { padding:16px; } h2 { font-size:20px; margin:0 0 12px; } h3 { font-size:16px; margin:20px 0 8px; }
      p { line-height:1.5; } .muted { color:var(--secondary-text-color); font-size:13px; } [role=alert] { color:var(--error-color); }
      button,input { font:inherit; padding:8px 12px; color:var(--primary-text-color); background:var(--card-background-color); border:1px solid var(--divider-color); border-radius:8px; }
      button { cursor:pointer; } button[aria-pressed=true] { color:var(--primary-color); border-color:var(--primary-color); }
      .buttons,form { display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin:8px 0; } svg { width:100%; margin-top:12px; }
      svg text { fill:var(--secondary-text-color); font-size:12px; } .axis { fill:none; stroke:var(--divider-color); }
      .line { fill:none; stroke:var(--primary-color); stroke-width:2; } .point { fill:var(--primary-color); cursor:pointer; }
      .point:hover { r:7; } .selection { stroke:var(--error-color); stroke-width:2; pointer-events:none; }
      .scroll { overflow-x:auto; max-height:500px; } table { border-collapse:collapse; width:100%; font-size:13px; }
      th,td { text-align:left; padding:8px; border-bottom:1px solid var(--divider-color); } th { position:sticky; top:0; background:var(--card-background-color); }
      th:nth-last-child(-n+3),td:nth-last-child(-n+3) { text-align:right; white-space:nowrap; }
    </style><ha-card><h2>${escapeHTML(this.config.title || "Resource usage")}</h2>
      <div class="buttons"><button data-metric="cpu" aria-pressed="${this.metric === "cpu"}">CPU</button><button data-metric="memory" aria-pressed="${this.metric === "memory"}">Memory</button>
      ${this.config.compact ? '<button id="details">Open process breakdown</button>' : '<button id="live">Show live</button>'}</div>
      ${this.graph(points)}
      ${stale ? '<p role="alert">Resource history is stale. Check the host monitoring service.</p>' : ""}
      ${this.config.compact ? "" : `<form><label for="time">Investigate a time</label><input id="time" type="datetime-local" required step="60"><button type="submit">Load snapshot</button></form>
        <p class="muted">One-minute snapshots kept for seven days. Chart shows five-minute samples. ${earliest ? `Available since ${escapeHTML(new Date(earliest * 1000).toLocaleString())}.` : ""}</p>${this.breakdown()}`}
      ${this.error ? `<p role="alert">${escapeHTML(this.error)}</p>` : ""}
    </ha-card>`;
    this.shadowRoot.querySelectorAll("[data-metric]").forEach((button) => button.addEventListener("click", () => { this.metric = button.dataset.metric; this.render(); }));
    this.shadowRoot.querySelectorAll("[data-sort]").forEach((button) => button.addEventListener("click", () => { this.sort = button.dataset.sort; this.render(); }));
    this.shadowRoot.querySelectorAll("[data-time]").forEach((point) => point.addEventListener("click", () => this.selectTime(Number(point.dataset.time))));
    this.shadowRoot.querySelectorAll("[data-time]").forEach((point) => point.addEventListener("keydown", (event) => {
      if (["Enter", " "].includes(event.key)) { event.preventDefault(); this.selectTime(Number(point.dataset.time)); }
    }));
    const timeInput = this.shadowRoot.querySelector("#time");
    if (timeInput) {
      timeInput.value = this.inputTime || "";
      timeInput.addEventListener("input", () => { this.inputTime = timeInput.value; });
    }
    this.shadowRoot.querySelector("#details")?.addEventListener("click", () => this.navigate());
    this.shadowRoot.querySelector("#live")?.addEventListener("click", async () => {
      try { await this._hass.callService("input_boolean", "turn_off", { entity_id: HISTORICAL }); }
      catch (error) { this.error = error.message; this.render(); }
    });
    this.shadowRoot.querySelector("form")?.addEventListener("submit", (event) => {
      event.preventDefault();
      this.selectTime(new Date(this.shadowRoot.querySelector("#time").value).getTime() / 1000);
    });
  }
}

customElements.define("resource-breakdown-card", ResourceBreakdownCard);
window.customCards = window.customCards || [];
window.customCards.push({ type: "resource-breakdown-card", name: "Host resource breakdown", description: "Clickable resource history with service and process attribution." });
