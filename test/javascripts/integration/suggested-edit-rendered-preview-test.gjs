import { click, find, focus, render, triggerEvent } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { sanitizeAsync } from "discourse/lib/text";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import SuggestedEditRenderedPreview from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edit-rendered-preview";
import sanitizeRenderedPreview from "discourse/plugins/discourse-suggested-edits/discourse/lib/sanitize-rendered-preview";

const PREVIEW = {
  available: true,
  unavailableReason: null,
  inline:
    '<div class="inline-diff"><p><del>Original</del><ins>Updated</ins> post. <a href="https://example.com/guide">Guide</a> <a href="mailto:team@example.com">Email</a></p></div>',
  sideBySide:
    '<div class="revision-content --previous"><p><del>Original</del> post.</p></div><div class="revision-content --current"><p><ins>Updated</ins> post.</p></div>',
};

function spacer(height) {
  return `<div style="height: ${height}px"></div>`;
}

const FRAGMENT_PREVIEW = {
  ...PREVIEW,
  inline: `<div class="inline-diff"><p>Text<sup class="footnote-ref"><a class="unchanged-ref" href="#fn1">[1]</a></sup> <del><a class="deleted-ref" href="#fn1">[1]</a></del></p>${spacer(600)}<ol class="footnotes-list"><li id="fn1" class="footnote-item diff-del">Old note${spacer(300)}</li><li id="fn1" class="footnote-item diff-ins">New note</li></ol>${spacer(3000)}</div>`,
  sideBySide: `<div class="revision-content --previous"><p>Old<sup class="footnote-ref"><a href="#fn1">[1]</a></sup> <a href="#missing">Gone</a></p>${spacer(1200)}<ol class="footnotes-list"><li id="fn1" class="footnote-item">Old note</li></ol>${spacer(3000)}</div><div class="revision-content --current"><p>New<sup class="footnote-ref"><a href="#fn1">[1]</a></sup> <a href="#caf%C3%A9">Café</a> <a href="#100%">Full</a></p>${spacer(300)}<h2><a name="café" class="anchor" href="#caf%C3%A9"></a>Café</h2>${spacer(300)}<p class="invalid-target" id="100%">Full</p>${spacer(300)}<ol class="footnotes-list"><li id="fn1" class="footnote-item">New note</li></ol>${spacer(3000)}</div>`,
};

function isAtModalTop(selector) {
  const body = find(".d-modal__body");
  const target = document.querySelector(selector);
  return (
    Math.abs(
      target.getBoundingClientRect().top - body.getBoundingClientRect().top
    ) < 1
  );
}

module(
  "Integration | Component | SuggestedEditRenderedPreview",
  function (hooks) {
    setupRenderingTest(hooks);

    test("shows the comparison without introductory copy or column labels", async function (assert) {
      await render(
        <template>
          <SuggestedEditRenderedPreview
            @preview={{PREVIEW}}
            @viewMode="side-by-side"
          />
        </template>
      );

      assert
        .dom(".suggested-edit-preview__header")
        .doesNotExist("the preview has no introductory heading or description");
      assert
        .dom(".suggested-edit-preview__column-label")
        .doesNotExist("side-by-side content has no redundant column labels");
      assert
        .dom(".suggested-edit-preview__body.--side-by-side.cooked")
        .exists();
      assert
        .dom(".suggested-edit-preview__body .revision-content.--current ins")
        .hasText("Updated");
      assert.dom(".suggested-edit-preview__fallback").doesNotExist();
    });

    test("renders inline without an empty global preview wrapper", async function (assert) {
      const envelope = { available: true, changes: new Map() };
      await render(
        <template>
          <SuggestedEditRenderedPreview
            @preview={{envelope}}
            @viewMode="inline"
          />
          <SuggestedEditRenderedPreview
            @preview={{PREVIEW}}
            @viewMode="inline"
          />
        </template>
      );

      assert
        .dom(".suggested-edit-preview")
        .exists({ count: 1 }, "only the hunk renderer has a wrapper");
      assert
        .dom(".suggested-edit-preview__body.--inline .inline-diff")
        .exists("renders the inline change");
    });

    test("renders side by side as inline when columns do not fit", async function (assert) {
      await render(
        <template>
          <SuggestedEditRenderedPreview
            @preview={{PREVIEW}}
            @stacked={{true}}
            @viewMode="side-by-side"
          />
        </template>
      );

      assert.dom(".suggested-edit-preview__body.--inline").exists();
      assert.dom(".suggested-edit-preview__columns").doesNotExist();
    });

    test("opens http links in a new tab and never navigates in place", async function (assert) {
      const open = sinon.stub(window, "open");
      let defaultPrevented;
      const recordDefault = (event) =>
        (defaultPrevented = event.defaultPrevented);
      document.addEventListener("click", recordDefault);

      try {
        await render(
          <template>
            <SuggestedEditRenderedPreview
              @preview={{PREVIEW}}
              @viewMode="inline"
            />
          </template>
        );

        await click(".suggested-edit-preview__body a[href^='https']");

        assert.true(defaultPrevented);
        assert.true(
          open.calledOnceWith(
            "https://example.com/guide",
            "_blank",
            "noopener,noreferrer"
          )
        );

        await click(".suggested-edit-preview__body a[href^='mailto']");

        assert.true(defaultPrevented);
        assert.true(open.calledOnce, "other schemes are not opened");
      } finally {
        document.removeEventListener("click", recordDefault);
      }
    });

    test("scrolls fragment links to the target on the clicked link's own side", async function (assert) {
      const open = sinon.stub(window, "open");
      const scrollIntoView = sinon.spy(Element.prototype, "scrollIntoView");
      const container = document.getElementById("ember-testing-container");

      await render(
        <template>
          <div id="fn1">Footnote of the post behind the modal</div>
          <div class="d-modal__body" style="height: 400px; overflow: auto;">
            <div class="first-card"><SuggestedEditRenderedPreview
                @preview={{FRAGMENT_PREVIEW}}
                @viewMode="side-by-side"
              /></div>
            <div class="second-card"><SuggestedEditRenderedPreview
                @preview={{FRAGMENT_PREVIEW}}
                @viewMode="side-by-side"
              /></div>
          </div>
        </template>
      );
      const containerScroll = container.scrollTop;

      await triggerEvent(
        ".second-card .revision-content.--current a[href='#fn1']",
        "click"
      );

      assert.true(
        isAtModalTop(".second-card .revision-content.--current #fn1"),
        "scrolls to the footnote on the suggested side"
      );
      assert.false(
        isAtModalTop(".second-card .revision-content.--previous #fn1")
      );

      await triggerEvent(
        ".second-card .revision-content.--previous a[href='#fn1']",
        "click"
      );

      assert.true(
        isAtModalTop(".second-card .revision-content.--previous #fn1"),
        "scrolls to the footnote on the current post side"
      );

      const body = find(".d-modal__body");
      const bodyScroll = body.scrollTop;
      await triggerEvent(
        ".second-card .revision-content.--previous a[href='#missing']",
        "click"
      );

      assert.strictEqual(
        body.scrollTop,
        bodyScroll,
        "missing targets are ignored"
      );

      await triggerEvent(
        ".second-card .revision-content.--current p a[href='#caf%C3%A9']",
        "click"
      );

      assert.true(
        isAtModalTop(".second-card .revision-content.--current a.anchor"),
        "encoded fragments are decoded"
      );

      await triggerEvent(
        ".second-card .revision-content.--current a[href='#100%']",
        "click"
      );

      assert.true(
        isAtModalTop(
          ".second-card .revision-content.--current .invalid-target"
        ),
        "invalid encodings are matched as written"
      );
      assert.strictEqual(
        container.scrollTop,
        containerScroll,
        "the background container does not scroll"
      );
      assert.true(scrollIntoView.notCalled);
      assert.true(open.notCalled, "fragments never open another tab");
    });

    test("scrolls inline fragment links to the version matching the link", async function (assert) {
      await render(
        <template>
          <div class="d-modal__body" style="height: 400px; overflow: auto;">
            <SuggestedEditRenderedPreview
              @preview={{FRAGMENT_PREVIEW}}
              @viewMode="inline"
            />
          </div>
        </template>
      );

      await triggerEvent(".unchanged-ref", "click");

      assert.true(
        isAtModalTop("li.diff-ins"),
        "an unchanged link goes to the current footnote"
      );

      await triggerEvent(".deleted-ref", "click");

      assert.true(
        isAtModalTop("li.diff-del"),
        "a deleted link goes to the deleted footnote"
      );
    });

    test("retains programmatic focus without an extra landmark, tab stop or scroll cap", async function (assert) {
      const preview = {
        ...PREVIEW,
        inline: `<div class="inline-diff">${"<p>Long paragraph</p>".repeat(200)}</div>`,
      };

      await render(
        <template>
          <SuggestedEditRenderedPreview
            @preview={{preview}}
            @viewMode="inline"
          />
        </template>
      );

      const body = document.querySelector(".suggested-edit-preview__body");
      assert.strictEqual(
        getComputedStyle(body).maxHeight,
        "none",
        "cards have no height cap"
      );
      assert.notStrictEqual(
        getComputedStyle(body).overflowY,
        "auto",
        "the modal owns scrolling, not individual cards"
      );
      assert
        .dom(body)
        .doesNotHaveAttribute("role", "no repeated region landmark")
        .hasAttribute("tabindex", "-1", "not an extra sequential tab stop")
        .doesNotHaveAttribute(
          "aria-label",
          "the containing card provides context"
        );

      await focus(body);

      assert.dom(body).isFocused();
    });

    test("offers to retry a preview that failed to load", async function (assert) {
      const retry = sinon.spy();
      const failed = {
        available: false,
        failed: true,
        unavailableReason: "error",
      };
      const changed = { available: false, unavailableReason: "post_changed" };

      await render(
        <template>
          <SuggestedEditRenderedPreview
            @onRetry={{retry}}
            @preview={{failed}}
            @viewMode="inline"
          />
        </template>
      );

      await click(".suggested-edit-preview__retry");

      assert.true(retry.calledOnce);

      await render(
        <template>
          <SuggestedEditRenderedPreview
            @loading={{true}}
            @onRetry={{retry}}
            @preview={{failed}}
            @viewMode="inline"
          />
        </template>
      );

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("couldn't be loaded", "the notice stays while loading");
      assert.dom(".suggested-edit-preview .spinner").exists();
      assert
        .dom(".suggested-edit-preview__retry")
        .hasAttribute("aria-disabled", "true")
        .hasText("Loading…")
        .isNotDisabled("disabling the focused control would drop focus");

      await click(".suggested-edit-preview__retry");

      assert.true(retry.calledOnce, "a loading retry can't be repeated");

      await render(
        <template>
          <SuggestedEditRenderedPreview
            @onRetry={{retry}}
            @preview={{changed}}
            @viewMode="inline"
          />
        </template>
      );

      assert
        .dom(".suggested-edit-preview__retry")
        .doesNotExist("an unavailable preview can't be retried");
    });

    test("explains when the suggestion is no longer pending", async function (assert) {
      const preview = { available: false, unavailableReason: "not_pending" };

      await render(
        <template>
          <SuggestedEditRenderedPreview
            @preview={{preview}}
            @viewMode="inline"
          />
        </template>
      );

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("this suggestion is no longer pending");
      assert.dom(".suggested-edit-preview__body").doesNotExist();
    });

    test("explains why the preview is unavailable", async function (assert) {
      const self = new (class {
        preview = { available: false, unavailableReason: "post_changed" };
      })();

      await render(
        <template>
          <SuggestedEditRenderedPreview
            @preview={{self.preview}}
            @viewMode="side-by-side"
          />
        </template>
      );

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("the post changed after this suggestion was made");
      assert.dom(".suggested-edit-preview__body").doesNotExist();

      self.preview = {
        available: false,
        unavailableReason: "unsupported_post",
      };
      await render(
        <template>
          <SuggestedEditRenderedPreview
            @preview={{self.preview}}
            @viewMode="side-by-side"
          />
        </template>
      );

      assert
        .dom(".suggested-edit-preview__fallback")
        .includesText("posts in this format");
    });

    test("shows a spinner while loading", async function (assert) {
      await render(
        <template>
          <SuggestedEditRenderedPreview @loading={{true}} @viewMode="inline" />
        </template>
      );

      assert.dom(".suggested-edit-preview .spinner").exists();
      assert.dom(".suggested-edit-preview__body").doesNotExist();
    });
  }
);

module("Integration | Lib | sanitize-rendered-preview", function (hooks) {
  setupRenderingTest(hooks);

  test("keeps diff markup and drops unsafe content", async function (assert) {
    this.siteSettings.allowed_iframes = "https://www.google.com/maps/embed?";
    const iframe =
      '<iframe src="https://www.google.com/maps/embed?pb=1"></iframe>';

    assert.true(
      (await sanitizeAsync(iframe)).includes("<iframe"),
      "the site allows this embed elsewhere"
    );

    const sanitized = await sanitizeRenderedPreview({
      available: true,
      changes: [
        {
          id: 42,
          available: true,
          inline: `<div class="inline-diff"><p class="diff-ins">Hi<script>alert(1)</script></p><img class="diff-del" src="/uploads/lake.png" onerror="alert(1)">${iframe}<div class="suggested-edit-preview__gap" aria-hidden="true">…</div></div>`,
          side_by_side:
            '<div class="revision-content --previous"><a href="javascript:alert(1)">link</a></div><div class="revision-content --current"></div>',
        },
        { id: 7, available: false, unavailable_reason: "too_complex" },
      ],
    });

    assert.true(sanitized.available);
    const change = sanitized.changes.get(42);
    assert.deepEqual(
      sanitized.changes.get(7),
      { available: false, unavailableReason: "too_complex" },
      "keeps unavailable raw ids"
    );
    assert.true(change.inline.includes('class="diff-ins"'));
    assert.true(change.inline.includes('class="diff-del"'));
    assert.true(change.inline.includes('src="/uploads/lake.png"'));
    assert.false(change.inline.includes("<script"));
    assert.false(change.inline.includes("onerror"));
    assert.false(change.inline.includes("<iframe"));
    const gap = new DOMParser()
      .parseFromString(change.inline, "text/html")
      .querySelector(".suggested-edit-preview__gap");
    assert
      .dom(gap)
      .hasAttribute(
        "aria-hidden",
        "true",
        "gap markers stay decorative after sanitization"
      )
      .hasText("…", "preserves the separator");
    assert.true(change.sideBySide.includes("revision-content --previous"));
    // eslint-disable-next-line no-script-url
    assert.false(change.sideBySide.includes("javascript:"));
    assert.strictEqual(
      change.source,
      undefined,
      "no full-source preview is retained"
    );
  });

  test("reports unavailable previews", async function (assert) {
    assert.deepEqual(
      await sanitizeRenderedPreview({
        available: false,
        unavailable_reason: "post_changed",
      }),
      { available: false, unavailableReason: "post_changed" }
    );
    assert.deepEqual(await sanitizeRenderedPreview(undefined), {
      available: false,
      unavailableReason: "error",
    });
  });
});
