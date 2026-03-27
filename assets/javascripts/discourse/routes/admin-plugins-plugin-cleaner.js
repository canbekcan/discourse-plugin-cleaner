import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class PluginCleanerRoute extends Route {
  model() {
    return ajax("/admin/plugin-cleaner/scan");
  }
}