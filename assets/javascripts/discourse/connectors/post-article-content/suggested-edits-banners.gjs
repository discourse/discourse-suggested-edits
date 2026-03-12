import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import SuggestedEditsReviewModal from "discourse/plugins/discourse-suggested-edits/discourse/components/modal/suggested-edits-review";
import { openSuggestedEditComposer } from "discourse/plugins/discourse-suggested-edits/discourse/lib/open-suggested-edit-composer";
import { deleteSuggestedEdit } from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

export default class SuggestedEditsBanners extends Component {
  @service siteSettings;
  @service modal;
  @service dialog;
  @service toasts;
  @service composer;

  @tracked withdrawn = false;

  get post() {
    return this.args.outletArgs.post;
  }

  get isFirstPost() {
    return (
      this.siteSettings.suggested_edits_enabled && this.post?.post_number === 1
    );
  }

  get ownPendingSuggestionId() {
    return this.post?.topic?.own_pending_suggested_edit_id;
  }

  get showOwnBanner() {
    return this.isFirstPost && this.ownPendingSuggestionId && !this.withdrawn;
  }

  @action
  async openRevise() {
    try {
      await openSuggestedEditComposer(this.composer, this.post);
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  withdraw() {
    this.dialog.yesNoConfirm({
      message: i18n("discourse_suggested_edits.banner.withdraw_confirm"),
      didConfirm: async () => {
        try {
          await deleteSuggestedEdit(this.ownPendingSuggestionId);
          this.withdrawn = true;
          this.post.topic.set("own_pending_suggested_edit_id", null);
          this.toasts.success({
            data: {
              message: i18n("discourse_suggested_edits.toast.withdrawn"),
            },
            duration: "short",
          });
        } catch (e) {
          popupAjaxError(e);
        }
      },
    });
  }

  get reviewCount() {
    return this.post?.topic?.pending_suggested_edit_count;
  }

  get showReviewBanner() {
    return this.isFirstPost && this.reviewCount > 0;
  }

  @action
  openReview() {
    this.modal.show(SuggestedEditsReviewModal, {
      model: {
        post: this.post,
      },
    });
  }

  <template>
    {{#if this.showOwnBanner}}
      <div class="suggested-edits-banner suggested-edits-banner--own">
        <div class="suggested-edits-banner__content">
          <span class="suggested-edits-banner__text">
            {{i18n "discourse_suggested_edits.banner.own_pending"}}
          </span>
        </div>
        <div class="suggested-edits-banner__actions">
          <DButton
            @action={{this.openRevise}}
            @label="discourse_suggested_edits.banner.edit"
            class="btn-default btn-small suggested-edits-banner__action"
          />
          <DButton
            @action={{this.withdraw}}
            @label="discourse_suggested_edits.banner.withdraw"
            class="btn-flat btn-small btn-danger suggested-edits-banner__action"
          />
        </div>
      </div>
    {{/if}}

    {{#if this.showReviewBanner}}
      <div class="suggested-edits-banner suggested-edits-banner--review">
        <div class="suggested-edits-banner__content">
          <span class="suggested-edits-banner__text">
            {{i18n
              "discourse_suggested_edits.banner.pending_review"
              count=this.reviewCount
            }}
          </span>
        </div>
        <div class="suggested-edits-banner__actions">
          <DButton
            @action={{this.openReview}}
            @label="discourse_suggested_edits.banner.review"
            class="btn-primary btn-small suggested-edits-banner__action"
          />
        </div>
      </div>
    {{/if}}

    {{yield}}
  </template>
}
