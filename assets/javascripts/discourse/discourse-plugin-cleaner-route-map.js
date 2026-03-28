import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class DiscoursePluginCleanerRoute extends Route {
  model() {
    return ajax("/admin/discourse-plugin-cleaner/scan");
  }
}