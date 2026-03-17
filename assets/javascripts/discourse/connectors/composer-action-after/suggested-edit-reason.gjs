import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { SUGGEST_EDIT_ACTION } from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

export default class SuggestedEditReason extends Component {
  @tracked showInput = false;

  constructor() {
    super(...arguments);
    if (this.model?.metaData?.reason) {
      this.showInput = true;
    }
  }

  get model() {
    return this.args.outletArgs.model;
  }

  get shouldRender() {
    return this.model?.action === SUGGEST_EDIT_ACTION;
  }

  get reason() {
    return this.model?.metaData?.reason || "";
  }

  @action
  showReasonInput(event) {
    event.preventDefault();
    this.showInput = true;
    schedule("afterRender", () => {
      document.querySelector(".suggested-edit-reason__input")?.focus();
    });
  }

  @action
  onInput(event) {
    if (this.model?.metaData) {
      this.model.metaData.reason = event.target.value;
    }
  }

  <template>
    {{#if this.shouldRender}}
      <span class="suggested-edit-reason">
        {{#if this.showInput}}
          <input
            type="text"
            class="suggested-edit-reason__input"
            value={{this.reason}}
            maxlength="255"
            placeholder={{i18n
              "discourse_suggested_edits.composer.reason_placeholder"
            }}
            {{on "input" this.onInput}}
          />
        {{else}}
          <a
            href
            class="suggested-edit-reason__link"
            {{on "click" this.showReasonInput}}
          >
            {{icon "pen-to-square"}}
            {{i18n "discourse_suggested_edits.composer.add_reason"}}
          </a>
        {{/if}}
      </span>
    {{/if}}
  </template>
}
