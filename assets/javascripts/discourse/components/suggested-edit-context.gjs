import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trustHTML } from "@ember/template";
import DButton from "discourse/components/d-button";
import { afterRender } from "discourse/lib/decorators";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dUniqueId from "discourse/ui-kit/helpers/d-unique-id";
import openSuggestedEditLink from "../lib/open-suggested-edit-link";

export default class SuggestedEditContext extends Component {
  contentId = `suggested-edit-context-${dUniqueId()}`;

  get isSource() {
    return this.args.viewMode === "source";
  }

  get isSideBySide() {
    return this.args.viewMode === "side-by-side";
  }

  get isVisible() {
    return Boolean(
      (this.isSource ? this.args.gap.raw : this.args.gap.html)?.trim()
    );
  }

  @action
  toggle(_, event) {
    const button = event.target.closest("button");
    const modal = button.closest(".d-modal__body");
    const top = button.getBoundingClientRect().top;
    const collapsing = this.args.expanded;
    this.args.onToggle();
    if (collapsing) {
      this._restoreAnchor(button, modal, top);
    }
  }

  @afterRender
  _restoreAnchor(button, modal, top) {
    if (modal && button.isConnected) {
      const bounds = modal.getBoundingClientRect();
      const scale = bounds.height / modal.offsetHeight || 1;
      modal.scrollTop += (button.getBoundingClientRect().top - top) / scale;
      button.focus({ preventScroll: true });
    }
  }

  <template>
    {{#if this.isVisible}}
      <div
        class={{dConcatClass
          "suggested-edit-context"
          (if @expanded "--expanded")
        }}
        data-context-id={{@gap.id}}
        ...attributes
      >
        <div class="suggested-edit-context__toggle-row">
          <DButton
            @action={{this.toggle}}
            @forwardEvent={{true}}
            @icon={{if @expanded "chevron-up" "chevron-down"}}
            @label={{if
              @expanded
              "discourse_suggested_edits.review.collapse_context"
              "discourse_suggested_edits.review.expand_context"
            }}
            aria-controls={{this.contentId}}
            aria-expanded={{if @expanded "true" "false"}}
            class="btn-flat suggested-edit-context__toggle"
          />
        </div>
        {{! template-lint-disable no-invalid-interactive }}
        <div
          id={{this.contentId}}
          class={{dConcatClass
            "suggested-edit-context__body"
            (if this.isSource "--source" "cooked")
          }}
          hidden={{if @expanded false true}}
          {{on "click" openSuggestedEditLink}}
        >
          {{#if @expanded}}
            {{#if this.isSource}}
              <pre>{{@gap.raw}}</pre>
            {{else if this.isSideBySide}}
              <div class="suggested-edit-context__columns">
                <div
                  class="suggested-edit-context__side revision-content"
                >{{trustHTML @gap.html}}</div>
                <div
                  class="suggested-edit-context__side revision-content"
                >{{trustHTML @gap.html}}</div>
              </div>
            {{else}}
              {{trustHTML @gap.html}}
            {{/if}}
          {{/if}}
        </div>
      </div>
    {{/if}}
  </template>
}
