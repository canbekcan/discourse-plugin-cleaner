import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

export default class AdminPluginsPluginCleanerController extends Controller {
  // ── State ──────────────────────────────────────────────────────────────────
  @tracked activeTab     = "scan";   // "scan" | "versions"
  @tracked isScanning    = false;
  @tracked isDeleting    = false;
  @tracked scanResult    = null;
  @tracked versionLogs   = null;
  @tracked errorMessage  = null;
  @tracked selectedItems = new Set();

  // ── Tab switching ──────────────────────────────────────────────────────────
  @action
  switchTab(tab) {
    this.activeTab = tab;
    this.errorMessage = null;

    if (tab === "versions" && !this.versionLogs) {
      this.loadVersions();
    }
  }

  // ── Scan ───────────────────────────────────────────────────────────────────
  @action
  async runScan() {
    this.isScanning   = true;
    this.scanResult   = null;
    this.errorMessage = null;
    this.selectedItems = new Set();

    try {
      this.scanResult = await ajax("/admin/plugins/plugin-cleaner/scan", { type: "GET" });
    } catch (e) {
      popupAjaxError(e);
      this.errorMessage = i18n("plugin_cleaner.errors.scan_failed");
    } finally {
      this.isScanning = false;
    }
  }

  // ── Selection ──────────────────────────────────────────────────────────────
  @action
  toggleItem(type, id) {
    const key = `${type}::${id}`;
    const next = new Set(this.selectedItems);
    next.has(key) ? next.delete(key) : next.add(key);
    this.selectedItems = next;
  }

  isSelected(type, id) {
    return this.selectedItems.has(`${type}::${id}`);
  }

  @action
  selectAll(type, items) {
    const next = new Set(this.selectedItems);
    items.forEach((item) => next.add(`${type}::${item.id ?? item.field ?? item.name}`));
    this.selectedItems = next;
  }

  @action
  deselectAll(type, items) {
    const next = new Set(this.selectedItems);
    items.forEach((item) => next.delete(`${type}::${item.id ?? item.field ?? item.name}`));
    this.selectedItems = next;
  }

  get selectedCount() {
    return this.selectedItems.size;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  @action
  async deleteSelected() {
    if (this.selectedItems.size === 0) {
      this.errorMessage = i18n("plugin_cleaner.errors.nothing_selected");
      return;
    }

    const confirmed = window.confirm(
      i18n("plugin_cleaner.confirm_delete", { count: this.selectedItems.size })
    );
    if (!confirmed) return;

    this.isDeleting = true;

    const items = [...this.selectedItems].map((key) => {
      const [type, ...rest] = key.split("::");
      return { type, id: rest.join("::") };
    });

    try {
      const result = await ajax("/admin/plugins/plugin-cleaner/delete", {
        type: "DELETE",
        data: { items },
      });

      const failed = result.results.filter((r) => !r.success);
      if (failed.length > 0) {
        this.errorMessage = failed.map((f) => `${f.type}::${f.id} — ${f.error}`).join("; ");
      }

      this.selectedItems = new Set();
      await this.runScan(); // refresh after deletion
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.isDeleting = false;
    }
  }

  // ── Versions ───────────────────────────────────────────────────────────────
  async loadVersions() {
    try {
      const data = await ajax("/admin/plugins/plugin-cleaner/versions", { type: "GET" });
      this.versionLogs = data.version_logs;
    } catch (e) {
      popupAjaxError(e);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  get hasScanResult() {
    return !!this.scanResult;
  }

  get deletableItems() {
    if (!this.scanResult) return [];

    const items = [];
    const cf = this.scanResult.custom_fields || {};

    ["user", "topic", "post", "category", "group"].forEach((model) => {
      (cf[model] || [])
        .filter((f) => f.orphan)
        .forEach((f) => items.push({ type: `${model}_custom_field`, id: f.field, label: f.field, risk: f.risk }));
    });

    (this.scanResult.themes || [])
      .filter((t) => t.deletable)
      .forEach((t) => items.push({ type: "theme", id: t.id, label: t.name, risk: t.risk }));

    (this.scanResult.badges || [])
      .filter((b) => b.deletable)
      .forEach((b) => items.push({ type: "badge", id: b.id, label: b.name, risk: b.risk }));

    (this.scanResult.tag_groups || [])
      .filter((t) => t.deletable)
      .forEach((t) => items.push({ type: "tag_group", id: t.id, label: t.name, risk: t.risk }));

    (this.scanResult.api_keys || [])
      .filter((k) => k.deletable)
      .forEach((k) => items.push({ type: "api_key", id: k.id, label: k.description, risk: k.risk }));

    return items;
  }
}
