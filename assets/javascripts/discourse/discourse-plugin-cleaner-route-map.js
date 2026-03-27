export default {
  resource: "admin.plugins",
  map() {
    this.route("plugin-cleaner", { path: "plugin-cleaner" });
  }
};