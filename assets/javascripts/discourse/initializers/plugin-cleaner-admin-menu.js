import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "plugin-cleaner-admin-menu",
  initialize() {
    withPluginApi("0.8", (api) => {
      // Admin panelindeki Plugins bölümüne sayfamızın butonunu ekliyoruz
      api.addAdminRoute("plugins.plugin-cleaner", "admin.plugins.plugin_cleaner");
    });
  }
};