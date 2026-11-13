// Following links in place would close the review and drop its decisions.
export default function openSuggestedEditLink(event) {
  const link = event.target.closest("a[href]");
  if (!link) {
    return;
  }

  event.preventDefault();
  const href = link.getAttribute("href");
  if (href.startsWith("#")) {
    scrollToFragment(link, href.slice(1));
  } else if (link.protocol === "http:" || link.protocol === "https:") {
    window.open(link.href, "_blank", "noopener,noreferrer");
  }
}

function scrollToFragment(link, fragment) {
  if (!fragment) {
    return;
  }

  let decoded;
  try {
    decoded = decodeURIComponent(fragment);
  } catch {
    decoded = fragment;
  }

  // Repeated ids belong to their own card/context column and diff version.
  const side = link.closest(
    ".revision-content, .suggested-edit-preview__body, .suggested-edit-context__body"
  );
  const id = CSS.escape(decoded);
  const targets = [...side.querySelectorAll(`#${id}, a[name="${id}"]`)];
  const isDeleted = (element) => Boolean(element.closest("del, .diff-del"));
  const target =
    targets.find((element) => isDeleted(element) === isDeleted(link)) ??
    targets[0];
  const modal = link.closest(".d-modal__body");
  if (target && modal) {
    const bounds = modal.getBoundingClientRect();
    const scale = bounds.height / modal.offsetHeight || 1;
    modal.scrollTop +=
      (target.getBoundingClientRect().top - bounds.top) / scale -
      modal.clientTop;
  }
}
