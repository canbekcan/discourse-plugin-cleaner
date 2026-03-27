import { ajax } from "discourse/lib/ajax";
import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "admin-plugin-cleaner",
  initialize() {
    withPluginApi("0.8", (api) => {
      // Şimdilik test için konsola yazdıran orijinal mantığınızı Discourse ajax metoduyla koruyoruz
      ajax("/admin/plugin-cleaner/scan").then(result => {
        console.log("PLUGIN CLEANER REPORT:", result);
      }).catch(error => {
        console.error("Plugin Cleaner API Hatası:", error);
      });
    });
  }
};