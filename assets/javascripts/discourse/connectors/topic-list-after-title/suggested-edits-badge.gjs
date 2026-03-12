import Component from "@glimmer/component";
import { service } from "@ember/service";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class SuggestedEditsBadge extends Component {
  @service siteSettings;

  get count() {
    return this.args.outletArgs.topic?.suggested_edit_count;
  }

  get shouldRender() {
    return this.siteSettings.suggested_edits_enabled && this.count > 0;
  }

  get titleText() {
    return i18n("discourse_suggested_edits.badge.title", {
      count: this.count,
    });
  }

  <template>
    {{#if this.shouldRender}}
      <span class="suggested-edits-badge" title={{this.titleText}}>
        {{icon "pen-to-square"}}
        {{this.count}}
      </span>
    {{/if}}
  </template>
}
