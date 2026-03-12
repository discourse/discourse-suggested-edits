import {
  getOriginalRaw,
  isSuggestEditActive,
} from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

/** @type {RichEditorExtension} */
const extension = {
  plugins({
    pmState: { Plugin, PluginKey },
    pmView: { Decoration, DecorationSet },
    utils: { convertFromMarkdown },
  }) {
    const pluginKey = new PluginKey("suggested-edit-markers");
    let cachedBaseline = null;
    let cachedBaselineRaw = null;

    function getBaselineDoc(fallbackDoc) {
      const originalRaw = getOriginalRaw();
      if (!originalRaw) {
        return fallbackDoc;
      }

      // Cache the parsed doc to avoid re-parsing on every transaction
      if (cachedBaselineRaw === originalRaw && cachedBaseline) {
        return cachedBaseline;
      }

      const doc = convertFromMarkdown(originalRaw);
      cachedBaseline = doc;
      cachedBaselineRaw = originalRaw;
      return doc;
    }

    // Map a character offset within node.textContent to a document position
    function charOffsetToDocPos(node, blockPos, charOffset) {
      let resultPos = blockPos + node.nodeSize - 1;
      let chars = 0;
      let found = false;

      node.descendants((child, pos) => {
        if (found) {
          return false;
        }
        if (child.isText) {
          const len = child.text.length;
          if (chars + len >= charOffset) {
            resultPos = blockPos + 1 + pos + (charOffset - chars);
            found = true;
            return false;
          }
          chars += len;
        }
      });

      return resultPos;
    }

    function addInlineDecorations(decorations, node, originalNode, blockPos) {
      const currentText = node.textContent;
      const originalText = originalNode.textContent;

      if (currentText === originalText) {
        return;
      }

      let prefixLen = 0;
      const minLen = Math.min(currentText.length, originalText.length);
      while (
        prefixLen < minLen &&
        currentText[prefixLen] === originalText[prefixLen]
      ) {
        prefixLen++;
      }

      let suffixLen = 0;
      while (
        suffixLen < minLen - prefixLen &&
        currentText[currentText.length - 1 - suffixLen] ===
          originalText[originalText.length - 1 - suffixLen]
      ) {
        suffixLen++;
      }

      const changedFrom = prefixLen;
      const changedTo = currentText.length - suffixLen;

      if (changedFrom >= changedTo) {
        return;
      }

      const from = charOffsetToDocPos(node, blockPos, changedFrom);
      const to = charOffsetToDocPos(node, blockPos, changedTo);

      decorations.push(
        Decoration.inline(from, to, {
          class: "suggested-edit-changed-text",
        })
      );
    }

    function buildDecorations(doc, originalDoc) {
      const decorations = [];

      doc.forEach((node, offset, index) => {
        if (index >= originalDoc.childCount) {
          decorations.push(
            Decoration.node(offset, offset + node.nodeSize, {
              class: "suggested-edit-changed-block suggested-edit-new-block",
            })
          );
        } else {
          const originalNode = originalDoc.child(index);
          if (!node.eq(originalNode)) {
            decorations.push(
              Decoration.node(offset, offset + node.nodeSize, {
                class: "suggested-edit-changed-block",
              })
            );
            addInlineDecorations(decorations, node, originalNode, offset);
          }
        }
      });

      if (doc.childCount < originalDoc.childCount && doc.childCount > 0) {
        const lastNode = doc.lastChild;
        const lastPos = doc.content.size - lastNode.nodeSize;
        const hasDecoration = decorations.some((d) => d.from === lastPos);
        if (!hasDecoration) {
          decorations.push(
            Decoration.node(lastPos, lastPos + lastNode.nodeSize, {
              class: "suggested-edit-changed-block",
            })
          );
        }
      }

      return decorations.length
        ? DecorationSet.create(doc, decorations)
        : DecorationSet.empty;
    }

    return new Plugin({
      key: pluginKey,
      state: {
        init() {
          cachedBaseline = null;
          cachedBaselineRaw = null;
          return { originalDoc: null, decorations: DecorationSet.empty };
        },
        apply(tr, value, _oldState, newState) {
          if (!isSuggestEditActive()) {
            cachedBaseline = null;
            cachedBaselineRaw = null;
            return { originalDoc: null, decorations: DecorationSet.empty };
          }

          const baseline = getBaselineDoc(null);
          const originalDoc = baseline || value.originalDoc;

          if (originalDoc) {
            return {
              originalDoc,
              decorations: buildDecorations(newState.doc, originalDoc),
            };
          }

          if (tr.docChanged && tr.getMeta("addToHistory") === false) {
            return {
              originalDoc: newState.doc,
              decorations: DecorationSet.empty,
            };
          }

          return {
            originalDoc: value.originalDoc,
            decorations: value.decorations.map(tr.mapping, tr.doc),
          };
        },
      },
      props: {
        decorations(state) {
          return pluginKey.getState(state)?.decorations ?? DecorationSet.empty;
        },
      },
    });
  },
};

export default extension;
