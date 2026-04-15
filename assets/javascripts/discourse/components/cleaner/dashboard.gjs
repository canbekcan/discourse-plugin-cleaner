import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import i18n from "discourse-common/helpers/i18n";
import DButton from "discourse/components/d-button";

export default class CleanerDashboard extends Component {
  @tracked isScanning = false;
  @tracked isPurging = false;
  @tracked dryRun = true;
  @tracked scanResults = null;

  @action
  async scan() {
    this.isScanning = true;
    try {
      this.scanResults = await ajax("/admin/plugins/plugin-cleaner/scan");
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.isScanning = false;
    }
  }

  @action
  toggleDryRun() {
    this.dryRun = !this.dryRun;
  }

  @action
  async purge(dataType, items) {
    if (!items || items.length === 0) return;

    if (!this.dryRun && !window.confirm(i18n("plugin_cleaner.ui.confirm_purge"))) {
      return;
    }

    this.isPurging = true;
    const itemIds = items.map((i) => i.id);

    try {
      const response = await ajax("/admin/plugins/plugin-cleaner/purge", {
        type: "DELETE",
        data: JSON.stringify({ data_type: dataType, items: itemIds, dry_run: this.dryRun }),
        contentType: "application/json",
      });

      const msg = response.dry_run
        ? i18n("plugin_cleaner.ui.dry_run_success", { count: response.purged_count })
        : i18n("plugin_cleaner.ui.purge_success", { count: response.purged_count });
        
      alert(msg);
      await this.scan(); // Refresh data
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.isPurging = false;
    }
  }

  <template>
    <div class="plugin-cleaner-dashboard">
      <h2>{{i18n "plugin_cleaner.title"}}</h2>
      <p>{{i18n "plugin_cleaner.description"}}</p>

      <div class="cleaner-controls">
        <DButton
          @action={{this.scan}}
          @disabled={{this.isScanning}}
          @icon="search"
          @translatedLabel={{i18n "plugin_cleaner.ui.scan_button"}}
          class="btn-primary"
        />

        <label class="dry-run-toggle">
          <input 
            type="checkbox" 
            checked={{this.dryRun}} 
            {{on "change" this.toggleDryRun}} 
          />
          {{i18n "plugin_cleaner.ui.dry_run_label"}}
        </label>
      </div>

      {{#if this.scanResults}}
        <div class="cleaner-results">
          
          {{!-- Plugin Store Section --}}
          <section class="result-section">
            <h3>{{i18n "plugin_cleaner.categories.plugin_store"}} ({{this.scanResults.plugin_store.length}})</h3>
            {{#if this.scanResults.plugin_store.length}}
              <DButton
                @action={{fn this.purge "plugin_store" this.scanResults.plugin_store}}
                @disabled={{this.isPurging}}
                @icon="trash-can"
                @translatedLabel={{i18n "plugin_cleaner.ui.purge_button"}}
                class="btn-danger"
              />
            {{/if}}
          </section>

          {{!-- Theme Settings Section --}}
          <section class="result-section">
            <h3>{{i18n "plugin_cleaner.categories.theme_settings"}} ({{this.scanResults.theme_settings.length}})</h3>
            {{#if this.scanResults.theme_settings.length}}
              <DButton
                @action={{fn this.purge "theme_settings" this.scanResults.theme_settings}}
                @disabled={{this.isPurging}}
                @icon="trash-can"
                @translatedLabel={{i18n "plugin_cleaner.ui.purge_button"}}
                class="btn-danger"
              />
            {{/if}}
          </section>

          {{!-- Site Settings Section --}}
          <section class="result-section">
            <h3>{{i18n "plugin_cleaner.categories.site_settings"}} ({{this.scanResults.site_settings.length}})</h3>
            {{#if this.scanResults.site_settings.length}}
              <DButton
                @action={{fn this.purge "site_settings" this.scanResults.site_settings}}
                @disabled={{this.isPurging}}
                @icon="trash-can"
                @translatedLabel={{i18n "plugin_cleaner.ui.purge_button"}}
                class="btn-danger"
              />
            {{/if}}
          </section>

        </div>
      {{/if}}
    </div>
  </template>
}