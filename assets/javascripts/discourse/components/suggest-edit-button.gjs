import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { openSuggestedEditComposer } from "discourse/plugins/discourse-suggested-edits/discourse/lib/open-suggested-edit-composer";

export default class SuggestEditButton extends Component {
  @service composer;

  @action
  async openSuggestEdit() {
    try {
      await openSuggestedEditComposer(this.composer, this.args.post);
    } catch (e) {
      popupAjaxError(e);
    }
  }

  <template>
    <DButton
      class="post-action-menu__suggest-edit suggest-edit"
      ...attributes
      @action={{this.openSuggestEdit}}
      @icon="pen-to-square"
      @title="discourse_suggested_edits.suggest_edit_title"
    />
  </template>
}
