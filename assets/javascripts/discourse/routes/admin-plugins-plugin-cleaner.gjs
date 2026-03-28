import DiscourseRoute from "discourse/routes/discourse";
import AdminPluginsPluginCleaner from "../components/admin-plugins-plugin-cleaner";

export default class AdminPluginsPluginCleanerRoute extends DiscourseRoute {
  model() {
    return {};
  }

  renderTemplate() {
    this.render("admin-plugins-plugin-cleaner");
  }
}
