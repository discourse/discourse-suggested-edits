import {
  click,
  fillIn,
  find,
  findAll,
  render,
  settled,
  waitFor,
  waitUntil,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import LiveRegions, {
  IDLE_ANNOUNCEMENT,
} from "discourse/components/a11y/live-regions";
import ModalContainer from "discourse/components/modal-container";
import KeyValueStore from "discourse/lib/key-value-store";
import { forceMobile } from "discourse/lib/mobile";
import { disableClearA11yAnnouncementsInTests } from "discourse/services/a11y";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import SuggestedEditsReviewModal from "discourse/plugins/discourse-suggested-edits/discourse/components/modal/suggested-edits-review";
import SuggestedEditsStaleWarning from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edits-stale-warning";

const UPDATED_AT = "2026-11-12T10:00:00.000Z";
const LATER_UPDATED_AT = "2026-11-12T11:00:00.000Z";

function buildChange(id, position, before, after) {
  return {
    id,
    position,
    before_text: before,
    after_text: after,
    diff_html: `<div class="inline-diff"><del class="diff-del">${before}</del><ins class="diff-ins">${after}</ins></div>`,
    side_by_side_before_html: `<div class="side-by-side-diff__before"><del class="diff-del">${before}</del></div>`,
    side_by_side_after_html: `<div class="side-by-side-diff__after"><ins class="diff-ins">${after}</ins></div>`,
    preview_context_before: "",
    preview_context_after: "",
    context_before: "",
    context_after: "",
  };
}

function buildSuggestion(id, changes, updatedAt = UPDATED_AT) {
  return {
    id,
    post_id: 1,
    status: "pending",
    created_at: UPDATED_AT,
    updated_at: updatedAt,
    user: {
      id: 2,
      username: "user2",
      avatar_template: "/letter_avatar_proxy/v4/letter/u/f475e1/{size}.png",
    },
    changes,
  };
}

const SUGGESTION = buildSuggestion(7, [
  buildChange(11, 0, "Original", "Updated"),
  buildChange(12, 1, "lake.png", "lake-blue.png"),
]);
const OTHER_SUGGESTION = buildSuggestion(8, [
  buildChange(13, 0, "Intro", "Introduction"),
]);
const REVISED_SUGGESTION = buildSuggestion(
  7,
  [buildChange(21, 0, "Original", "Revised")],
  LATER_UPDATED_AT
);

function renderedChange(id, before, after) {
  return {
    id,
    available: true,
    inline: `<div class="inline-diff"><p><del>${before}</del><ins>${after}</ins> post with <a href="/t/guide/5">a link</a>.</p></div>`,
    side_by_side: `<div class="revision-content --previous"><p><del>${before}</del> post.</p></div><div class="revision-content --current"><p><ins>${after}</ins> post with <a href="/t/guide/5">a link</a>.</p></div>`,
  };
}

// Deliberately out of order: the raw id, not the response position, owns a card.
const RENDERED_PREVIEW = {
  available: true,
  changes: [
    renderedChange(
      12,
      '<img src="/uploads/lake.png" alt="Lake">',
      '<img src="/uploads/lake-blue.png" alt="Blue lake">'
    ),
    renderedChange(11, "Original", "Updated"),
  ],
};
const OTHER_PREVIEW = {
  available: true,
  changes: [renderedChange(13, "Intro", "Introduction")],
};
const REVISED_PREVIEW = {
  available: true,
  changes: [renderedChange(21, "Original", "Revised")],
};

const CONTEXT_GAPS = [
  {
    id: "start-11",
    before_change_id: 11,
    after_change_id: null,
    raw: "Leading **context**\n\n",
    html: '<p>Leading <strong>context</strong></p><img src="/uploads/leading.png" alt="Leading">',
  },
  {
    id: "11-12",
    before_change_id: 12,
    after_change_id: 11,
    raw: "Between context\n\n",
    html: '<p>Between context</p><img src="/uploads/between.png" alt="Between">',
  },
  {
    id: "12-end",
    before_change_id: null,
    after_change_id: 12,
    raw: "Trailing context\n",
    html: '<p>Trailing context</p><img src="/uploads/trailing.png" alt="Trailing">',
  },
];

const NOT_PENDING_PREVIEW = {
  available: false,
  unavailable_reason: "not_pending",
};

const ReviewHost = <template><ModalContainer /><LiveRegions /></template>;

const VIEW_MODE_KEY = "suggested-edits-view-mode";
const viewModeStore = new KeyValueStore("discourse_suggested_edits_");
const RENDERED_PREVIEW_TIMEOUT =
  SuggestedEditsReviewModal.RENDERED_PREVIEW_TIMEOUT;

module(
  "Integration | Component | Modal | SuggestedEditsReview",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      viewModeStore.remove(VIEW_MODE_KEY);
      disableClearA11yAnnouncementsInTests();

      this.suggestions = [SUGGESTION];
      this.previewRequests = [];
      this.showResponses = {
        7: () => ({ ...SUGGESTION, rendered_preview: RENDERED_PREVIEW }),
        8: () => ({ ...OTHER_SUGGESTION, rendered_preview: OTHER_PREVIEW }),
      };

      pretender.get("/suggested-edits/suggestions", () =>
        response({ suggested_edits: this.suggestions })
      );
      pretender.get("/suggested-edits/suggestions/:id", async (request) => {
        this.previewRequests.push({
          id: request.params.id,
          ...request.queryParams,
        });
        const suggestedEdit = await this.showResponses[request.params.id]();
        if (typeof suggestedEdit === "number") {
          return response(suggestedEdit, {});
        }
        return suggestedEdit
          ? response({ suggested_edit: suggestedEdit })
          : response(500, {});
      });
    });

    hooks.afterEach(function () {
      viewModeStore.remove(VIEW_MODE_KEY);
      SuggestedEditsReviewModal.RENDERED_PREVIEW_TIMEOUT =
        RENDERED_PREVIEW_TIMEOUT;
    });

    function openModal(owner) {
      owner
        .lookup("service:modal")
        .show(SuggestedEditsReviewModal, { model: { post: { id: 1 } } });
    }

    async function showModal(owner) {
      await render(ReviewHost);
      openModal(owner);
      await settled();
    }

    test("interleaves leading, between and trailing context with stable actionable cards", async function (assert) {
      const suggestion = buildSuggestion(7, [
        ...SUGGESTION.changes,
        buildChange(14, 2, "End", "New end"),
      ]);
      const gaps = [
        ...CONTEXT_GAPS.slice(0, 2),
        {
          id: "12-14",
          before_change_id: 14,
          after_change_id: 12,
          raw: "Second interval",
          html: "<p>Second interval</p>",
        },
        { ...CONTEXT_GAPS[2], id: "14-end", after_change_id: 14 },
      ];
      this.suggestions = [suggestion];
      this.showResponses[7] = () => ({
        ...suggestion,
        rendered_preview: {
          ...RENDERED_PREVIEW,
          changes: [
            ...RENDERED_PREVIEW.changes,
            renderedChange(14, "End", "New end"),
          ],
          gaps: [...gaps].reverse(),
        },
      });
      await showModal(this.owner);
      const items = findAll(".suggested-edits-review-modal__changes > *").map(
        (element) => element.dataset.contextId ?? element.dataset.changeId
      );
      assert.deepEqual(
        items,
        ["start-11", "11", "11-12", "12", "12-14", "14", "14-end"],
        "all positions are placed by raw ids, not response order"
      );
      assert
        .dom(".suggested-edit-context__toggle")
        .exists(
          { count: 4 },
          "leading, two between and trailing controls appear once"
        );
      for (const button of findAll(".suggested-edit-context__toggle")) {
        assert
          .dom(button)
          .hasText("Expand", "no counts or extra visible prose")
          .hasAttribute(
            "aria-expanded",
            "false",
            "all context starts collapsed"
          );
      }
      assert
        .dom(".suggested-edit-context img")
        .doesNotExist("no omitted image is mounted while closed");
      assert
        .dom(".suggested-edit-change-item")
        .exists({ count: 3 }, "context adds no extra decision cards");
      await click('[data-context-id="start-11"] button');
      await click('[data-context-id="14-end"] button');
      assert
        .dom('[data-context-id="start-11"] .suggested-edit-context__side')
        .exists({ count: 2 }, "leading content is accessible on both sides");
      assert
        .dom('[data-context-id="14-end"] .suggested-edit-context__side')
        .exists({ count: 2 }, "trailing content is accessible on both sides");
    });

    test("keeps unsaved edits and decisions when gaps expand or view modes change", async function (assert) {
      this.showResponses[7] = () => ({
        ...SUGGESTION,
        rendered_preview: { ...RENDERED_PREVIEW, gaps: CONTEXT_GAPS },
      });
      await showModal(this.owner);
      await click('[data-change-id="11"] .suggested-edit-change-item__accept');
      await click('[data-change-id="12"] .suggested-edit-change-item__reject');
      await click('[data-change-id="12"] .suggested-edit-change-item__edit');
      await fillIn("textarea", "Unsaved reviewer edit");
      const editor = find("textarea");
      const card = find('[data-change-id="11"]');
      await click('[data-context-id="11-12"] button');
      await click(".inline-mode");
      assert
        .dom('[data-context-id="11-12"] button')
        .hasText("Collapse", "expanded state survives Inline");
      assert
        .dom('[data-context-id="11-12"] img')
        .exists({ count: 1 }, "inline mounts context once");
      await click(".source-mode");
      assert
        .dom('[data-context-id="11-12"] pre')
        .hasText(
          CONTEXT_GAPS[1].raw.trim(),
          "Source shows the exact interval as text"
        );
      assert
        .dom('[data-context-id="11-12"] img')
        .doesNotExist("Source never renders context images");
      assert.strictEqual(
        find("textarea"),
        editor,
        "view and context changes do not remount the editor"
      );
      assert
        .dom(editor)
        .hasValue("Unsaved reviewer edit", "unsaved editText is intact");
      assert.strictEqual(
        find('[data-change-id="11"]'),
        card,
        "card DOM identity is stable"
      );
      assert
        .dom(card)
        .hasClass(
          "suggested-edit-change-item--accepted",
          "accepted decisions survive expansion"
        );
      assert
        .dom('[data-change-id="12"]')
        .hasClass(
          "suggested-edit-change-item--rejected",
          "rejected decisions survive expansion"
        );
      await click(".side-by-side-mode");
      assert
        .dom('[data-context-id="11-12"] button')
        .hasText(
          "Collapse",
          "expanded state survives the return to rendered view"
        );
      assert.strictEqual(
        this.previewRequests.length,
        1,
        "mode and context toggles never fetch or cook fragments"
      );
    });

    test("suppresses overlapping legacy context with valid gaps and preserves it without the envelope", async function (assert) {
      const changes = SUGGESTION.changes.map((change) => ({
        ...change,
        context_before: "Previous hunk must not leak ".repeat(30),
        preview_context_before: "must not leak ",
        context_after: "Next hunk must not leak ".repeat(30),
        preview_context_after: "Next hunk ",
      }));
      const suggestion = { ...SUGGESTION, changes };
      this.suggestions = [suggestion];
      this.showResponses[7] = () => ({
        ...suggestion,
        rendered_preview: { available: true, changes: [], gaps: CONTEXT_GAPS },
      });
      await showModal(this.owner);
      assert
        .dom(
          ".suggested-edit-change-item__context, .suggested-edit-change-item__expand"
        )
        .doesNotExist(
          "fallback cards never cross a neighboring hunk when exact gaps exist"
        );
      await click(".source-mode");
      assert
        .dom(
          ".suggested-edit-change-item__context, .suggested-edit-change-item__expand"
        )
        .doesNotExist("Source has only unified exact context");
      await click('[data-context-id="start-11"] button');
      assert
        .dom('[data-context-id="start-11"] pre')
        .hasText(
          CONTEXT_GAPS[0].raw.trim(),
          "leading raw context appears only once"
        );
      this.owner.lookup("service:modal").close();
      await settled();
      this.showResponses[7] = () => ({
        ...suggestion,
        rendered_preview: { available: true, changes: [] },
      });
      openModal(this.owner);
      await settled();
      assert
        .dom(".suggested-edit-change-item__context")
        .exists(
          { count: 8 },
          "missing gap envelopes retain the legacy source context"
        );
      assert
        .dom(".suggested-edit-change-item__expand")
        .exists(
          { count: 4 },
          "legacy expansion remains available when exact gaps cannot load"
        );
    });

    test("shows raw-only context in Source without phantom empty controls and keeps mobile rendered context inline", async function (assert) {
      forceMobile();
      const gaps = [
        { ...CONTEXT_GAPS[0], raw: " \n", html: " \n" },
        { ...CONTEXT_GAPS[1], html: undefined },
        CONTEXT_GAPS[2],
      ];
      this.showResponses[7] = () => ({
        ...SUGGESTION,
        rendered_preview: { ...RENDERED_PREVIEW, gaps },
      });
      await showModal(this.owner);
      assert
        .dom(".suggested-edit-context__toggle")
        .exists(
          { count: 1 },
          "only the safe, meaningful trailing rendered gap is offered"
        );
      await click('[data-context-id="12-end"] button');
      assert
        .dom('[data-context-id="12-end"] img')
        .exists({ count: 1 }, "mobile context appears once");
      await click(".source-mode");
      assert
        .dom(".suggested-edit-context__toggle")
        .exists(
          { count: 2 },
          "the unsafe rendered interval is still available as raw source"
        );
      assert
        .dom('[data-context-id="12-end"] button')
        .hasText("Collapse", "mobile expanded state survives Source");
      await click('[data-context-id="11-12"] button');
      assert
        .dom('[data-context-id="11-12"] pre')
        .hasText(CONTEXT_GAPS[1].raw.trim(), "raw-only context is usable");
      await click(".inline-mode");
      assert
        .dom('[data-context-id="11-12"]')
        .doesNotExist("unsafe rendered context never leaks into Inline");
      await click(".source-mode");
      assert
        .dom('[data-context-id="11-12"] button')
        .hasText(
          "Collapse",
          "hidden mode-specific gaps retain their expansion state"
        );
    });

    test("retains gap expansion through retry but resets it for a revised suggestion", async function (assert) {
      let review;
      class RetriableReview extends SuggestedEditsReviewModal {
        constructor() {
          super(...arguments);
          review = this;
        }
      }
      this.showResponses[7] = () => ({
        ...SUGGESTION,
        rendered_preview: { ...RENDERED_PREVIEW, gaps: CONTEXT_GAPS },
      });
      await render(ReviewHost);
      this.owner
        .lookup("service:modal")
        .show(RetriableReview, { model: { post: { id: 1 } } });
      await settled();
      await click('[data-context-id="start-11"] button');
      await click('[data-change-id="11"] .suggested-edit-change-item__accept');
      const invalidatePreview = () => {
        review.renderedPreviews = new Map([
          [7, { available: false, failed: true, unavailableReason: "error" }],
        ]);
      };
      invalidatePreview();
      await settled();
      await click(".suggested-edit-preview__retry");
      assert
        .dom('[data-context-id="start-11"] button')
        .hasText("Collapse", "retry preserves the root-owned expansion state");
      assert
        .dom('[data-change-id="11"]')
        .hasClass(
          "suggested-edit-change-item--accepted",
          "retry preserves decisions"
        );
      invalidatePreview();
      this.showResponses[7] = () => ({
        ...SUGGESTION,
        updated_at: LATER_UPDATED_AT,
        rendered_preview: { ...RENDERED_PREVIEW, gaps: CONTEXT_GAPS },
      });
      await settled();
      await click(".suggested-edit-preview__retry");
      assert
        .dom('[data-context-id="start-11"] button')
        .hasText(
          "Expand",
          "revision resets expansion even when gap ids remain the same"
        );
      assert
        .dom(".suggested-edit-change-item--accepted")
        .doesNotExist("revision still clears obsolete decisions");
    });

    test("shows rendered text and images beside their own decisions and switches to exact source", async function (assert) {
      await showModal(this.owner);

      assert.deepEqual(
        this.previewRequests,
        [{ id: "7", include_rendered_preview: "true" }],
        "one shared opt-in request"
      );
      assert
        .dom(".side-by-side-mode")
        .hasClass("active")
        .hasAttribute("aria-current", "true")
        .hasAttribute("aria-label");
      assert.dom(".inline-mode").doesNotHaveAttribute("aria-current");
      assert.dom(".source-mode").hasAttribute("aria-label");
      const textCard = '[data-change-id="11"]';
      const imageCard = '[data-change-id="12"]';
      assert
        .dom(textCard)
        .hasAttribute("role", "group")
        .hasAttribute(
          "aria-label",
          "Change 1",
          "the first card has a concise accessible group name"
        );
      assert
        .dom(imageCard)
        .hasAttribute("role", "group")
        .hasAttribute(
          "aria-label",
          "Change 2",
          "each card has a unique group name"
        );
      assert
        .dom(`${textCard} .suggested-edit-preview__body .--current ins`)
        .hasText("Updated", "text preview matches its exact raw id");
      assert
        .dom(`${imageCard} .suggested-edit-preview__body .--current img`)
        .hasAttribute(
          "src",
          "/uploads/lake-blue.png",
          "the changed image is actually rendered in its card"
        );
      for (const card of [textCard, imageCard]) {
        for (const action of ["accept", "edit", "reject"]) {
          assert
            .dom(`${card} .suggested-edit-change-item__${action}`)
            .exists(`${action} belongs to the preview card`);
        }
      }
      assert
        .dom(".suggested-edit-preview")
        .exists(
          { count: 2 },
          "only card renderers exist after success; no empty global status wrapper"
        );
      assert
        .dom(".suggested-edits-review-modal__changes-title")
        .doesNotExist("no separate decision-list heading");
      assert
        .dom(
          ".suggested-edits-review-modal__changes > .suggested-edit-change-item"
        )
        .exists({ count: 2 }, "the existing list owns all cards");
      assert
        .dom(".suggested-edit-change-item__diff")
        .doesNotExist("no duplicate raw diff in rendered view");

      await click(".source-mode");
      assert
        .dom(".suggested-edit-preview__body")
        .doesNotExist("source uses raw hunks, not full-source previews");
      assert.dom(".source-mode").hasAttribute("aria-current", "true");
      assert
        .dom(textCard)
        .hasAttribute(
          "aria-label",
          "Change 1",
          "source cards retain accessible context"
        );
      assert.dom(".side-by-side-mode").doesNotHaveAttribute("aria-current");
      assert
        .dom(".suggested-edit-change-item__diff--side-by-side")
        .exists({ count: 2 }, "desktop source stays side by side");
      assert
        .dom(`${imageCard} .suggested-edit-change-item__diff`)
        .includesText("lake-blue.png", "exact image source is shown");

      await click(".inline-mode");
      assert
        .dom(".suggested-edit-preview__body.--inline .inline-diff")
        .exists({ count: 2 }, "both cards switch inline");
      assert
        .dom(".suggested-edit-change-item__diff--side-by-side")
        .doesNotExist();
      assert.strictEqual(
        this.previewRequests.length,
        1,
        "switching modes reuses the cache"
      );
    });

    test("reviews only three changed cards for a ten-image post", async function (assert) {
      const tenImages = Array.from(
        { length: 10 },
        (_, index) => `![Image ${index + 1}](/uploads/image-${index + 1}.png)`
      ).join("\n\n");
      const suggestion = buildSuggestion(9, [
        {
          ...buildChange(81, 0, "Heading", "Updated heading"),
          context_after: tenImages,
        },
        buildChange(94, 1, "image-2.png", "image-2-new.png"),
        buildChange(107, 2, "image-7.png", "image-7-new.png"),
      ]);
      this.suggestions = [suggestion];
      this.showResponses[9] = () => ({
        ...suggestion,
        rendered_preview: {
          available: true,
          changes: [
            renderedChange(
              107,
              '<img src="/uploads/image-7.png" alt="Image 7">',
              '<img src="/uploads/image-7-new.png" alt="New image 7">'
            ),
            renderedChange(81, "Heading", "Updated heading"),
            renderedChange(
              94,
              '<img src="/uploads/image-2.png" alt="Image 2">',
              '<img src="/uploads/image-2-new.png" alt="New image 2">'
            ),
          ],
        },
      });
      await showModal(this.owner);
      assert
        .dom(".suggested-edit-change-item")
        .exists({ count: 3 }, "only changed raw hunks become cards");
      assert
        .dom(".suggested-edit-preview__body img")
        .exists(
          { count: 4 },
          "only the two changed images and their previous versions render"
        );
      for (const id of [81, 94, 107]) {
        const card = `[data-change-id="${id}"]`;
        assert
          .dom(`${card} .suggested-edit-preview__body`)
          .exists("the card has its own preview");
        for (const action of ["accept", "edit", "reject"]) {
          assert
            .dom(`${card} .suggested-edit-change-item__${action}`)
            .exists(`${action} is in the same card`);
        }
      }
      assert
        .dom('[data-change-id="81"] .suggested-edit-preview__body')
        .includesText("Updated heading", "the text change renders too");
      assert
        .dom('[data-change-id="94"] .--current img')
        .hasAttribute(
          "src",
          "/uploads/image-2-new.png",
          "image 2 matches its exact raw hunk"
        );
      assert
        .dom('[data-change-id="107"] .--current img')
        .hasAttribute(
          "src",
          "/uploads/image-7-new.png",
          "image 7 matches its exact raw hunk"
        );
      assert
        .dom('.suggested-edit-preview img[src="/uploads/image-1.png"]')
        .doesNotExist("unchanged context images are not rendered");
      assert.strictEqual(
        this.previewRequests.length,
        1,
        "all cards share one request"
      );
    });

    test("renders available hunks while another card falls back to source", async function (assert) {
      this.showResponses[7] = () => ({
        ...SUGGESTION,
        rendered_preview: {
          available: true,
          changes: [
            RENDERED_PREVIEW.changes[0],
            { id: 11, available: false, unavailable_reason: "too_complex" },
          ],
        },
      });
      await showModal(this.owner);
      assert
        .dom('[data-change-id="12"] .suggested-edit-preview__body img')
        .exists({ count: 2 }, "the available image card is rendered");
      assert
        .dom('[data-change-id="11"] .suggested-edit-change-item__diff')
        .includesText("Updated", "only the unavailable card uses raw source");
      assert
        .dom(".suggested-edit-preview__fallback")
        .doesNotExist("a local failure is not a global error");
      await click('[data-change-id="11"] .suggested-edit-change-item__accept');
      await click('[data-change-id="12"] .suggested-edit-change-item__reject');
      assert
        .dom('[data-change-id="11"]')
        .hasClass(
          "suggested-edit-change-item--accepted",
          "fallback cards remain actionable"
        );
      assert
        .dom('[data-change-id="12"]')
        .hasClass(
          "suggested-edit-change-item--rejected",
          "rendered cards remain actionable"
        );
    });

    test("keeps unavailable, missing and visually equivalent hunks as exact source cards", async function (assert) {
      this.suggestions = [
        buildSuggestion(7, [
          ...SUGGESTION.changes,
          buildChange(99, 2, "**same**", "__same__"),
        ]),
      ];
      this.showResponses[7] = () => ({
        ...this.suggestions[0],
        rendered_preview: {
          available: true,
          changes: [
            {
              id: 99,
              available: false,
              unavailable_reason: "no_visible_change",
            },
            { id: 12, available: false, unavailable_reason: "too_complex" },
            renderedChange(999, "Wrong", "Unrelated"),
          ],
        },
      });
      await showModal(this.owner);
      assert
        .dom(".suggested-edit-change-item")
        .exists({ count: 3 }, "no raw hunk disappears");
      assert
        .dom(".suggested-edit-preview__body")
        .doesNotExist("unrelated ids never fill a missing preview");
      assert
        .dom('[data-change-id="11"] .suggested-edit-change-item__diff')
        .includesText("Updated", "missing preview uses its exact source");
      assert
        .dom('[data-change-id="12"] .suggested-edit-change-item__source-notice')
        .hasText(
          "Rendered preview unavailable. Source shown.",
          "local complexity fallback is concise"
        );
      assert
        .dom('[data-change-id="99"] .suggested-edit-change-item__source-notice')
        .hasText(
          "No visible difference. Source shown.",
          "visible equivalence is not described as no raw change"
        );
      assert
        .dom('[data-change-id="99"] .suggested-edit-change-item__diff')
        .includesText("__same__", "the raw change remains reviewable");
      assert
        .dom(".suggested-edit-preview__fallback")
        .doesNotExist("local fallback has no repeated global failure");
      assert
        .dom(".suggested-edit-preview__retry")
        .doesNotExist("individual cards do not retry independently");
      await click(".source-mode");
      assert
        .dom(".suggested-edit-change-item__source-notice")
        .doesNotExist("source mode needs no preview notices");
    });

    test("uses list order for accessible card names when raw positions are missing", async function (assert) {
      const suggestion = {
        ...SUGGESTION,
        changes: SUGGESTION.changes.map((change) => ({
          ...change,
          position: undefined,
        })),
      };
      this.suggestions = [suggestion];
      this.showResponses[7] = () => ({
        ...suggestion,
        rendered_preview: RENDERED_PREVIEW,
      });
      await showModal(this.owner);
      assert
        .dom('[data-change-id="11"]')
        .hasAttribute(
          "aria-label",
          "Change 1",
          "the first missing position falls back to list order"
        );
      assert
        .dom('[data-change-id="12"]')
        .hasAttribute(
          "aria-label",
          "Change 2",
          "fallback group names stay unique"
        );
    });

    test("opens preview links in a new tab without losing decisions", async function (assert) {
      const open = sinon.stub(window, "open");

      await showModal(this.owner);
      await click(".suggested-edit-change-item__accept");
      await click(".suggested-edit-preview__body a");

      assert.true(
        open.calledOnceWith(
          `${window.location.origin}/t/guide/5`,
          "_blank",
          "noopener,noreferrer"
        )
      );
      assert.dom(".suggested-edits-review-modal").exists();
      assert.dom(".suggested-edit-change-item--accepted").exists({ count: 1 });
    });

    test("keeps mobile views to a single column", async function (assert) {
      viewModeStore.set({ key: VIEW_MODE_KEY, value: "side-by-side" });
      forceMobile();

      await showModal(this.owner);

      assert.dom(".side-by-side-mode").doesNotExist();
      assert.dom(".inline-mode").hasAttribute("aria-current", "true");
      assert
        .dom(".suggested-edit-preview__body.--inline .inline-diff")
        .exists();
      assert
        .dom(".suggested-edit-change-item__diff--side-by-side")
        .doesNotExist();

      await click(".source-mode");

      assert
        .dom(".suggested-edit-preview__body")
        .doesNotExist("mobile source uses raw cards");
      assert
        .dom(".suggested-edit-change-item__diff")
        .exists({ count: 2 }, "both exact raw hunks remain");
      assert
        .dom(".suggested-edit-change-item__diff--side-by-side")
        .doesNotExist("mobile source stays inline");
    });

    test("partial acceptance sends exact raw ids and reviewer overrides replace stale rendered proposals", async function (assert) {
      let applied;
      pretender.put("/suggested-edits/suggestions/:id/apply", (request) => {
        applied = new URLSearchParams(request.requestBody);
        return response(204, "");
      });
      await showModal(this.owner);
      await click('[data-change-id="12"] .suggested-edit-change-item__accept');
      await click('[data-change-id="11"] .suggested-edit-change-item__reject');
      await click(".suggested-edits-review-modal__apply");
      assert.deepEqual(
        applied.getAll("accepted_change_ids[]"),
        ["12"],
        "selection uses the raw id despite reversed preview order"
      );

      await showModal(this.owner);
      await click('[data-change-id="11"] .suggested-edit-change-item__edit');
      assert
        .dom('[data-change-id="11"] .suggested-edit-preview__body')
        .doesNotExist("editing hides the submitted preview");
      await fillIn(
        ".suggested-edit-change-item__editor-textarea",
        "Reviewer text"
      );
      await click(".suggested-edit-change-item__save-edit");
      assert
        .dom('[data-change-id="11"] .suggested-edit-preview__body')
        .doesNotExist("an override never shows stale rendered text");
      assert
        .dom('[data-change-id="11"] .suggested-edit-change-item__edited-text')
        .hasText("Reviewer text", "the explicit edited source is shown");
      assert
        .dom('[data-change-id="12"] .suggested-edit-preview__body')
        .exists("other cards keep their preview");
      await click(".suggested-edits-review-modal__apply");
      assert.deepEqual(
        applied.getAll("accepted_change_ids[]"),
        ["11"],
        "only the edited raw change is accepted"
      );
      assert.strictEqual(
        applied.get("change_overrides[11]"),
        "Reviewer text",
        "the override uses that raw id"
      );
    });

    test("replaces a revised suggestion and resets its decisions", async function (assert) {
      const { promise: gate, resolve: release } = Promise.withResolvers();
      this.showResponses[7] = async () => {
        await gate;
        return { ...REVISED_SUGGESTION, rendered_preview: REVISED_PREVIEW };
      };

      await render(ReviewHost);
      openModal(this.owner);
      await waitFor(".suggested-edit-change-item__accept");

      document.querySelector(".suggested-edit-change-item__accept").click();
      await waitFor(".suggested-edit-change-item--accepted");

      release();
      await settled();

      assert.dom(".suggested-edit-change-item").exists({ count: 1 });
      assert.dom(".suggested-edit-change-item").includesText("Revised");
      assert.dom(".suggested-edit-change-item--accepted").doesNotExist();
    });

    test("keeps decisions on the selected suggestion when another one is refreshed", async function (assert) {
      const { promise: gate, resolve: release } = Promise.withResolvers();
      this.suggestions = [SUGGESTION, OTHER_SUGGESTION];
      this.showResponses[7] = async () => {
        await gate;
        return { ...REVISED_SUGGESTION, rendered_preview: REVISED_PREVIEW };
      };

      await render(ReviewHost);
      openModal(this.owner);
      await waitFor(".suggested-edits-review-modal__nav button");

      document
        .querySelectorAll(".suggested-edits-review-modal__nav button")[1]
        .click();
      await waitUntil(() =>
        document
          .querySelector(".suggested-edits-review-modal__nav-label")
          ?.textContent.includes("2 / 2")
      );
      await waitFor(".suggested-edit-preview__body");

      document.querySelector(".suggested-edit-change-item__accept").click();
      await waitFor(".suggested-edit-change-item--accepted");

      release();
      await settled();

      assert
        .dom(".suggested-edit-change-item--accepted")
        .includesText("Introduction", "the selected suggestion is untouched");
      assert
        .dom("#a11y-announcements-polite")
        .hasText(
          IDLE_ANNOUNCEMENT,
          "another suggestion's refresh is not announced"
        );

      await click(".suggested-edits-review-modal__nav button");

      assert.dom(".suggested-edit-change-item").exists({ count: 1 });
      assert.dom(".suggested-edit-change-item").includesText("Revised");
      assert.strictEqual(
        this.previewRequests.filter(({ id }) => id === "7").length,
        1,
        "the refreshed preview is reused"
      );
    });

    test("retries a preview that failed to load", async function (assert) {
      this.suggestions = [SUGGESTION, OTHER_SUGGESTION];
      let failures = 1;
      this.showResponses[7] = () =>
        failures-- > 0
          ? null
          : { ...SUGGESTION, rendered_preview: RENDERED_PREVIEW };

      await showModal(this.owner);

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("couldn't be loaded");
      assert.dom(".suggested-edit-change-item").exists({ count: 2 });
      assert
        .dom(".suggested-edit-preview__fallback")
        .exists({ count: 1 }, "one global notice for all cards");
      assert
        .dom(".suggested-edit-preview__retry")
        .exists({ count: 1 }, "one shared retry control");
      assert
        .dom(".suggested-edit-change-item .suggested-edit-preview__fallback")
        .doesNotExist("global errors are not repeated in cards");

      const [previous, next] = document.querySelectorAll(
        ".suggested-edits-review-modal__nav button"
      );
      await click(next);
      await click(previous);

      assert.dom(".suggested-edit-preview__fallback").doesNotExist();
      assert.dom(".suggested-edit-preview__body.--side-by-side").exists();
    });

    test("retries a failed preview in place, keeping focus and decisions", async function (assert) {
      const { promise: gate, resolve: release } = Promise.withResolvers();
      this.showResponses[7] = async () => {
        switch (this.previewRequests.length) {
          case 1:
            return null;
          case 2:
            await gate;
            return null;
          default:
            return { ...SUGGESTION, rendered_preview: RENDERED_PREVIEW };
        }
      };

      await showModal(this.owner);

      assert
        .dom("#a11y-announcements-polite")
        .includesText("couldn't be loaded", "the failure is announced");

      await click(".suggested-edit-change-item__accept");

      assert.dom(".suggested-edits-review-modal__nav").doesNotExist();
      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("couldn't be loaded");

      const retry = document.querySelector(".suggested-edit-preview__retry");
      retry.focus();
      retry.click();
      await waitFor(".suggested-edit-preview__retry[aria-disabled='true']");

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("couldn't be loaded", "the notice stays while retrying");
      assert.dom(".suggested-edit-preview .spinner").exists();
      assert
        .dom(".suggested-edit-preview__retry")
        .isFocused("the retry control keeps focus while loading")
        .hasText("Loading…")
        .isNotDisabled();

      release();
      await settled();

      assert.strictEqual(
        document.querySelector(".suggested-edit-preview__retry"),
        retry,
        "a failed retry keeps the same control"
      );
      assert
        .dom(retry)
        .isFocused()
        .hasText("Retry")
        .doesNotHaveAttribute("aria-disabled");

      await click(retry);

      assert.dom(".suggested-edit-preview__fallback").doesNotExist();
      assert
        .dom(".suggested-edit-preview__body.--side-by-side")
        .isFocused("focus moves to the loaded preview");
      assert
        .dom(".suggested-edit-change-item--accepted")
        .exists({ count: 1 }, "the decision survives the retries");
      assert.strictEqual(this.previewRequests.length, 3);
    });

    test("times out a hung preview and ignores its late response", async function (assert) {
      SuggestedEditsReviewModal.RENDERED_PREVIEW_TIMEOUT = 50;
      const { promise: hung, resolve: releaseHung } = Promise.withResolvers();
      this.showResponses[7] = async () => {
        if (this.previewRequests.length === 1) {
          await hung;
          return { ...REVISED_SUGGESTION, rendered_preview: REVISED_PREVIEW };
        }
        return { ...SUGGESTION, rendered_preview: RENDERED_PREVIEW };
      };

      await render(ReviewHost);
      openModal(this.owner);
      await waitFor(".suggested-edit-preview__retry");

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("couldn't be loaded");

      await click(".suggested-edit-change-item__accept");
      await click(".suggested-edit-preview__retry");

      assert.dom(".suggested-edit-preview__body.--side-by-side").exists();
      assert.dom(".suggested-edit-change-item--accepted").exists({ count: 1 });

      releaseHung();
      await settled();

      assert
        .dom(".suggested-edit-change-item")
        .exists({ count: 2 }, "the late response does not replace the record");
      assert.dom(".suggested-edit-change-item--accepted").exists({ count: 1 });
    });

    test("refreshes a status change that keeps the same timestamp", async function (assert) {
      const { promise: gate, resolve: release } = Promise.withResolvers();
      this.showResponses[7] = async () => {
        await gate;
        return {
          ...SUGGESTION,
          status: "stale",
          rendered_preview: NOT_PENDING_PREVIEW,
        };
      };

      await render(ReviewHost);
      openModal(this.owner);
      await waitFor(".suggested-edit-change-item__accept");

      document.querySelector(".suggested-edit-change-item__accept").click();
      await waitFor(".suggested-edit-change-item--accepted");
      document.querySelector(".source-mode").focus();

      release();
      await settled();

      assert
        .dom("#a11y-announcements-polite")
        .includesText("This post was edited since this suggestion was made");
      assert
        .dom(".source-mode")
        .isFocused("focus on a control that stays usable is kept");
      assert
        .dom(".suggested-edits-stale-warning .btn")
        .hasText("Discard Suggestion");
      assert.dom(".suggested-edits-review-modal__discard").isNotDisabled();
      assert
        .dom(".suggested-edits-review-modal__resolved-notice")
        .doesNotExist();
      assert.dom(".suggested-edit-change-item--accepted").doesNotExist();
      assert.dom(".suggested-edit-change-item__accept").isDisabled();
      assert.dom(".suggested-edits-review-modal__accept-all").isDisabled();
      assert.dom(".suggested-edits-review-modal__apply").isDisabled();
    });

    [
      ["applied", "has already been applied"],
      ["dismissed", "was discarded"],
      ["withdrawn", "was withdrawn by its author"],
    ].forEach(([status, notice]) => {
      test(`disables a suggestion that was ${status} after the list loaded`, async function (assert) {
        this.showResponses[7] = () => ({
          ...SUGGESTION,
          status,
          updated_at: LATER_UPDATED_AT,
          rendered_preview: NOT_PENDING_PREVIEW,
        });

        await showModal(this.owner);

        assert
          .dom(".suggested-edits-review-modal__resolved-notice")
          .includesText(notice);
        assert.dom(".suggested-edits-stale-warning").doesNotExist();
        assert
          .dom(".suggested-edit-preview__fallback")
          .includesText("no longer pending");
        assert.dom(".suggested-edit-preview__retry").doesNotExist();
        assert.dom(".suggested-edit-change-item__accept").isDisabled();
        assert.dom(".suggested-edit-change-item__edit").isDisabled();
        assert.dom(".suggested-edit-change-item__reject").isDisabled();
        assert.dom(".suggested-edits-review-modal__accept-all").isDisabled();
        assert.dom(".suggested-edits-review-modal__apply").isDisabled();
        assert.dom(".suggested-edits-review-modal__discard").isDisabled();
      });
    });

    test("announces a background resolution and moves lost focus to its notice", async function (assert) {
      const { promise: gate, resolve: release } = Promise.withResolvers();
      this.showResponses[7] = async () => {
        await gate;
        return {
          ...SUGGESTION,
          status: "withdrawn",
          rendered_preview: NOT_PENDING_PREVIEW,
        };
      };

      await render(ReviewHost);
      openModal(this.owner);
      await waitFor(".suggested-edit-change-item__accept");
      document.querySelector(".suggested-edit-change-item__accept").focus();

      release();
      await settled();

      assert
        .dom("#a11y-announcements-polite")
        .includesText("was withdrawn by its author");
      assert
        .dom(".suggested-edits-review-modal__resolved-notice")
        .isFocused("focus moves from the disabled control to the notice");
    });

    test("only allows discarding suggestions on posts that can't be edited this way", async function (assert) {
      this.showResponses[7] = () => ({
        ...SUGGESTION,
        rendered_preview: {
          available: false,
          unavailable_reason: "unsupported_post",
        },
      });

      await showModal(this.owner);

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("can only be discarded");
      assert
        .dom("#a11y-announcements-polite")
        .includesText("can only be discarded");
      assert.dom(".suggested-edit-change-item__accept").isDisabled();
      assert.dom(".suggested-edit-change-item__edit").isDisabled();
      assert.dom(".suggested-edit-change-item__reject").isDisabled();
      assert.dom(".suggested-edits-review-modal__accept-all").isDisabled();
      assert.dom(".suggested-edits-review-modal__apply").isDisabled();
      assert.dom(".suggested-edits-review-modal__discard").isNotDisabled();
    });

    test("asks the reviewer to wait when previews are rate limited", async function (assert) {
      this.showResponses[7] = () => 429;

      await showModal(this.owner);

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("Wait a minute before you retry");
      assert
        .dom("#a11y-announcements-polite")
        .includesText("Wait a minute before you retry");
      assert.dom(".suggested-edit-preview__retry").isNotDisabled();
      assert.dom(".suggested-edit-change-item__accept").isNotDisabled();
    });

    test("discards the suggestion it was asked to while the request is pending", async function (assert) {
      const { promise: gate, resolve: release } = Promise.withResolvers();
      const dismissed = [];
      pretender.put(
        "/suggested-edits/suggestions/:id/dismiss",
        async (request) => {
          dismissed.push(request.params.id);
          await gate;
          return response(204, "");
        }
      );
      this.suggestions = [SUGGESTION, OTHER_SUGGESTION];

      await showModal(this.owner);
      await click(".suggested-edit-change-item__accept");

      document.querySelector(".suggested-edits-review-modal__discard").click();
      await waitFor(".suggested-edits-review-modal__discard[disabled]");

      const next = document.querySelectorAll(
        ".suggested-edits-review-modal__nav button"
      )[1];
      assert.dom(next).isDisabled("navigation waits for the discard");
      assert.dom(".suggested-edits-review-modal__apply").isDisabled();
      assert.dom(".suggested-edits-review-modal__accept-all").isDisabled();
      assert.dom(".suggested-edit-change-item__edit").isDisabled();
      assert.dom(".suggested-edit-change-item__reject").isDisabled();
      assert.dom(".suggested-edit-change-item--accepted").exists({ count: 1 });

      next.click();
      document.querySelector(".suggested-edits-review-modal__discard").click();
      release();
      await settled();

      assert.deepEqual(
        dismissed,
        ["7"],
        "the selected suggestion is discarded once"
      );
      assert.dom(".suggested-edits-review-modal__nav").doesNotExist();
      assert.dom(".suggested-edit-change-item").exists({ count: 1 });
      assert
        .dom(".suggested-edit-change-item")
        .includesText("Introduction", "the other suggestion remains");
      assert.dom(".suggested-edits-review-modal__discard").isNotDisabled();
    });

    test("ignores a late preview after the modal is closed", async function (assert) {
      const { promise: gate, resolve: release } = Promise.withResolvers();
      this.showResponses[7] = async () => {
        await gate;
        return { ...REVISED_SUGGESTION, rendered_preview: REVISED_PREVIEW };
      };
      await render(ReviewHost);
      openModal(this.owner);
      await waitFor(".suggested-edit-change-item__accept");
      const modal = this.owner.lookup("service:modal");
      modal.close();
      await waitUntil(
        () => !document.querySelector(".suggested-edits-review-modal")
      );
      release();
      await settled();
      assert
        .dom(".suggested-edits-review-modal")
        .doesNotExist("a late result never reopens the review");
      assert
        .dom("#a11y-announcements-polite")
        .hasText(
          IDLE_ANNOUNCEMENT,
          "closed reviews do not announce late refreshes"
        );
      assert.strictEqual(
        this.previewRequests.length,
        1,
        "closing does not trigger another request"
      );
    });

    test("only notifies when the review is closed during a discard", async function (assert) {
      const { promise: gate, resolve: release } = Promise.withResolvers();
      pretender.put("/suggested-edits/suggestions/:id/dismiss", async () => {
        await gate;
        return response(204, "");
      });
      this.suggestions = [SUGGESTION, OTHER_SUGGESTION];
      const onSuccess = sinon.spy();
      const modal = this.owner.lookup("service:modal");
      await render(ReviewHost);
      modal.show(SuggestedEditsReviewModal, {
        model: { post: { id: 1 }, onSuccess },
      });
      await settled();

      document.querySelector(".suggested-edits-review-modal__discard").click();
      await waitFor(".suggested-edits-review-modal__discard[disabled]");
      modal.close();
      await waitUntil(
        () => !document.querySelector(".suggested-edits-review-modal")
      );
      const close = sinon.spy(modal, "close");

      release();
      await settled();

      assert.true(onSuccess.calledOnce, "the post is notified once");
      assert.true(close.notCalled, "the review isn't closed again");
      assert.strictEqual(
        this.previewRequests.length,
        1,
        "no preview loads after closing"
      );
      assert.dom(".suggested-edits-review-modal").doesNotExist();
    });

    test("does not keep an edit that matches the suggested text", async function (assert) {
      let applied;
      pretender.put("/suggested-edits/suggestions/:id/apply", (request) => {
        applied = new URLSearchParams(request.requestBody);
        return response(204, "");
      });

      await showModal(this.owner);
      await click(".suggested-edits-review-modal__accept-all");
      await click(".suggested-edit-change-item__edit");
      await click(".suggested-edit-change-item__save-edit");

      assert
        .dom('[data-change-id="11"] .suggested-edit-preview__body')
        .exists("an unchanged edit restores its preview");
      assert.dom(".suggested-edit-change-item__edited-text").doesNotExist();

      await click(".suggested-edits-review-modal__apply");

      assert.deepEqual(applied.getAll("accepted_change_ids[]"), ["11", "12"]);
      assert.false(
        [...applied.keys()].some((key) => key.startsWith("change_overrides")),
        "no override is sent"
      );
    });

    test("falls back to the source changes when no preview is available", async function (assert) {
      this.showResponses[7] = () => ({
        ...SUGGESTION,
        rendered_preview: {
          available: false,
          unavailable_reason: "post_changed",
        },
      });

      await showModal(this.owner);

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("Review the source changes below");
      assert.dom(".suggested-edit-preview__body").doesNotExist();
      assert.dom(".suggested-edit-change-item__accept").exists({ count: 2 });
    });
  }
);

module(
  "Integration | Component | SuggestedEditsStaleWarning",
  function (hooks) {
    setupRenderingTest(hooks);

    test("can disable its discard action", async function (assert) {
      await render(
        <template><SuggestedEditsStaleWarning @disabled={{true}} /></template>
      );

      assert
        .dom(".suggested-edits-stale-warning .btn")
        .hasText("Discard Suggestion")
        .isDisabled();
    });
  }
);
