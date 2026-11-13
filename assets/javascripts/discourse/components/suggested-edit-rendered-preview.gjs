import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trustHTML } from "@ember/template";
import DButton from "discourse/components/d-button";
import { afterRender } from "discourse/lib/decorators";
import { eq, or } from "discourse/truth-helpers";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import { i18n } from "discourse-i18n";
import openSuggestedEditLink from "../lib/open-suggested-edit-link";

const UNAVAILABLE_MESSAGES = {
  post_changed:
    "discourse_suggested_edits.review.preview.unavailable.post_changed",
  unsupported_post:
    "discourse_suggested_edits.review.preview.unavailable.unsupported_post",
  too_complex:
    "discourse_suggested_edits.review.preview.unavailable.too_complex",
  not_pending:
    "discourse_suggested_edits.review.preview.unavailable.not_pending",
  rate_limited:
    "discourse_suggested_edits.review.preview.unavailable.rate_limited",
};

export function unavailableNotice(reason) {
  return i18n(
    UNAVAILABLE_MESSAGES[reason] ??
      "discourse_suggested_edits.review.preview.unavailable.error"
  );
}

export default class SuggestedEditRenderedPreview extends Component {
  get mode() {
    if (
      !this.args.preview?.available ||
      !this.args.preview.inline ||
      !this.args.preview.sideBySide ||
      this.args.viewMode === "source"
    ) {
      return null;
    }

    return this.args.viewMode === "inline" || this.args.stacked
      ? "inline"
      : "side-by-side";
  }

  get html() {
    return this.mode === "inline"
      ? this.args.preview.inline
      : this.args.preview.sideBySide;
  }

  get fallbackNotice() {
    const preview = this.args.preview;
    if (
      !preview ||
      preview.available ||
      (this.args.loading && !preview.failed)
    ) {
      return null;
    }

    return unavailableNotice(preview.unavailableReason);
  }

  get canRetry() {
    return Boolean(this.args.preview?.failed && this.args.onRetry);
  }

  @action
  async retry(_, event) {
    if (this.args.loading) {
      return;
    }

    const modal = event.target.closest(".d-modal__body");
    const section = event.target.closest(".suggested-edit-preview");
    await this.args.onRetry();
    if (!this.isDestroying && !this.isDestroyed) {
      this._restoreFocus(modal ?? section);
    }
  }

  // Finishing a retry can remove the focused retry button with its notice.
  @afterRender
  _restoreFocus(section) {
    if (document.activeElement === document.body) {
      (
        section.querySelector(".suggested-edit-preview__body") ??
        section.querySelector(".suggested-edit-preview__fallback") ??
        (section.matches(".d-modal__body") ? section : null)
      )?.focus();
    }
  }

  <template>
    {{#if (or @loading this.fallbackNotice this.mode)}}
      <section class="suggested-edit-preview" ...attributes>
        {{#if this.fallbackNotice}}
          <div
            class="suggested-edit-preview__fallback alert alert-info"
            tabindex="-1"
          >
            <span>{{this.fallbackNotice}}</span>
            {{#if this.canRetry}}
              {{! Stays focusable while loading, as disabling it would drop focus. }}
              <DButton
                @action={{this.retry}}
                @forwardEvent={{true}}
                @icon="arrows-rotate"
                @label={{if
                  @loading
                  "loading"
                  "discourse_suggested_edits.review.preview.retry"
                }}
                aria-disabled={{if @loading "true"}}
                class={{dConcatClass
                  "btn-default btn-small suggested-edit-preview__retry"
                  (if @loading "disabled")
                }}
              />
            {{/if}}
          </div>
        {{/if}}
        {{#if @loading}}
          <div class="spinner small"></div>
        {{else if this.mode}}
          {{! template-lint-disable no-invalid-interactive }}
          <div
            class={{dConcatClass
              "suggested-edit-preview__body cooked"
              (if (eq this.mode "inline") "--inline" "--side-by-side")
            }}
            data-preview-mode={{this.mode}}
            tabindex="-1"
            {{on "click" openSuggestedEditLink}}
          >
            {{trustHTML this.html}}
          </div>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
