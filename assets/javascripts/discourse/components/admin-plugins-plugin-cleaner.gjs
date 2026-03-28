import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { concat } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import DButton from "discourse/components/d-button";

// ── Risk badge ────────────────────────────────────────────────────────────────
const RiskBadge = <template>
  <span class="pc-badge pc-badge--{{@risk}}">
    {{i18n (concat "plugin_cleaner.risk." @risk)}}
  </span>
</template>;

// ── Status badge ──────────────────────────────────────────────────────────────
const StatusBadge = <template>
  <span class="pc-badge pc-badge--{{if @orphaned "medium" "none"}}">
    {{if @orphaned (i18n "plugin_cleaner.table.orphaned") (i18n "plugin_cleaner.table.active")}}
  </span>
</template>;

// ── Stat box ──────────────────────────────────────────────────────────────────
const StatBox = <template>
  <div class="pc-stat {{if @value "pc-stat--warn"}}">
    <span class="pc-stat__num">{{@value}}</span>
    <span class="pc-stat__lbl">{{@label}}</span>
  </div>
</template>;

// ── Main component ────────────────────────────────────────────────────────────
export default class AdminPluginsPluginCleaner extends Component {
  @tracked activeTab     = "scan";
  @tracked isScanning    = false;
  @tracked isDeleting    = false;
  @tracked scanResult    = null;
  @tracked versionLogs   = null;
  @tracked errorMessage  = null;
  @tracked _selected     = new Set();

  // ── Tabs ────────────────────────────────────────────────────────────────────
  @action
  switchTab(tab) {
    this.activeTab    = tab;
    this.errorMessage = null;
    if (tab === "versions" && !this.versionLogs) {
      this.#loadVersions();
    }
  }

  // ── Scan ────────────────────────────────────────────────────────────────────
  @action
  async runScan() {
    this.isScanning    = true;
    this.scanResult    = null;
    this.errorMessage  = null;
    this._selected     = new Set();

    try {
      this.scanResult = await ajax("/admin/plugins/plugin-cleaner/scan", { type: "GET" });
    } catch (e) {
      popupAjaxError(e);
      this.errorMessage = i18n("plugin_cleaner.errors.scan_failed");
    } finally {
      this.isScanning = false;
    }
  }

  // ── Selection ───────────────────────────────────────────────────────────────
  @action
  toggleItem(type, id) {
    const key  = `${type}::${id}`;
    const next = new Set(this._selected);
    next.has(key) ? next.delete(key) : next.add(key);
    this._selected = next;
  }

  isSelected(type, id) {
    return this._selected.has(`${type}::${id}`);
  }

  get selectedCount() {
    return this._selected.size;
  }

  // ── Delete ──────────────────────────────────────────────────────────────────
  @action
  async deleteSelected() {
    if (this._selected.size === 0) {
      this.errorMessage = i18n("plugin_cleaner.errors.nothing_selected");
      return;
    }

    if (
      !window.confirm(
        i18n("plugin_cleaner.confirm_delete", { count: this._selected.size })
      )
    ) return;

    this.isDeleting = true;

    const items = [...this._selected].map((key) => {
      const [type, ...rest] = key.split("::");
      return { type, id: rest.join("::") };
    });

    try {
      const result = await ajax("/admin/plugins/plugin-cleaner/delete", {
        type: "DELETE",
        data: { items },
      });

      const failed = (result.results || []).filter((r) => !r.success);
      if (failed.length > 0) {
        this.errorMessage = failed.map((f) => `${f.type}::${f.id} — ${f.error}`).join("; ");
      }

      this._selected = new Set();
      await this.runScan();
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.isDeleting = false;
    }
  }

  // ── Versions ─────────────────────────────────────────────────────────────────
  async #loadVersions() {
    try {
      const data   = await ajax("/admin/plugins/plugin-cleaner/versions", { type: "GET" });
      this.versionLogs = data.version_logs;
    } catch (e) {
      popupAjaxError(e);
    }
  }

  // ── Template ─────────────────────────────────────────────────────────────────
  <template>
    <div class="plugin-cleaner-admin">

      {{! Header }}
      <div class="plugin-cleaner-header">
        <h2>{{i18n "plugin_cleaner.title"}}</h2>
        <p>{{i18n "plugin_cleaner.description"}}</p>
      </div>

      {{! Tabs }}
      <div class="plugin-cleaner-tabs">
        <button
          class="pc-tab {{if (eq this.activeTab "scan") "active"}}"
          {{on "click" (fn this.switchTab "scan")}}>
          {{i18n "plugin_cleaner.nav.scan"}}
        </button>
        <button
          class="pc-tab {{if (eq this.activeTab "versions") "active"}}"
          {{on "click" (fn this.switchTab "versions")}}>
          {{i18n "plugin_cleaner.nav.versions"}}
        </button>
      </div>

      {{! Error }}
      {{#if this.errorMessage}}
        <div class="alert alert-error pc-alert">{{this.errorMessage}}</div>
      {{/if}}

      {{! ══════════════════════════════════════════════ }}
      {{! SCAN TAB                                       }}
      {{! ══════════════════════════════════════════════ }}
      {{#if (eq this.activeTab "scan")}}

        <div class="plugin-cleaner-toolbar">
          <DButton
            @action={{this.runScan}}
            @disabled={{this.isScanning}}
            @translatedLabel={{if this.isScanning
              (i18n "plugin_cleaner.actions.scanning")
              (i18n "plugin_cleaner.actions.run_scan")}}
            @icon={{if this.isScanning "spinner" "search"}}
            class="btn-primary"
          />

          {{#if this.selectedCount}}
            <DButton
              @action={{this.deleteSelected}}
              @disabled={{this.isDeleting}}
              @translatedLabel={{if this.isDeleting
                (i18n "plugin_cleaner.actions.deleting")
                (i18n "plugin_cleaner.actions.delete_selected")}}
              @icon={{if this.isDeleting "spinner" "trash-can"}}
              class="btn-danger"
            />
            <span class="pc-selected-count">
              {{this.selectedCount}} {{i18n "plugin_cleaner.table.action"}}ed
            </span>
          {{/if}}
        </div>

        {{#if this.scanResult}}

          {{! Scan meta }}
          <div class="pc-scan-meta">
            {{i18n "plugin_cleaner.status.scanned_at" time=this.scanResult.scanned_at}}
            &nbsp;·&nbsp;
            <strong class={{if this.scanResult.summary.total_issues "pc-has-issues"}}>
              {{i18n "plugin_cleaner.status.issues_found" count=this.scanResult.summary.total_issues}}
            </strong>
          </div>

          {{! Summary grid }}
          <div class="pc-summary-grid">
            <StatBox
              @value={{this.scanResult.summary.orphaned_custom_fields}}
              @label={{i18n "plugin_cleaner.summary.orphaned_custom_fields"}} />
            <StatBox
              @value={{this.scanResult.summary.orphaned_plugin_settings}}
              @label={{i18n "plugin_cleaner.summary.orphaned_plugin_settings"}} />
            <StatBox
              @value={{this.scanResult.summary.inactive_themes}}
              @label={{i18n "plugin_cleaner.summary.inactive_themes"}} />
            <StatBox
              @value={{this.scanResult.summary.disabled_badges}}
              @label={{i18n "plugin_cleaner.summary.disabled_badges"}} />
            <StatBox
              @value={{this.scanResult.summary.stale_api_keys}}
              @label={{i18n "plugin_cleaner.summary.stale_api_keys"}} />
            <StatBox
              @value={{this.scanResult.summary.failing_webhooks}}
              @label={{i18n "plugin_cleaner.summary.failing_webhooks"}} />
            <StatBox
              @value={{this.scanResult.summary.empty_tag_groups}}
              @label={{i18n "plugin_cleaner.summary.empty_tag_groups"}} />
            <StatBox
              @value={{this.scanResult.summary.orphaned_uploads}}
              @label={{i18n "plugin_cleaner.summary.orphaned_uploads"}} />
          </div>

          {{#unless this.scanResult.summary.total_issues}}
            <div class="alert alert-success pc-alert">
              {{i18n "plugin_cleaner.status.clean"}}
            </div>
          {{/unless}}

          {{! ── Custom Fields: User ── }}
          {{#if this.scanResult.custom_fields.user.length}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.custom_fields"}} — User</h3>
              <table class="pc-table">
                <thead>
                  <tr>
                    <th class="pc-col-check"></th>
                    <th>{{i18n "plugin_cleaner.table.field"}}</th>
                    <th>{{i18n "plugin_cleaner.table.records"}}</th>
                    <th>{{i18n "plugin_cleaner.table.risk"}}</th>
                    <th>{{i18n "plugin_cleaner.table.status"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.scanResult.custom_fields.user as |f|}}
                    <tr class={{if f.orphan "pc-row--orphan"}}>
                      <td>
                        {{#if f.orphan}}
                          <input
                            type="checkbox"
                            checked={{this.isSelected "user_custom_field" f.field}}
                            {{on "change" (fn this.toggleItem "user_custom_field" f.field)}}
                          />
                        {{/if}}
                      </td>
                      <td><code>{{f.field}}</code></td>
                      <td>{{f.count}}</td>
                      <td><RiskBadge @risk={{f.risk}} /></td>
                      <td><StatusBadge @orphaned={{f.orphan}} /></td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}

          {{! ── Custom Fields: Topic ── }}
          {{#if this.scanResult.custom_fields.topic.length}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.custom_fields"}} — Topic</h3>
              <table class="pc-table">
                <thead>
                  <tr>
                    <th class="pc-col-check"></th>
                    <th>{{i18n "plugin_cleaner.table.field"}}</th>
                    <th>{{i18n "plugin_cleaner.table.records"}}</th>
                    <th>{{i18n "plugin_cleaner.table.risk"}}</th>
                    <th>{{i18n "plugin_cleaner.table.status"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.scanResult.custom_fields.topic as |f|}}
                    <tr class={{if f.orphan "pc-row--orphan"}}>
                      <td>
                        {{#if f.orphan}}
                          <input
                            type="checkbox"
                            checked={{this.isSelected "topic_custom_field" f.field}}
                            {{on "change" (fn this.toggleItem "topic_custom_field" f.field)}}
                          />
                        {{/if}}
                      </td>
                      <td><code>{{f.field}}</code></td>
                      <td>{{f.count}}</td>
                      <td><RiskBadge @risk={{f.risk}} /></td>
                      <td><StatusBadge @orphaned={{f.orphan}} /></td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}

          {{! ── Custom Fields: Post ── }}
          {{#if this.scanResult.custom_fields.post.length}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.custom_fields"}} — Post</h3>
              <table class="pc-table">
                <thead>
                  <tr>
                    <th class="pc-col-check"></th>
                    <th>{{i18n "plugin_cleaner.table.field"}}</th>
                    <th>{{i18n "plugin_cleaner.table.records"}}</th>
                    <th>{{i18n "plugin_cleaner.table.risk"}}</th>
                    <th>{{i18n "plugin_cleaner.table.status"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.scanResult.custom_fields.post as |f|}}
                    <tr class={{if f.orphan "pc-row--orphan"}}>
                      <td>
                        {{#if f.orphan}}
                          <input
                            type="checkbox"
                            checked={{this.isSelected "post_custom_field" f.field}}
                            {{on "change" (fn this.toggleItem "post_custom_field" f.field)}}
                          />
                        {{/if}}
                      </td>
                      <td><code>{{f.field}}</code></td>
                      <td>{{f.count}}</td>
                      <td><RiskBadge @risk={{f.risk}} /></td>
                      <td><StatusBadge @orphaned={{f.orphan}} /></td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}

          {{! ── Plugin Settings ── }}
          {{#if this.scanResult.plugin_settings.length}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.plugin_settings"}}</h3>
              <table class="pc-table">
                <thead>
                  <tr>
                    <th>{{i18n "plugin_cleaner.table.setting"}}</th>
                    <th>{{i18n "plugin_cleaner.table.plugin"}}</th>
                    <th>{{i18n "plugin_cleaner.table.value"}}</th>
                    <th>{{i18n "plugin_cleaner.table.status"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.scanResult.plugin_settings as |s|}}
                    <tr class={{if s.orphaned "pc-row--orphan"}}>
                      <td><code>{{s.setting}}</code></td>
                      <td>{{s.plugin}}</td>
                      <td><code>{{s.value}}</code></td>
                      <td><StatusBadge @orphaned={{s.orphaned}} /></td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}

          {{! ── Themes ── }}
          {{#if this.scanResult.themes.length}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.themes"}}</h3>
              <table class="pc-table">
                <thead>
                  <tr>
                    <th class="pc-col-check"></th>
                    <th>{{i18n "plugin_cleaner.table.name"}}</th>
                    <th>{{i18n "plugin_cleaner.table.status"}}</th>
                    <th>{{i18n "plugin_cleaner.table.risk"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.scanResult.themes as |t|}}
                    <tr class={{if t.orphaned "pc-row--orphan"}}>
                      <td>
                        {{#if t.deletable}}
                          <input
                            type="checkbox"
                            checked={{this.isSelected "theme" t.id}}
                            {{on "change" (fn this.toggleItem "theme" t.id)}}
                          />
                        {{/if}}
                      </td>
                      <td>{{t.name}}</td>
                      <td><StatusBadge @orphaned={{t.orphaned}} /></td>
                      <td><RiskBadge @risk={{t.risk}} /></td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}

          {{! ── API Keys ── }}
          {{#if this.scanResult.api_keys.length}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.api_keys"}}</h3>
              <table class="pc-table">
                <thead>
                  <tr>
                    <th class="pc-col-check"></th>
                    <th>{{i18n "plugin_cleaner.table.name"}}</th>
                    <th>{{i18n "plugin_cleaner.table.user"}}</th>
                    <th>{{i18n "plugin_cleaner.table.last_used"}}</th>
                    <th>{{i18n "plugin_cleaner.table.status"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.scanResult.api_keys as |k|}}
                    <tr class={{if k.stale "pc-row--orphan"}}>
                      <td>
                        {{#if k.deletable}}
                          <input
                            type="checkbox"
                            checked={{this.isSelected "api_key" k.id}}
                            {{on "change" (fn this.toggleItem "api_key" k.id)}}
                          />
                        {{/if}}
                      </td>
                      <td>{{k.description}}</td>
                      <td>{{k.user}}</td>
                      <td>{{if k.last_used k.last_used (i18n "plugin_cleaner.table.never")}}</td>
                      <td><StatusBadge @orphaned={{k.stale}} /></td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}

          {{! ── Badges ── }}
          {{#if this.scanResult.badges.length}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.badges"}}</h3>
              <table class="pc-table">
                <thead>
                  <tr>
                    <th class="pc-col-check"></th>
                    <th>{{i18n "plugin_cleaner.table.name"}}</th>
                    <th>Grants</th>
                    <th>{{i18n "plugin_cleaner.table.status"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.scanResult.badges as |b|}}
                    {{#if b.orphaned}}
                      <tr class="pc-row--orphan">
                        <td>
                          <input
                            type="checkbox"
                            checked={{this.isSelected "badge" b.id}}
                            {{on "change" (fn this.toggleItem "badge" b.id)}}
                          />
                        </td>
                        <td>{{b.name}}</td>
                        <td>{{b.grant_count}}</td>
                        <td><StatusBadge @orphaned={{true}} /></td>
                      </tr>
                    {{/if}}
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}

          {{! ── Tag Groups ── }}
          {{#if this.scanResult.tag_groups.length}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.tag_groups"}}</h3>
              <table class="pc-table">
                <thead>
                  <tr>
                    <th class="pc-col-check"></th>
                    <th>{{i18n "plugin_cleaner.table.name"}}</th>
                    <th>Tags</th>
                    <th>{{i18n "plugin_cleaner.table.status"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.scanResult.tag_groups as |t|}}
                    <tr class={{if t.orphaned "pc-row--orphan"}}>
                      <td>
                        {{#if t.deletable}}
                          <input
                            type="checkbox"
                            checked={{this.isSelected "tag_group" t.id}}
                            {{on "change" (fn this.toggleItem "tag_group" t.id)}}
                          />
                        {{/if}}
                      </td>
                      <td>{{t.name}}</td>
                      <td>{{t.tag_count}}</td>
                      <td><StatusBadge @orphaned={{t.orphaned}} /></td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}

          {{! ── Webhooks ── }}
          {{#if this.scanResult.web_hooks.length}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.webhooks"}}</h3>
              <table class="pc-table">
                <thead>
                  <tr>
                    <th>{{i18n "plugin_cleaner.table.url"}}</th>
                    <th>{{i18n "plugin_cleaner.table.active"}}</th>
                    <th>Last Status</th>
                    <th>{{i18n "plugin_cleaner.table.last_used"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.scanResult.web_hooks as |w|}}
                    <tr class={{if w.failing "pc-row--orphan"}}>
                      <td><code>{{w.payload_url}}</code></td>
                      <td>{{if w.active "✅" "❌"}}</td>
                      <td>{{if w.last_status w.last_status "—"}}</td>
                      <td>{{if w.last_triggered w.last_triggered (i18n "plugin_cleaner.table.never")}}</td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}

          {{! ── Uploads ── }}
          {{#if this.scanResult.uploads.checked}}
            <div class="pc-section">
              <h3>{{i18n "plugin_cleaner.sections.uploads"}}</h3>
              <div class="pc-summary-grid">
                <StatBox @value={{this.scanResult.uploads.total}} @label="Total" />
                <StatBox
                  @value={{this.scanResult.uploads.orphaned}}
                  @label={{concat "Orphaned (" this.scanResult.uploads.orphaned_pct "%)"}}
                />
              </div>
              {{#if this.scanResult.uploads.orphaned}}
                <p class="pc-note">
                  Run <code>rake uploads:clean</code> from the server to reclaim space.
                </p>
              {{/if}}
            </div>
          {{/if}}

        {{/if}}{{! end scanResult }}

      {{/if}}{{! end scan tab }}

      {{! ══════════════════════════════════════════════ }}
      {{! VERSIONS TAB                                   }}
      {{! ══════════════════════════════════════════════ }}
      {{#if (eq this.activeTab "versions")}}
        <div class="pc-section">
          <h3>{{i18n "plugin_cleaner.versions.title"}}</h3>

          {{#if this.versionLogs}}
            <table class="pc-table">
              <thead>
                <tr>
                  <th>{{i18n "plugin_cleaner.versions.plugin"}}</th>
                  <th>{{i18n "plugin_cleaner.versions.version"}}</th>
                  <th>{{i18n "plugin_cleaner.versions.status"}}</th>
                  <th>{{i18n "plugin_cleaner.versions.recorded_at"}}</th>
                  <th>{{i18n "plugin_cleaner.versions.notes"}}</th>
                </tr>
              </thead>
              <tbody>
                {{#each this.versionLogs as |log|}}
                  <tr class={{if (eq log.status "removed") "pc-row--orphan"}}>
                    <td><code>{{log.plugin_name}}</code></td>
                    <td>{{log.version}}</td>
                    <td>
                      <span class="pc-badge pc-badge--{{if (eq log.status "active") "none" "medium"}}">
                        {{if (eq log.status "active")
                          (i18n "plugin_cleaner.versions.status_active")
                          (i18n "plugin_cleaner.versions.status_removed")}}
                      </span>
                    </td>
                    <td>{{log.recorded_at}}</td>
                    <td>{{log.notes}}</td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          {{else}}
            <p class="pc-note">{{i18n "plugin_cleaner.versions.loading"}}</p>
          {{/if}}
        </div>
      {{/if}}

    </div>
  </template>
}
