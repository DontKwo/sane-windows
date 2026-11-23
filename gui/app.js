(function () {
  "use strict";

  const state = {
    sections: [],
    cleanupItems: [],
    toolingLoaded: false,
    pendingAction: null,
    filter: ""
  };

  function setStatus(text) {
    const banner = document.getElementById("statusBanner");
    if (banner) banner.textContent = text;
  }

  function appendLog(text) {
    const box = document.getElementById("outputConsole");
    if (box) box.textContent = text || "Completed.";
  }

  window.addEventListener("error", function (event) {
    setStatus("An unexpected UI error occurred. Review Execution Log for details.");
    appendLog("UI error: " + (event.message || "Unknown error"));
  });

  window.addEventListener("unhandledrejection", function (event) {
    setStatus("Operation did not complete. Check Execution Log for friendly details.");
    appendLog("Async error: " + (event.reason ? String(event.reason) : "Unknown rejection"));
  });

  async function apiGet(url) {
    const resp = await fetch(url, { cache: "no-store" });
    if (!resp.ok) throw new Error("Request failed with status " + resp.status);
    return resp.json();
  }

  async function apiPost(url, payload) {
    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload || {})
    });
    if (!resp.ok) throw new Error("Request failed with status " + resp.status);
    return resp.json();
  }

  function formatLabel(key) {
    return key.replace(/_/g, " ").replace(/\b\w/g, function (ch) { return ch.toUpperCase(); });
  }

  function formatBytes(bytes) {
    const num = Number(bytes || 0);
    if (num >= 1073741824) return (num / 1073741824).toFixed(2) + " GB";
    if (num >= 1048576) return (num / 1048576).toFixed(2) + " MB";
    if (num >= 1024) return (num / 1024).toFixed(2) + " KB";
    return num + " B";
  }

  function renderTweaks() {
    const host = document.getElementById("tweaksGrid");
    if (!host) return;
    host.textContent = "";
    const term = state.filter.trim().toLowerCase();

    state.sections.forEach(function (sec) {
      const visibleItems = (sec.items || []).filter(function (item) {
        return !term || item.key.toLowerCase().includes(term) || sec.name.toLowerCase().includes(term);
      });
      if (visibleItems.length === 0) return;

      const card = document.createElement("div");
      card.className = "card";
      const heading = document.createElement("h2");
      heading.textContent = formatLabel(sec.name);
      card.appendChild(heading);

      visibleItems.forEach(function (item) {
        const row = document.createElement("div");
        row.className = "setting-row";
        const label = document.createElement("label");

        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.checked = Boolean(item.enabled);
        checkbox.addEventListener("change", function () {
          item.enabled = checkbox.checked;
        });

        const textSpan = document.createElement("span");
        textSpan.textContent = formatLabel(item.key);

        label.appendChild(checkbox);
        label.appendChild(textSpan);
        row.appendChild(label);
        card.appendChild(row);
      });

      host.appendChild(card);
    });
  }

  function renderTweaksDiffs(diffs) {
    const card = document.getElementById("tweaksDiffCard");
    const host = document.getElementById("tweaksDiffHost");
    if (!card || !host) return;
    host.textContent = "";
    card.hidden = false;

    if (!diffs || diffs.length === 0) {
      const p = document.createElement("p");
      p.className = "muted";
      p.textContent = "All inspected settings match config.yaml with 0 pending changes.";
      host.appendChild(p);
      return;
    }

    const table = document.createElement("table");
    table.innerHTML = "<thead><tr><th>Status</th><th>Section</th><th>Setting</th><th>Change / Detail</th></tr></thead><tbody></tbody>";
    const tbody = table.querySelector("tbody");
    diffs.slice(0, 60).forEach(function (row) {
      const tr = document.createElement("tr");
      const statusTd = document.createElement("td");
      const badge = document.createElement("span");
      const stLower = String(row.status || "Info").toLowerCase();
      badge.className = "badge " + (stLower === "pending" ? "badge-warn" : (stLower === "skipped" ? "badge-muted" : "badge-ok"));
      badge.textContent = row.status || "Info";
      statusTd.appendChild(badge);

      const secTd = document.createElement("td");
      secTd.textContent = formatLabel(String(row.section || "system"));
      const tgtTd = document.createElement("td");
      tgtTd.textContent = formatLabel(String(row.target || ""));
      const actTd = document.createElement("td");
      actTd.textContent = String(row.action || "");

      tr.appendChild(statusTd);
      tr.appendChild(secTd);
      tr.appendChild(tgtTd);
      tr.appendChild(actTd);
      tbody.appendChild(tr);
    });
    host.appendChild(table);
  }

  function renderSnapshots(snapshots) {
    const select = document.getElementById("tweaks.snapshot_select");
    if (!select) return;
    select.textContent = "";
    if (!snapshots || snapshots.length === 0) {
      const opt = document.createElement("option");
      opt.value = "";
      opt.textContent = "No snapshots saved yet";
      select.appendChild(opt);
      return;
    }
    snapshots.forEach(function (name) {
      const opt = document.createElement("option");
      opt.value = name;
      opt.textContent = name;
      select.appendChild(opt);
    });
  }

  function updateCleanupSummary() {
    const summaryEl = document.getElementById("cleanupSelectionSummary");
    const selectAllEl = document.getElementById("cleanup.select_all");
    if (!summaryEl) return;
    const selected = state.cleanupItems.filter(function (it) { return it.selected; });
    const totalBytes = selected.reduce(function (acc, it) { return acc + Number(it.sizeBytes || 0); }, 0);
    summaryEl.textContent = selected.length + " of " + state.cleanupItems.length + " selected (" + formatBytes(totalBytes) + ")";
    if (selectAllEl && state.cleanupItems.length > 0) {
      selectAllEl.checked = selected.length === state.cleanupItems.length;
    }
  }

  function renderCleanupTable(items) {
    state.cleanupItems = (items || []).map(function (item) {
      return Object.assign({ selected: true }, item);
    });
    const host = document.getElementById("cleanupTableHost");
    if (!host) return;
    host.textContent = "";
    if (state.cleanupItems.length === 0) {
      const p = document.createElement("p");
      p.className = "muted";
      p.textContent = "No cleanable caches reported for the selected age filter.";
      host.appendChild(p);
      updateCleanupSummary();
      return;
    }
    const table = document.createElement("table");
    table.innerHTML = "<thead><tr><th>Clean</th><th>Target</th><th>Category</th><th>Reclaimable</th></tr></thead><tbody></tbody>";
    const tbody = table.querySelector("tbody");
    state.cleanupItems.forEach(function (rowItem) {
      const tr = document.createElement("tr");
      const checkTd = document.createElement("td");
      const box = document.createElement("input");
      box.type = "checkbox";
      box.className = "cleanup-row-check";
      box.checked = Boolean(rowItem.selected);
      box.setAttribute("aria-label", "Select " + (rowItem.name || rowItem.id));
      box.addEventListener("change", function () {
        rowItem.selected = box.checked;
        updateCleanupSummary();
      });
      checkTd.appendChild(box);

      const nameTd = document.createElement("td");
      nameTd.textContent = rowItem.name || "Target";
      const catTd = document.createElement("td");
      catTd.textContent = rowItem.category || "Cache";
      const sizeTd = document.createElement("td");
      sizeTd.textContent = rowItem.sizeLabel || "0 B";

      tr.appendChild(checkTd);
      tr.appendChild(nameTd);
      tr.appendChild(catTd);
      tr.appendChild(sizeTd);
      tbody.appendChild(tr);
    });
    host.appendChild(table);
    updateCleanupSummary();
  }

  async function runSingleToolAction(mode, toolName) {
    setStatus((mode === "install" ? "Installing " : "Updating ") + toolName + "...");
    const res = await apiPost("/api/tooling/action", { mode: mode, tool: toolName });
    renderToolingTable(res.tools || []);
    setStatus(res.ok ? (toolName + " action finished.") : (toolName + " action returned warnings."));
    appendLog(res.output || "");
  }

  function renderToolingTable(rows) {
    const host = document.getElementById("toolingTableHost");
    if (!host) return;
    host.textContent = "";
    if (!rows || rows.length === 0) {
      const p = document.createElement("p");
      p.className = "muted";
      p.textContent = "Click Refresh Diagnostics to inspect installed developer CLIs.";
      host.appendChild(p);
      return;
    }
    const table = document.createElement("table");
    table.innerHTML = "<thead><tr><th>Tool</th><th>Status</th><th>Version</th><th>Action</th></tr></thead><tbody></tbody>";
    const tbody = table.querySelector("tbody");
    rows.forEach(function (item) {
      const tr = document.createElement("tr");
      const nameTd = document.createElement("td");
      nameTd.textContent = item.tool || "";
      const stTd = document.createElement("td");
      const badge = document.createElement("span");
      const isInstalled = String(item.status || "").toLowerCase() === "installed";
      badge.className = "badge " + (isInstalled ? "badge-ok" : "badge-warn");
      badge.textContent = item.status || "Unknown";
      stTd.appendChild(badge);

      const verTd = document.createElement("td");
      verTd.textContent = item.version || "";

      const actTd = document.createElement("td");
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = isInstalled ? "btn-secondary" : "btn-primary";
      const mode = isInstalled ? "update" : "install";
      btn.textContent = isInstalled ? "Update" : "Install";
      btn.addEventListener("click", function () {
        openConfirm((isInstalled ? "Update " : "Install ") + item.tool + " via system package manager?", function () {
          return runSingleToolAction(mode, item.tool);
        });
      });
      actTd.appendChild(btn);

      tr.appendChild(nameTd);
      tr.appendChild(stTd);
      tr.appendChild(verTd);
      tr.appendChild(actTd);
      tbody.appendChild(tr);
    });
    host.appendChild(table);
  }

  async function refreshToolingDiagnostics() {
    setStatus("Inspecting installed developer CLIs...");
    const res = await apiPost("/api/tooling/status", {});
    state.toolingLoaded = true;
    renderToolingTable(res.tools || []);
    setStatus("Tooling check complete.");
    appendLog(res.output || "");
  }

  function switchTab(activeId) {
    const map = {
      "tabs.tweaks": "panelTweaks",
      "tabs.cleanup": "panelCleanup",
      "tabs.tooling": "panelTooling"
    };
    Object.keys(map).forEach(function (tabId) {
      const btn = document.querySelector('[data-testid="' + tabId + '"]');
      const panel = document.getElementById(map[tabId]);
      const isSelected = tabId === activeId;
      if (btn) btn.classList.toggle("active", isSelected);
      if (panel) panel.hidden = !isSelected;
    });
    if (activeId === "tabs.tooling" && !state.toolingLoaded) {
      refreshToolingDiagnostics().catch(function (err) {
        setStatus("Unable to inspect developer CLIs.");
        appendLog(String(err));
      });
    }
  }

  function openConfirm(message, fn) {
    state.pendingAction = fn;
    const msgEl = document.getElementById("confirmMessage");
    const overlay = document.getElementById("confirmOverlay");
    if (msgEl) msgEl.textContent = message;
    if (overlay) overlay.hidden = false;
  }

  function closeConfirm() {
    state.pendingAction = null;
    const overlay = document.getElementById("confirmOverlay");
    if (overlay) overlay.hidden = true;
  }

  async function saveConfig() {
    setStatus("Saving config.yaml...");
    const res = await apiPost("/api/config", { sections: state.sections });
    setStatus(res.ok ? "Saved config.yaml selections." : "Could not save config.yaml.");
    if (res.output) appendLog(res.output);
  }

  async function refreshInitialData() {
    const cfg = await apiGet("/api/config");
    state.sections = cfg.sections || [];
    renderTweaks();
    const snaps = await apiGet("/api/snapshots");
    renderSnapshots(snaps.snapshots || []);
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelector('[data-testid="tabs.tweaks"]').addEventListener("click", function () { switchTab("tabs.tweaks"); });
    document.querySelector('[data-testid="tabs.cleanup"]').addEventListener("click", function () { switchTab("tabs.cleanup"); });
    document.querySelector('[data-testid="tabs.tooling"]').addEventListener("click", function () { switchTab("tabs.tooling"); });

    document.querySelector('[data-testid="header.theme_toggle"]').addEventListener("click", function (ev) {
      const root = document.documentElement;
      const isLight = root.getAttribute("data-theme") === "light";
      if (isLight) {
        root.removeAttribute("data-theme");
        ev.currentTarget.textContent = "Light Theme";
      } else {
        root.setAttribute("data-theme", "light");
        ev.currentTarget.textContent = "Dark Theme";
      }
    });

    document.querySelector('[data-testid="tweaks.search_input"]').addEventListener("input", function (ev) {
      state.filter = ev.target.value || "";
      renderTweaks();
    });

    document.querySelector('[data-testid="tweaks.save_btn"]').addEventListener("click", function () {
      saveConfig().catch(function (err) { setStatus("Save failed."); appendLog(String(err)); });
    });

    document.querySelector('[data-testid="tweaks.preview_btn"]').addEventListener("click", async function () {
      setStatus("Running dry-run preview (-WhatIf)...");
      await saveConfig();
      const res = await apiPost("/api/setup/preview", {});
      renderTweaksDiffs(res.diffs || []);
      setStatus("Preview complete.");
      appendLog(res.output || "");
    });

    document.querySelector('[data-testid="tweaks.apply_btn"]').addEventListener("click", function () {
      openConfirm("This saves a rollback snapshot and applies checked tweaks from config.yaml to Windows. Proceed?", async function () {
        setStatus("Creating snapshot and applying tweaks...");
        await saveConfig();
        const res = await apiPost("/api/setup/apply", {});
        setStatus(res.ok ? "Tweaks applied cleanly." : "Apply finished with warnings.");
        appendLog(res.output || "");
        const snaps = await apiGet("/api/snapshots");
        renderSnapshots(snaps.snapshots || []);
      });
    });

    document.querySelector('[data-testid="tweaks.revert_btn"]').addEventListener("click", function () {
      const snap = document.getElementById("tweaks.snapshot_select").value;
      if (!snap) {
        setStatus("No snapshot selected to revert.");
        return;
      }
      openConfirm("Restore Windows settings from snapshot " + snap + "?", async function () {
        setStatus("Reverting snapshot " + snap + "...");
        const res = await apiPost("/api/setup/revert", { snapshot: snap });
        setStatus(res.ok ? "Snapshot restored." : "Revert returned warnings.");
        appendLog(res.output || "");
      });
    });

    const minAgeInput = document.getElementById("minAgeInput");
    const minAgeSlider = document.getElementById("minAgeSlider");
    if (minAgeInput && minAgeSlider) {
      minAgeSlider.addEventListener("input", function () {
        minAgeInput.value = minAgeSlider.value;
      });
      minAgeInput.addEventListener("input", function () {
        const clamped = Math.max(0, Math.min(365, Number(minAgeInput.value || 0)));
        minAgeSlider.value = String(clamped);
      });
    }

    document.querySelector('[data-testid="cleanup.select_all"]').addEventListener("change", function (ev) {
      const checked = Boolean(ev.target.checked);
      state.cleanupItems.forEach(function (item) { item.selected = checked; });
      document.querySelectorAll(".cleanup-row-check").forEach(function (el) { el.checked = checked; });
      updateCleanupSummary();
    });

    document.querySelector('[data-testid="cleanup.scan_btn"]').addEventListener("click", async function () {
      const days = Number(document.getElementById("minAgeInput").value || 0);
      setStatus("Scanning Windows caches (dry run)...");
      const res = await apiPost("/api/cleanup/scan", { minAgeDays: days });
      renderCleanupTable(res.items || []);
      setStatus("Cache scan complete (" + (res.totalSize || "0 B") + ").");
      appendLog(res.output || "");
    });

    document.querySelector('[data-testid="cleanup.clean_btn"]').addEventListener("click", function () {
      const days = Number(document.getElementById("minAgeInput").value || 0);
      const selectedIds = state.cleanupItems.filter(function (it) { return it.selected; }).map(function (it) { return it.id; });
      if (state.cleanupItems.length > 0 && selectedIds.length === 0) {
        setStatus("Select at least one cleanup category first.");
        return;
      }
      const targetDesc = selectedIds.length > 0 ? (selectedIds.length + " selected target(s)") : "detected temporary and cache files";
      openConfirm("Permanently remove " + targetDesc + " older than " + days + " day(s)?", async function () {
        setStatus("Cleaning selected caches...");
        const res = await apiPost("/api/cleanup/run", { minAgeDays: days, targetIds: selectedIds });
        setStatus(res.ok ? "Cleanup finished." : "Cleanup completed with warnings.");
        appendLog(res.output || "");
      });
    });

    document.querySelector('[data-testid="tooling.refresh_btn"]').addEventListener("click", function () {
      refreshToolingDiagnostics().catch(function (err) {
        setStatus("Tooling inspection failed.");
        appendLog(String(err));
      });
    });

    document.querySelector('[data-testid="tooling.install_btn"]').addEventListener("click", function () {
      openConfirm("Install missing developer tools via winget, scoop, choco, or official scripts?", async function () {
        setStatus("Installing missing CLIs...");
        const res = await apiPost("/api/tooling/action", { mode: "install" });
        renderToolingTable(res.tools || []);
        setStatus("Tooling install finished.");
        appendLog(res.output || "");
      });
    });

    document.querySelector('[data-testid="tooling.update_btn"]').addEventListener("click", function () {
      openConfirm("Update installed developer CLIs to latest versions?", async function () {
        setStatus("Updating installed CLIs...");
        const res = await apiPost("/api/tooling/action", { mode: "update" });
        renderToolingTable(res.tools || []);
        setStatus("Tooling updates finished.");
        appendLog(res.output || "");
      });
    });

    document.querySelector('[data-testid="log.clear_btn"]').addEventListener("click", function () {
      appendLog("Ready.");
    });

    document.querySelector('[data-testid="confirm.cancel_btn"]').addEventListener("click", closeConfirm);
    document.querySelector('[data-testid="confirm.proceed_btn"]').addEventListener("click", async function () {
      const fn = state.pendingAction;
      closeConfirm();
      if (fn) await fn();
    });

    refreshInitialData().catch(function (err) {
      setStatus("Unable to load configuration from workspace.");
      appendLog(String(err));
    });
  });
})();
