import { tracked } from "@glimmer/tracking";
import {
  click,
  find,
  focus,
  render,
  settled,
  triggerEvent,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import SuggestedEditContext from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edit-context";
import sanitizeRenderedPreview from "discourse/plugins/discourse-suggested-edits/discourse/lib/sanitize-rendered-preview";

const GAP = {
  id: "start-11",
  before_change_id: 11,
  after_change_id: null,
  raw: 'Before **the change**\n<img src="raw-only.png">',
  html: '<p>Before <strong>the change</strong></p><img src="/uploads/context.png" alt="Context">',
};

module("Integration | Component | SuggestedEditContext", function (hooks) {
  setupRenderingTest(hooks);

  test("mounts context only while expanded and keeps one accessible toggle", async function (assert) {
    const expanded = tracked(false);
    const toggle = () => (expanded.value = !expanded.value);
    await render(
      <template>
        <SuggestedEditContext
          @gap={{GAP}}
          @expanded={{expanded.value}}
          @onToggle={{toggle}}
          @viewMode="side-by-side"
        />
      </template>
    );
    const button = find("button");
    const contentId = button.getAttribute("aria-controls");
    assert
      .dom(button)
      .hasText("Expand", "only the chosen label is visible")
      .hasAttribute("aria-expanded", "false", "initially collapsed");
    assert
      .dom(".suggested-edit-context img")
      .doesNotExist("collapsed gaps mount no image elements");
    assert.dom(`#${contentId}`).isNotVisible("the controlled body is hidden");
    await click(button);
    assert
      .dom(button)
      .hasText("Collapse", "the open label has no extra metadata")
      .hasAttribute("aria-expanded", "true", "announces expansion")
      .hasAttribute("aria-controls", contentId, "the controlled id is stable");
    assert
      .dom(".suggested-edit-context img")
      .exists({ count: 2 }, "the unchanged image appears on both sides");
    assert
      .dom(".suggested-edit-context__side:first-child")
      .hasText("Before the change", "previous side uses base content");
    assert.strictEqual(
      find(".suggested-edit-context__side:first-child").innerHTML,
      find(".suggested-edit-context__side:last-child").innerHTML,
      "both columns show the identical neutral base"
    );
    assert
      .dom(
        ".suggested-edit-change-item__actions, .suggested-edit-context ins, .suggested-edit-context del"
      )
      .doesNotExist("context has no decisions or diff markup");
    assert
      .dom(".suggested-edit-context button")
      .exists({ count: 1 }, "there is only one control for both columns");
    await click(button);
    assert
      .dom(".suggested-edit-context img")
      .doesNotExist("collapse unmounts all context images");
    assert.strictEqual(
      find("button"),
      button,
      "the existing control survives collapse"
    );
  });

  test("uses inline context once and exact escaped source without cooking fragments", async function (assert) {
    const mode = tracked("inline");
    await render(
      <template>
        <SuggestedEditContext
          @gap={{GAP}}
          @expanded={{true}}
          @viewMode={{mode.value}}
        />
      </template>
    );
    assert
      .dom(".suggested-edit-context img")
      .exists({ count: 1 }, "inline has one base image");
    mode.value = "source";
    await settled();
    assert
      .dom(".suggested-edit-context pre")
      .hasText(GAP.raw, "Source preserves raw Markdown and HTML as text");
    assert
      .dom(".suggested-edit-context img")
      .doesNotExist("source is never interpreted as HTML");
  });

  test("omits unsafe rendered or whitespace-only gaps while retaining raw context in Source", async function (assert) {
    const gap = { ...GAP, html: null };
    const empty = { ...GAP, id: "empty", raw: " \n ", html: " \n " };
    const mode = tracked("inline");
    await render(
      <template>
        <SuggestedEditContext
          @gap={{gap}}
          @expanded={{true}}
          @viewMode={{mode.value}}
        />
        <SuggestedEditContext
          @gap={{empty}}
          @expanded={{true}}
          @viewMode={{mode.value}}
        />
      </template>
    );
    assert
      .dom(".suggested-edit-context")
      .doesNotExist("there are no phantom rendered controls");
    mode.value = "source";
    await settled();
    assert
      .dom(".suggested-edit-context button")
      .exists(
        { count: 1 },
        "only meaningful raw context gets a Source control"
      );
    assert
      .dom("pre")
      .hasText(GAP.raw, "the source-only interval remains accessible");
  });

  test("sanitizes context and keeps external links away from the review", async function (assert) {
    const preview = await sanitizeRenderedPreview({
      available: true,
      changes: [],
      gaps: [
        {
          ...GAP,
          html: '<p><a href="https://example.com/guide">Guide</a><a href="javascript:alert(1)">Unsafe</a></p><img src="/uploads/context.png" onerror="alert(1)"><iframe src="https://example.com"></iframe><script>alert(1)</script>',
        },
      ],
    });
    const open = sinon.stub(window, "open");
    const gap = preview.gaps[0];
    await render(
      <template>
        <SuggestedEditContext
          @gap={{gap}}
          @expanded={{true}}
          @viewMode="inline"
        />
      </template>
    );
    assert
      .dom(
        ".suggested-edit-context iframe, .suggested-edit-context script, .suggested-edit-context [onerror]"
      )
      .doesNotExist("unsafe context is stripped");
    assert
      .dom('.suggested-edit-context a[href^="javascript:"]')
      .doesNotExist("unsafe link schemes are stripped");
    await click('.suggested-edit-context a[href^="https:"]');
    assert.true(
      open.calledOnceWith(
        "https://example.com/guide",
        "_blank",
        "noopener,noreferrer"
      ),
      "safe links open without replacing the review"
    );
  });

  test("opens context below a top-edge toggle without anchoring the following card", async function (assert) {
    const expanded = tracked(false);
    const toggle = () => (expanded.value = !expanded.value);
    const gap = {
      ...GAP,
      html: '<p>Newly revealed context</p><div style="height: 1400px"></div>',
    };
    await render(
      <template>
        <div class="suggested-edits-review-modal">
          <div class="d-modal__body" style="height: 400px; overflow: auto;">
            <div class="previous-card" style="height: 800px">Previous change</div>
            <SuggestedEditContext
              @gap={{gap}}
              @expanded={{expanded.value}}
              @onToggle={{toggle}}
              @viewMode="inline"
            />
            <div class="next-card" style="height: 1800px">Next change</div>
          </div>
        </div>
      </template>
    );
    const modal = find(".d-modal__body");
    const button = find(".suggested-edit-context__toggle");
    const row = find(".suggested-edit-context__toggle-row");
    const bounds = modal.getBoundingClientRect();
    const scale = bounds.height / modal.offsetHeight || 1;
    const contentTop =
      bounds.top + parseFloat(getComputedStyle(modal).paddingTop) * scale;
    modal.scrollTop += (row.getBoundingClientRect().top - contentTop) / scale;
    await focus(button);
    await new Promise(requestAnimationFrame);
    await new Promise(requestAnimationFrame);

    const scrollBefore = modal.scrollTop;
    assert.true(
      find(".previous-card").getBoundingClientRect().bottom <= contentTop + 1,
      "the previous card is above the content viewport"
    );
    assert.true(
      find(".next-card").getBoundingClientRect().top <
        modal.getBoundingClientRect().bottom,
      "the following card is initially visible and could become a native anchor"
    );
    await click(button);
    await new Promise(requestAnimationFrame);
    await new Promise(requestAnimationFrame);

    assert.strictEqual(
      modal.scrollTop,
      scrollBefore,
      "expansion does not jump to keep the following card anchored"
    );
    assert.true(
      find(".suggested-edit-context__body").getBoundingClientRect().top >=
        button.getBoundingClientRect().bottom,
      "new context starts below the toggle, not above the viewport"
    );
    assert.dom(button).hasText("Collapse", "the existing labels are unchanged");
  });

  test("anchors a sticky collapse row in the modal and preserves its button focus", async function (assert) {
    const expanded = tracked(true);
    const toggle = () => (expanded.value = !expanded.value);
    const gap = {
      ...GAP,
      html: '<p>Start</p><div style="height: 1800px"></div><p>End</p>',
    };
    await render(
      <template>
        <div class="d-modal__body" style="height: 400px; overflow: auto;">
          <div style="height: 800px"></div>
          <SuggestedEditContext
            @gap={{gap}}
            @expanded={{expanded.value}}
            @onToggle={{toggle}}
            @viewMode="inline"
          />
          <div style="height: 1800px"></div>
        </div>
      </template>
    );
    const modal = find(".d-modal__body");
    const button = find(".suggested-edit-context__toggle");
    modal.scrollTop = 1200;
    await focus(button);
    const top = button.getBoundingClientRect().top;
    const scrollBefore = modal.scrollTop;
    const background = document.documentElement.scrollTop;
    assert.strictEqual(
      getComputedStyle(find(".suggested-edit-context__toggle-row")).position,
      "sticky",
      "Collapse remains reachable inside long context"
    );
    await click(button);
    assert
      .dom(button)
      .isFocused("focus remains on the existing collapse button")
      .hasText("Expand", "the same button is now collapsed");
    assert.true(
      Math.abs(button.getBoundingClientRect().top - top) < 1,
      "the clicked row stays at its viewport location"
    );
    assert.true(
      modal.scrollTop < scrollBefore,
      "the modal offset is explicitly corrected after collapse"
    );
    assert.strictEqual(
      document.documentElement.scrollTop,
      background,
      "the background document never scrolls"
    );
  });

  test("keeps context fragments on their own column and interval", async function (assert) {
    const gap = {
      ...GAP,
      html: '<a href="#fn1">Note</a><div style="height: 600px"></div><p id="fn1">Own footnote</p><div style="height: 800px"></div>',
    };
    await render(
      <template>
        <div id="fn1">Background footnote</div>
        <div class="d-modal__body" style="height: 400px; overflow: auto;">
          <SuggestedEditContext
            class="first-gap"
            @gap={{gap}}
            @expanded={{true}}
            @viewMode="side-by-side"
          />
          <SuggestedEditContext
            class="second-gap"
            @gap={{gap}}
            @expanded={{true}}
            @viewMode="side-by-side"
          />
        </div>
      </template>
    );
    const modal = find(".d-modal__body");
    await triggerEvent(
      ".second-gap .suggested-edit-context__side:last-child a",
      "click"
    );
    const target = find(
      ".second-gap .suggested-edit-context__side:last-child #fn1"
    );
    assert.true(
      Math.abs(
        target.getBoundingClientRect().top - modal.getBoundingClientRect().top
      ) < 1,
      "only the clicked context column supplies the fragment target"
    );
  });
});
