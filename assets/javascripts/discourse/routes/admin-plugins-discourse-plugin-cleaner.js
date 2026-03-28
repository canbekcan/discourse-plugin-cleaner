export default class DiscoursePluginCleanerRoute extends Route {
  model() {
    return ajax("/admin/discourse-plugin-cleaner/scan");
  }
}