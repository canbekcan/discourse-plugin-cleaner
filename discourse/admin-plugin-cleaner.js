import { apiRequest } from "discourse/lib/ajax";

export default {
  setupComponent() {
    apiRequest("/admin/plugin-cleaner/scan").then(result => {
      console.log("PLUGIN CLEANER REPORT", result);
    });
  }
};