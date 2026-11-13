import { sanitizeAsync } from "discourse/lib/text";

// Mirrors the post history modal so diff classes and oneboxes survive, while
// embeds are always dropped from previews.
function sanitizeOptions() {
  return {
    features: { editHistory: true, historyOneboxes: true, previewGaps: true },
    allowListed: {
      editHistory: { custom: (tag, attr) => attr === "class" },
      historyOneboxes: ["header", "article", "div[style]"],
      previewGaps: ["div[aria-hidden=true]"],
    },
    allowedIframes: [],
  };
}

async function sanitizeHtml(html) {
  return html ? await sanitizeAsync(html, sanitizeOptions()) : null;
}

export default async function sanitizeRenderedPreview(preview) {
  if (!preview?.available) {
    return {
      available: false,
      unavailableReason: preview?.unavailable_reason ?? "error",
    };
  }

  const changes = await Promise.all(
    (preview.changes || []).map(async (change) => {
      if (!change.available) {
        return [
          change.id,
          {
            available: false,
            unavailableReason: change.unavailable_reason,
          },
        ];
      }

      const [inline, sideBySide] = await Promise.all([
        sanitizeHtml(change.inline),
        sanitizeHtml(change.side_by_side),
      ]);
      return [change.id, { available: true, inline, sideBySide }];
    })
  );

  const gaps = Array.isArray(preview.gaps)
    ? await Promise.all(
        preview.gaps.map(async (gap) => ({
          id: gap.id,
          before_change_id: gap.before_change_id,
          after_change_id: gap.after_change_id,
          raw: gap.raw,
          html: await sanitizeHtml(gap.html),
        }))
      )
    : null;

  return { available: true, changes: new Map(changes), gaps };
}
