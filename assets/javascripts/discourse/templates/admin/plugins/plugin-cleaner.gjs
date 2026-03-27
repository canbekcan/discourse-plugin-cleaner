import Component from "@glimmer/component";
import i18n from "discourse-common/helpers/i18n";

export default class PluginCleaner extends Component {
  <template>
    <div class="admin-controls">
      <h2>{{i18n "plugin_cleaner.title"}}</h2>
    </div>

    <div class="admin-container">
      <p><strong>{{i18n "plugin_cleaner.total_fields"}}</strong> {{@model.summary.total_custom_fields}}</p>
      <p style="color: red;"><strong>{{i18n "plugin_cleaner.suspicious"}}</strong> {{@model.summary.suspicious_fields_count}}</p>
      
      <br>
      <h3>{{i18n "plugin_cleaner.detected"}}</h3>
      <ul>
        {{#each @model.recommendation as |rec|}}
          <li>{{rec}}</li>
        {{else}}
          <li>{{i18n "plugin_cleaner.clean"}}</li>
        {{/each}}
      </ul>
    </div>
  </template>
}