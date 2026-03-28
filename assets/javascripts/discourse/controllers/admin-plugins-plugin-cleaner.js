import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class AdminPluginsPluginCleanerController extends Controller {
  @tracked isScanning = false;
  @tracked scanResult = null;
  @tracked errorMessage = null;

  @action
  async runScan() {
    this.isScanning = true;
    this.scanResult = null;
    this.errorMessage = null;

    try {
      const result = await ajax("/admin/plugins/plugin-cleaner/scan", {
        type: "GET",
      });
      this.scanResult = result;
    } catch (e) {
      popupAjaxError(e);
      this.errorMessage = "Scan failed. Check logs for details.";
    } finally {
      this.isScanning = false;
    }
  }
}
