# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::RenderedPreview do
  fab!(:suggester, :user)
  fab!(:post) do
    Fabricate(:post, raw: "Intro paragraph.\n\nOriginal sentence here.\n\nOutro paragraph.")
  end

  let(:suggested_raw) { "Intro paragraph.\n\nUpdated sentence here.\n\nOutro paragraph." }

  def create_suggestion(raw: suggested_raw)
    suggestion =
      Fabricate(
        :suggested_edit,
        post: post,
        user: suggester,
        raw_suggestion: raw,
        base_post_version: post.version,
      )

    DiscourseSuggestedEdits::ChangeExtractor
      .call(original_raw: post.raw, new_raw: raw)
      .each { |change| suggestion.edit_changes.create!(change) }

    suggestion.reload
  end

  def diff_limit_exceeded
    ONPDiff::DiffLimitExceeded.new(
      comparisons_used: 1,
      comparison_budget: 1,
      left_size: 1,
      right_size: 1,
    )
  end

  it "returns focused rendered changes keyed by raw hunk id without a full source preview" do
    suggestion = create_suggestion

    preview = described_class.call(suggestion)

    expect(preview.keys).to contain_exactly(:available, :changes, :gaps)
    expect(preview[:available]).to eq(true)
    expect(preview[:changes].map { |change| change[:id] }).to eq(suggestion.edit_changes.pluck(:id))
    change = preview[:changes].sole
    expect(change.keys).to contain_exactly(:id, :available, :inline, :side_by_side)
    expect(change[:available]).to eq(true)
    expect(change[:inline]).to start_with('<div class="inline-diff">')
    expect(change[:inline]).to match(%r{<del>Original\s*</del>})
    expect(change[:inline]).to match(%r{<ins>Updated\s*</ins>})
    expect(Nokogiri::HTML5.fragment(change[:inline]).css("p").size).to eq(1)
    expect(
      Nokogiri::HTML5.fragment(change[:inline]).css(".suggested-edit-preview__gap"),
    ).to be_empty
    expect(change[:side_by_side]).to include(
      'class="revision-content --previous"',
      'class="revision-content --current"',
    )
  end

  it "resolves upload short urls and marks replaced images" do
    old_upload = Fabricate(:upload)
    new_upload = Fabricate(:upload)
    post.update_columns(raw: "Our lake:\n\n![lake|690x388](#{old_upload.short_url})\n\nThoughts?")
    raw = "Our lake:\n\n![lake|690x388](#{new_upload.short_url})\n\nThoughts?"

    preview = described_class.call(create_suggestion(raw: raw))[:changes].sole

    expect(preview[:side_by_side]).to include(old_upload.url, new_upload.url)
    expect(preview[:side_by_side]).not_to include("upload://")
    expect(preview[:inline]).to match(/<img[^>]*class="diff-del"[^>]*>/)
    expect(preview[:inline]).to match(/<img[^>]*class="diff-ins"[^>]*>/)
  end

  it "renders text-only caption edits from real cooking that leaves bare top-level text" do
    post.update_columns(
      raw:
        "<p>Unchanged introduction.</p>\n" + '<img src="https://example.com/photo.png">' +
          "\nOriginal caption &lt;safe&gt; &amp; sound.",
    )
    cooked = Nokogiri::HTML5.fragment(post.cook(post.raw))
    expect(cooked.children.select(&:text?).map(&:text).join).to include(
      "Original caption <safe> & sound.",
    )
    suggestion = create_suggestion(raw: post.raw.sub("Original caption", "Updated caption"))

    preview = described_class.call(suggestion)[:changes].sole

    expect(preview[:available]).to eq(true)
    inline = Nokogiri::HTML5.fragment(preview[:inline])
    expect(inline.css("del").text).to include("Original")
    expect(inline.css("ins").text).to include("Updated")
    expect(inline.css("img, safe")).to be_empty
    sides = Nokogiri::HTML5.fragment(preview[:side_by_side])
    expect(sides.at_css("[class~='--previous']").text).to include(
      "Original caption <safe> & sound.",
    )
    expect(sides.at_css("[class~='--current']").text).to include("Updated caption <safe> & sound.")
    expect(sides.css("safe")).to be_empty
  end

  it "keeps a bare caption's inline markup and full sentence when only its tail changes" do
    post.update_columns(
      raw:
        "<p>Unchanged introduction.</p>\n" + '<img src="https://example.com/photo.png">' +
          "\nCaption <strong>bold</strong> original tail &amp; sound.",
    )
    cooked = Nokogiri::HTML5.fragment(post.cook(post.raw))
    expect(cooked.children.select(&:text?).map(&:text).join).to include("original tail & sound.")
    expect(cooked.search("./strong").text).to eq("bold")
    suggestion = create_suggestion(raw: post.raw.sub("original tail", "updated tail"))

    preview = described_class.call(suggestion)[:changes].sole

    expect(preview[:available]).to eq(true)
    sides = Nokogiri::HTML5.fragment(preview[:side_by_side])
    previous = sides.at_css("[class~='--previous']")
    current = sides.at_css("[class~='--current']")
    expect(previous.css("p").map { |paragraph| paragraph.text.strip }).to eq(
      ["Caption bold original tail & sound."],
    )
    expect(current.css("p").map { |paragraph| paragraph.text.strip }).to eq(
      ["Caption bold updated tail & sound."],
    )
    expect(sides.css("p > strong").map(&:text)).to eq(%w[bold bold])
    expect(sides.css("img")).to be_empty
    inline = Nokogiri::HTML5.fragment(preview[:inline])
    expect(inline.css("p").size).to eq(1)
    expect(inline.css("p > strong").text).to eq("bold")
    expect(inline.css("del").text).to include("original")
    expect(inline.css("ins").text).to include("updated")
  end

  it "keeps both image replacements and bare caption edits in a single rendered hunk" do
    old_url = "https://example.com/old.png"
    new_url = "https://example.com/new.png"
    post.update_columns(
      raw: "<p>Unchanged paragraph.</p>\n<img src=\"#{old_url}\">\nOriginal caption.",
    )
    cooked = Nokogiri::HTML5.fragment(post.cook(post.raw))
    expect(cooked.children.select(&:text?).map(&:text).join).to include("Original caption.")
    suggestion = create_suggestion(raw: post.raw.sub(old_url, new_url).sub("Original", "Updated"))

    preview = described_class.call(suggestion)[:changes].sole

    expect(preview[:available]).to eq(true)
    inline = Nokogiri::HTML5.fragment(preview[:inline])
    expect(inline.css("img").map { |image| image["src"] }).to contain_exactly(old_url, new_url)
    expect(inline.css("del").text).to include("Original")
    expect(inline.css("ins").text).to include("Updated")
    sides = Nokogiri::HTML5.fragment(preview[:side_by_side])
    expect(
      sides.at_css("[class~='--previous']").css("p").map { |paragraph| paragraph.text.strip },
    ).to eq(["Original caption."])
    expect(
      sides.at_css("[class~='--current']").css("p").map { |paragraph| paragraph.text.strip },
    ).to eq(["Updated caption."])
  end

  it "renders bare caption edits following an unchanged paragraph and break" do
    post.update_columns(raw: "<p>Unchanged paragraph.</p>\n<br>\nOriginal caption.")
    cooked = Nokogiri::HTML5.fragment(post.cook(post.raw))
    expect(cooked.children.select(&:text?).map(&:text).join).to include("Original caption.")

    preview =
      described_class.call(create_suggestion(raw: post.raw.sub("Original", "Updated")))[
        :changes
      ].sole

    expect(preview[:available]).to eq(true)
    inline = Nokogiri::HTML5.fragment(preview[:inline])
    expect(inline.css("p").size).to eq(1)
    expect(inline.css("br")).to be_empty
    expect(inline.css("del").text).to include("Original")
    expect(inline.css("ins").text).to include("Updated")
  end

  it "replaces embeds with links" do
    SiteSetting.allowed_iframes = "https://example.com/embed/"
    raw = "#{post.raw}\n\n<iframe src=\"https://example.com/embed/1\"></iframe>"

    preview = described_class.call(create_suggestion(raw: raw))[:changes].sole

    expect(preview[:side_by_side]).not_to include("<iframe")
    expect(preview[:side_by_side]).to include('href="https://example.com/embed/1"')
  end

  describe "embed neutralization" do
    it "replaces an iframe inside a paragraph without nesting paragraphs" do
      html = '<p>Before <iframe src="https://example.com/embed/1"></iframe> after</p>'

      output = described_class.new(create_suggestion).send(:neutralize_embeds, html)

      expect(output).to eq(
        '<p>Before <a href="https://example.com/embed/1">https://example.com/embed/1</a> after</p>',
      )
      expect(Nokogiri::HTML5.fragment(output).css("p p")).to be_empty
    end

    it "wraps a standalone iframe in a paragraph" do
      html = '<iframe src="https://example.com/embed/1"></iframe>'

      output = described_class.new(create_suggestion).send(:neutralize_embeds, html)

      expect(output).to eq(
        '<p><a href="https://example.com/embed/1">https://example.com/embed/1</a></p>',
      )
    end

    it "returns HTML without iframes unchanged without parsing it" do
      html = "<p>No embeds here.</p>"

      expect(described_class.new(create_suggestion).send(:neutralize_embeds, html)).to be(html)
    end
  end

  describe "hashtag permissions" do
    fab!(:secret_category) do
      Fabricate(:private_category, group: Fabricate(:group), slug: "secret-plans")
    end

    before { post.update_columns(last_editor_id: Fabricate(:admin).id) }

    def hashtag_slugs(preview, side)
      Nokogiri::HTML5
        .fragment(preview[:side_by_side])
        .css(".revision-content[class~='#{side}'] a.hashtag-cooked")
        .map { |link| link["data-slug"] }
    end

    it "does not resolve hashtags the suggester adds but cannot see" do
      Fabricate(:category, slug: "public-plans")
      raw = "#{post.raw}\n\n#secret-plans #public-plans"

      preview = described_class.call(create_suggestion(raw: raw))[:changes].sole

      expect(hashtag_slugs(preview, "--current")).to eq(["public-plans"])
    end

    it "renders the current post as published while the suggestion loses hidden hashtags" do
      post.update_columns(raw: "#{post.raw}\n\n#secret-plans")
      raw = post.raw.sub("Original", "Updated")

      preview = described_class.call(create_suggestion(raw: raw))[:changes].sole

      expect(hashtag_slugs(preview, "--previous")).to eq(["secret-plans"])
      expect(hashtag_slugs(preview, "--current")).to be_empty
    end

    it "includes the unaffected published hashtag permission change in every independent hunk" do
      post.update_columns(raw: "#{post.raw}\n\n#secret-plans")
      suggestion =
        create_suggestion(raw: post.raw.sub("Original", "Updated").sub("Outro", "Closing"))
      expect(suggestion.edit_changes.size).to eq(2)
      expect(
        suggestion.edit_changes.map { |change| change.before_text + change.after_text }.join,
      ).not_to include(secret_category.slug)

      preview = described_class.call(suggestion)

      expect(preview[:changes].map { |change| change[:available] }).to eq([true, true])
      preview[:changes].each do |change|
        expect(hashtag_slugs(change, "--previous")).to eq([secret_category.slug])
        expect(hashtag_slugs(change, "--current")).to be_empty
        current = Nokogiri::HTML5.fragment(change[:side_by_side]).at_css("[class~='--current']")
        expect(current.text).to include("#secret-plans")
      end
    end
  end

  it "does not change the post" do
    suggestion = create_suggestion

    original_post = post.attributes
    original_suggestion = suggestion.attributes
    original_changes = suggestion.edit_changes.map(&:attributes)

    described_class.call(suggestion)

    expect(post.attributes).to eq(original_post)
    expect(post.reload.attributes).to eq(original_post)
    expect(suggestion.reload.attributes).to eq(original_suggestion)
    expect(suggestion.edit_changes.map(&:attributes)).to eq(original_changes)
    expect(PostRevision.where(post_id: post.id)).not_to exist
  end

  it "is unavailable when the post changed without a new version" do
    suggestion = create_suggestion
    post.update_columns(raw: post.raw.sub("Outro", "Closing"))

    expect(described_class.call(suggestion.reload)).to eq(
      available: false,
      unavailable_reason: "post_changed",
    )
  end

  it "is unavailable when the post has a newer version" do
    suggestion = create_suggestion
    post.update_columns(version: post.version + 1)

    expect(described_class.call(suggestion.reload)).to include(
      available: false,
      unavailable_reason: "post_changed",
    )
  end

  it "is unavailable when the suggestion is stale" do
    suggestion = create_suggestion
    suggestion.update!(status: :stale)

    expect(described_class.call(suggestion)).to include(
      available: false,
      unavailable_reason: "post_changed",
    )
  end

  it "reports not_pending for resolved suggestions" do
    suggestion = create_suggestion

    %i[applied dismissed withdrawn].each do |status|
      suggestion.update!(status: status)

      expect(described_class.call(suggestion)).to include(
        available: false,
        unavailable_reason: "not_pending",
      )
    end
  end

  it "falls back to the source diff when secure upload rewriting hits a malformed upload URI" do
    enable_secure_uploads
    SiteSetting.login_required = true
    post.update_columns(
      raw: "Original sentence here.",
      cooked: '<p><a href="upload://foo%">broken</a></p>',
    )
    allow(Discourse).to receive(:warn_exception)

    suggestion = create_suggestion(raw: "Updated sentence here.")
    preview = described_class.call(suggestion)

    expect(preview[:available]).to eq(true)
    expect(preview[:changes]).to eq(
      [
        {
          id: suggestion.edit_changes.sole.id,
          available: false,
          unavailable_reason: "too_complex",
        },
      ],
    )
    expect(Discourse).to have_received(:warn_exception).at_least(:once)
  end

  it "falls back per change when a rendered diff exceeds its comparison budget" do
    suggestion = create_suggestion
    allow_any_instance_of(DiscourseDiff).to receive(:inline_html).and_raise(diff_limit_exceeded)

    preview = described_class.call(suggestion)

    expect(preview).to include(
      available: true,
      changes: [
        {
          id: suggestion.edit_changes.sole.id,
          available: false,
          unavailable_reason: "too_complex",
        },
      ],
    )
  end

  it "keeps other hunk previews when one candidate fails to cook" do
    suggestion = create_suggestion(raw: suggested_raw.sub("Outro", "Closing"))
    allow(Discourse).to receive(:warn_exception)
    allow_any_instance_of(Post).to receive(:cook).and_wrap_original do |method, raw, options|
      raise URI::InvalidURIError if raw.include?("Updated")
      method.call(raw, options)
    end

    preview = described_class.call(suggestion)

    expect(preview[:changes].map { |change| change[:available] }).to eq([false, true])
    expect(preview[:changes].first[:unavailable_reason]).to eq("too_complex")
    expect(preview[:changes].last[:inline]).to include("Closing")
  end

  it "falls back per change when the top-level block diff exceeds its comparison budget" do
    suggestion = create_suggestion
    allow_any_instance_of(ONPDiff).to receive(:paragraph_diff).and_raise(diff_limit_exceeded)

    preview = described_class.call(suggestion)

    expect(preview[:changes].sole).to eq(
      id: suggestion.edit_changes.sole.id,
      available: false,
      unavailable_reason: "too_complex",
    )
  end

  it "is unavailable for raw HTML posts" do
    suggestion = create_suggestion
    post.update_columns(cook_method: Post.cook_methods[:raw_html])

    expect(described_class.call(suggestion.reload)).to eq(
      available: false,
      unavailable_reason: "unsupported_post",
    )
  end

  it "returns only three focused cards for first and last image replacements and a middle text edit" do
    image_urls = (1..10).map { |index| "https://example.com/image-#{index}.png" }
    replacement_urls = %w[https://example.com/new-first.png https://example.com/new-last.png]
    blocks = image_urls.map { |url| "![photo](#{url})" }
    blocks.insert(5, "Original middle paragraph.")
    post.update_columns(raw: blocks.join("\n\n"))
    raw = post.raw.sub(image_urls.first, replacement_urls.first)
    raw = raw.sub("Original middle", "Updated middle").sub(image_urls.last, replacement_urls.last)
    suggestion = create_suggestion(raw: raw)

    preview = described_class.call(suggestion)

    expect(preview[:changes].map { |change| change[:id] }).to eq(suggestion.edit_changes.pluck(:id))
    expect(preview[:changes].size).to eq(3)
    expect(preview[:changes].map { |change| change[:available] }).to eq([true, true, true])
    %i[inline side_by_side].each do |mode|
      images = preview[:changes].map { |change| Nokogiri::HTML5.fragment(change[mode]).css("img") }
      expect(images.map(&:size)).to eq([2, 0, 2])
      expect(images.first.map { |image| image["src"] }).to contain_exactly(
        image_urls.first,
        replacement_urls.first,
      )
      expect(images.last.map { |image| image["src"] }).to contain_exactly(
        image_urls.last,
        replacement_urls.last,
      )
    end
    expect(preview[:changes][1][:inline]).to include("middle paragraph.", "<ins>Updated ")
  end

  shared_examples "independent rendered block hunks" do |kind, block, selector, child_selector, child_count|
    it "cooks incomplete raw hunks within a #{kind} independently and keeps the enclosing block" do
      post.update_columns(raw: "Intro paragraph.\n\n#{block}\n\nOutro paragraph.")
      suggestion =
        create_suggestion(
          raw:
            post.raw.sub("First item", "Updated first item").sub("Last item", "Updated last item"),
        )
      changes = suggestion.edit_changes.to_a
      expect(changes.size).to eq(2)

      preview = described_class.call(suggestion)

      expect(preview[:changes].map { |change| change[:available] }).to eq([true, true])
      expect(preview[:gaps].map { |gap| gap.key?(:html) }).to eq([true, false, true])
      expect(preview[:gaps][1][:raw]).to include("Middle item")
      expect(preview[:gaps].first[:html]).to eq("<p>Intro paragraph.</p>")
      expect(preview[:gaps].last[:html]).to eq("<p>Outro paragraph.</p>")
      preview[:changes].each_with_index do |change, index|
        current =
          Nokogiri::HTML5.fragment(change[:side_by_side]).css(
            ".revision-content[class~='--current']",
          )
        expect(current.css(selector).size).to eq(1)
        expect(current.css(child_selector).size).to eq(child_count) if child_selector
        expected =
          index == 0 ? ["Updated first item", "Last item"] : ["First item", "Updated last item"]
        expect(current.text).to include(*expected, "Middle item")
        expect(current.children.map(&:name)).to eq([kind == :table ? "div" : selector])
        expect(Nokogiri::HTML5.fragment(change[:inline]).css(selector).size).to eq(1)
      end
    end
  end

  include_examples "independent rendered block hunks",
                   :list,
                   "- First item\n- Middle item\n- Last item",
                   "ul",
                   "li",
                   3

  include_examples "independent rendered block hunks",
                   :table,
                   "| Name | Value |\n| --- | --- |\n| First item | one |\n| Middle item | two |\n| Last item | three |",
                   "table",
                   "tbody tr",
                   3

  include_examples "independent rendered block hunks",
                   :code,
                   "```text\nFirst item\nMiddle item\nLast item\n```",
                   "pre",
                   "code",
                   1

  include_examples "independent rendered block hunks",
                   :paragraph,
                   "First item\nMiddle item\nLast item",
                   "p",
                   nil,
                   nil

  it "keeps multiple separated rendered runs caused by one raw hunk" do
    old_url = "https://example.com/before"
    new_url = "https://example.com/after"
    post.update_columns(
      raw:
        "[First link][target]\n\nStable paragraph.\n\n[Last link][target]\n\n[target]: #{old_url}",
    )
    suggestion = create_suggestion(raw: post.raw.sub(old_url, new_url))

    preview = described_class.call(suggestion)[:changes].sole

    expect(preview[:available]).to eq(true)
    current =
      Nokogiri::HTML5.fragment(preview[:side_by_side]).at_css(
        ".revision-content[class~='--current']",
      )
    expect(current.css("a").map { |link| link["href"] }).to eq([new_url, new_url])
    expect(current.css("p").map(&:text)).to eq(["First link", "Last link"])
    expect(Nokogiri::HTML5.fragment(preview[:inline]).css(".inline-diff").size).to eq(1)
    sides = Nokogiri::HTML5.fragment(preview[:side_by_side]).css(".revision-content")
    expect(sides.size).to eq(2)
    expect(sides.map { |side| side.css("p").map(&:text) }).to eq([["First link", "Last link"]] * 2)
    expect(sides.map { |side| side.children.map(&:name) }).to eq([%w[p div p]] * 2)
    expect(sides.map { |side| side.css(".suggested-edit-preview__gap").map(&:text) }).to eq(
      [["…"], ["…"]],
    )
    inline = Nokogiri::HTML5.fragment(preview[:inline])
    expect(inline.css(".suggested-edit-preview__gap").map(&:text)).to eq(["…"])
    expect(inline.css("p").map(&:text)).to eq(["First link", "Last link"])
  end

  it "keeps visible-equivalent raw edits available for source review" do
    post.update_columns(raw: "A paragraph.\n\nAnother paragraph.")
    suggestion = create_suggestion(raw: post.raw.sub("\n\n", "\n\n\n"))

    preview = described_class.call(suggestion)

    expect(preview).to include(
      available: true,
      changes: [
        {
          id: suggestion.edit_changes.sole.id,
          available: false,
          unavailable_reason: "no_visible_change",
        },
      ],
    )
  end

  it "renders complete added and deleted blocks with an empty opposite side" do
    post.update_columns(raw: "Delete this paragraph.\n\nKeep this paragraph.\n\nFinal paragraph.")
    suggestion =
      create_suggestion(raw: "Keep this paragraph.\n\nFinal paragraph.\n\nAdded paragraph.")

    preview = described_class.call(suggestion)

    expect(preview[:changes].map { |change| change[:available] }).to eq([true, true])
    deletion, addition =
      preview[:changes].map { |change| Nokogiri::HTML5.fragment(change[:side_by_side]) }
    expect(deletion.at_css("[class~='--previous']").text).to eq("Delete this paragraph.")
    expect(deletion.at_css("[class~='--current']").text).to be_empty
    expect(addition.at_css("[class~='--previous']").text).to be_empty
    expect(addition.at_css("[class~='--current']").text).to eq("Added paragraph.")
  end

  it "cooks the full base once and full independent candidates on read-only copies" do
    suggestion = create_suggestion(raw: suggested_raw.sub("Outro", "Closing"))
    cooked_inputs = []
    allow_any_instance_of(Post).to receive(:cook).and_wrap_original do |method, raw, options|
      cooked_inputs << [raw, method.receiver.last_editor_id, method.receiver.readonly?]
      method.call(raw, options)
    end

    described_class.call(suggestion)

    candidates =
      suggestion.edit_changes.map do |change|
        DiscourseSuggestedEdits::ChangeApplier.call(raw: post.raw, changes: [change])
      end
    expect(cooked_inputs).to eq(
      [[post.raw, post.last_editor_id, true]] + candidates.map { |raw| [raw, suggester.id, true] },
    )
  end

  it "falls back for all remaining changes after ten candidate cooks" do
    post.update_columns(raw: (1..12).map { |index| "Original paragraph #{index}." }.join("\n\n"))
    suggestion = create_suggestion(raw: post.raw.gsub("Original", "Updated"))
    cooked_inputs = []
    allow_any_instance_of(Post).to receive(:cook).and_wrap_original do |method, raw, options|
      cooked_inputs << raw
      method.call(raw, options)
    end

    preview = described_class.call(suggestion)

    expect(preview[:changes].size).to eq(12)
    expect(preview[:changes].map { |change| change[:available] }).to eq([true] * 10 + [false] * 2)
    expect(preview[:changes].last(2).map { |change| change[:unavailable_reason] }).to eq(
      ["too_complex"] * 2,
    )
    expect(cooked_inputs.size).to eq(11)
  end

  it "counts UTF-8 bytes including the base and stops at the cumulative raw budget" do
    post.update_columns(raw: "Original café.\n\nOriginal résumé.\n\nOriginal naïve.")
    suggestion = create_suggestion(raw: post.raw.gsub("Original", "Updated!"))
    cooked_inputs = []
    allow_any_instance_of(Post).to receive(:cook).and_wrap_original do |method, raw, options|
      cooked_inputs << raw
      method.call(raw, options)
    end

    stub_const(described_class, :MAX_RAW_BYTES, post.raw.bytesize * 3) do
      preview = described_class.call(suggestion)

      expect(preview[:changes].map { |change| change[:available] }).to eq([true, true, false])
      expect(preview[:changes].last[:unavailable_reason]).to eq("too_complex")
      expect(cooked_inputs.sum(&:bytesize)).to eq(described_class::MAX_RAW_BYTES)
    end
  end

  it "skips cooking when the base alone exceeds 128 KiB" do
    post.update_columns(raw: "Original #{"é" * (64 * 1024)}")
    suggestion = create_suggestion(raw: post.raw.sub("Original", "Updated"))
    cooked_inputs = []
    allow_any_instance_of(Post).to receive(:cook).and_wrap_original do |method, raw, options|
      cooked_inputs << raw
      method.call(raw, options)
    end

    preview = described_class.call(suggestion)

    expect(preview[:changes].sole).to eq(
      id: suggestion.edit_changes.sole.id,
      available: false,
      unavailable_reason: "too_complex",
    )
    expect(cooked_inputs).to be_empty
  end

  it "rejects a suggestion whose hunks do not exactly reconstruct its stored raw" do
    suggestion = create_suggestion
    suggestion.update!(raw_suggestion: "Unrelated proposed content.")

    expect(described_class.call(suggestion)).to eq(
      available: false,
      unavailable_reason: "post_changed",
    )
  end

  it "rejects hunks that no longer match the base" do
    suggestion = create_suggestion
    suggestion.edit_changes.sole.update!(before_text: "Mismatched original text.")

    expect(described_class.call(suggestion.reload)).to eq(
      available: false,
      unavailable_reason: "post_changed",
    )
  end

  describe "context gaps" do
    it "keeps exact source context between two hunks sharing a paragraph without a rendered middle gap" do
      post.update_columns(
        raw:
          "Intro.\n\nOriginal first line.\nUnchanged middle line.\nOriginal last line.\n\nOutro.",
      )
      suggestion = create_suggestion(raw: post.raw.gsub("Original", "Updated"))
      first, last = suggestion.edit_changes.to_a
      expect(suggestion.edit_changes.size).to eq(2)

      preview = described_class.call(suggestion)

      expect(preview[:changes].map { |change| change[:available] }).to eq([true, true])
      expect(
        preview[:changes].map { |change| Nokogiri::HTML5.fragment(change[:inline]).css("p").size },
      ).to eq([1, 1])
      expect(preview[:gaps]).to eq(
        [
          {
            id: "start-#{first.id}",
            before_change_id: first.id,
            after_change_id: nil,
            raw: "Intro.\n\n",
            html: "<p>Intro.</p>",
          },
          {
            id: "#{first.id}-#{last.id}",
            before_change_id: last.id,
            after_change_id: first.id,
            raw: "Unchanged middle line.\n",
          },
          {
            id: "#{last.id}-end",
            before_change_id: nil,
            after_change_id: last.id,
            raw: "\nOutro.",
            html: "<p>Outro.</p>",
          },
        ],
      )
    end

    it "keeps exact source context between two hunks sharing a list without a rendered middle gap" do
      post.update_columns(
        raw:
          "Intro.\n\n- Original first item\n- Unchanged middle item\n- Original last item\n\nOutro.",
      )
      suggestion = create_suggestion(raw: post.raw.gsub("Original", "Updated"))
      first, last = suggestion.edit_changes.to_a
      expect(suggestion.edit_changes.size).to eq(2)

      preview = described_class.call(suggestion)

      expect(preview[:changes].map { |change| change[:available] }).to eq([true, true])
      expect(
        preview[:changes].map { |change| Nokogiri::HTML5.fragment(change[:inline]).css("ul").size },
      ).to eq([1, 1])
      expect(preview[:gaps]).to eq(
        [
          {
            id: "start-#{first.id}",
            before_change_id: first.id,
            after_change_id: nil,
            raw: "Intro.\n\n",
            html: "<p>Intro.</p>",
          },
          {
            id: "#{first.id}-#{last.id}",
            before_change_id: last.id,
            after_change_id: first.id,
            raw: "- Unchanged middle item\n",
          },
          {
            id: "#{last.id}-end",
            before_change_id: nil,
            after_change_id: last.id,
            raw: "\nOutro.",
            html: "<p>Outro.</p>",
          },
        ],
      )
    end

    it "returns exact leading, two between and trailing gaps using stable raw change ids" do
      image_url = "https://example.com/unchanged.png"
      post.update_columns(
        raw:
          "Leading café.\n\nFirst original.\n\nBetween first and second.\n\nSecond original.\n\n![unchanged](#{image_url})\n\nThird original.\n\nTrailing résumé.",
      )
      suggestion = create_suggestion(raw: post.raw.gsub("original", "updated"))
      first, second, third = suggestion.edit_changes.to_a
      cooked_inputs = []
      allow_any_instance_of(Post).to receive(:cook).and_wrap_original do |method, raw, options|
        cooked_inputs << raw
        method.call(raw, options)
      end

      preview = described_class.call(suggestion)

      expect(preview[:changes].map { |change| change[:available] }).to eq([true, true, true])
      gaps = preview[:gaps]
      expect(gaps.map { |gap| gap.except(:html) }).to eq(
        [
          {
            id: "start-#{first.id}",
            before_change_id: first.id,
            after_change_id: nil,
            raw: "Leading café.\n\n",
          },
          {
            id: "#{first.id}-#{second.id}",
            before_change_id: second.id,
            after_change_id: first.id,
            raw: "\nBetween first and second.\n\n",
          },
          {
            id: "#{second.id}-#{third.id}",
            before_change_id: third.id,
            after_change_id: second.id,
            raw: "\n![unchanged](#{image_url})\n\n",
          },
          {
            id: "#{third.id}-end",
            before_change_id: nil,
            after_change_id: third.id,
            raw: "\nTrailing résumé.",
          },
        ],
      )
      expect(gaps.map { |gap| gap.key?(:html) }).to eq([true] * 4)
      expect(gaps.values_at(0, 1, 3).map { |gap| Nokogiri::HTML5.fragment(gap[:html]).text }).to eq(
        ["Leading café.", "Between first and second.", "Trailing résumé."],
      )
      expect(
        Nokogiri::HTML5.fragment(gaps[2][:html]).css("img").map { |image| image["src"] },
      ).to eq([image_url])
      expect(
        [
          gaps[0][:raw],
          first.before_text,
          gaps[1][:raw],
          second.before_text,
          gaps[2][:raw],
          third.before_text,
          gaps[3][:raw],
        ].join,
      ).to eq(post.raw)
      expect(cooked_inputs.size).to eq(4)
      expect(cooked_inputs.first).to eq(post.raw)
      expect(
        gaps.map do |gap|
          Nokogiri::HTML5.fragment(gap[:html]).css("ins, del, .diff-ins, .diff-del").size
        end,
      ).to eq([0] * 4)
    end

    it "omits whitespace-only leading and trailing gaps" do
      post.update_columns(raw: "\n\nFirst original.\n\nBetween paragraphs.\n\nSecond original.\n\n")
      suggestion = create_suggestion(raw: post.raw.gsub("original", "updated"))
      first, second = suggestion.edit_changes.to_a

      preview = described_class.call(suggestion)

      expect(preview[:gaps]).to eq(
        [
          {
            id: "#{first.id}-#{second.id}",
            before_change_id: second.id,
            after_change_id: first.id,
            raw: "\nBetween paragraphs.\n\n",
            html: "<p>Between paragraphs.</p>",
          },
        ],
      )
    end

    it "returns an empty authoritative gap list when the whole document changes" do
      post.update_columns(raw: "Original paragraph.")

      preview = described_class.call(create_suggestion(raw: "Updated paragraph."))

      expect(preview[:available]).to eq(true)
      expect(preview[:gaps]).to eq([])
    end

    it "uses consumed base positions and insertion anchors around deletions and additions" do
      post.update_columns(raw: "Leading.\n\nRemove paragraph.\n\nBetween.\n\nTrailing.")
      suggestion = create_suggestion(raw: "Leading.\n\nBetween.\n\nNew paragraph.\n\nTrailing.")
      deletion, insertion = suggestion.edit_changes.to_a
      expect(deletion.after_text).to be_empty
      expect(insertion.before_text).to be_empty

      preview = described_class.call(suggestion)

      expect(preview[:changes].map { |change| change[:available] }).to eq([true, true])
      expect(preview[:gaps].map { |gap| Nokogiri::HTML5.fragment(gap[:html]).text }).to eq(
        %w[Leading. Between. Trailing.],
      )
      gaps = preview[:gaps]
      expect(
        [
          gaps[0][:raw],
          deletion.before_text,
          gaps[1][:raw],
          insertion.before_text,
          gaps[2][:raw],
        ].join,
      ).to eq(post.raw)
      expect(gaps.map { |gap| gap.values_at(:after_change_id, :before_change_id) }).to eq(
        [[nil, deletion.id], [deletion.id, insertion.id], [insertion.id, nil]],
      )
    end

    it "keeps the complete base interval between pure insertions at both document edges" do
      post.update_columns(raw: "Middle content.\n\nLast content.\n")
      suggestion = create_suggestion(raw: "New opening.\n\n#{post.raw}\n\nNew ending.")
      first, last = suggestion.edit_changes.to_a
      expect([first.before_text, last.before_text]).to eq(["", ""])

      preview = described_class.call(suggestion)

      expect(preview[:gaps]).to eq(
        [
          {
            id: "#{first.id}-#{last.id}",
            before_change_id: last.id,
            after_change_id: first.id,
            raw: post.raw,
            html: "<p>Middle content.</p><p>Last content.</p>",
          },
        ],
      )
    end

    it "retains exact source intervals but omits all rendered context when any hunk exceeds a cooking budget" do
      post.update_columns(
        raw: "Leading.\n\nFirst original.\n\nBetween.\n\nSecond original.\n\nTrailing.",
      )
      suggestion = create_suggestion(raw: post.raw.gsub("original", "updated"))
      cooked_inputs = []
      allow_any_instance_of(Post).to receive(:cook).and_wrap_original do |method, raw, options|
        cooked_inputs << raw
        method.call(raw, options)
      end
      previews = []

      stub_const(described_class, :MAX_CANDIDATE_COOKS, 1) do
        previews << described_class.call(suggestion)
      end
      stub_const(described_class, :MAX_RAW_BYTES, 0) do
        previews << described_class.call(suggestion)
      end

      expect(previews.first[:changes].map { |change| change[:available] }).to eq([true, false])
      expect(previews.last[:changes].map { |change| change[:available] }).to eq([false, false])
      previews.each do |preview|
        expect(preview[:gaps].map { |gap| gap[:raw] }).to eq(
          ["Leading.\n\n", "\nBetween.\n\n", "\nTrailing."],
        )
        expect(preview[:gaps].map { |gap| gap.key?(:html) }).to eq([false, false, false])
      end
      expect(cooked_inputs.size).to eq(2)
    end

    it "provides source-only gaps for visible-equivalent changes" do
      post.update_columns(raw: "Leading.\n\nTrailing.")
      suggestion = create_suggestion(raw: post.raw.sub("\n\n", "\n\n\n"))

      preview = described_class.call(suggestion)

      expect(preview[:changes].sole[:unavailable_reason]).to eq("no_visible_change")
      expect(preview[:gaps].map { |gap| gap[:raw] }).to eq(["Leading.\n\n", "Trailing."])
      expect(preview[:gaps].map { |gap| gap.key?(:html) }).to eq([false, false])
    end

    it "omits rendered context everywhere when a distant hunk has multiple changed block runs" do
      old_url = "https://example.com/old"
      new_url = "https://example.com/new"
      post.update_columns(
        raw:
          "Leading context.\n\nOriginal sentence.\n\n[First link][target]\n\nMiddle context.\n\n[Last link][target]\n\n[target]: #{old_url}\n\nTrailing context.",
      )
      suggestion = create_suggestion(raw: post.raw.sub("Original", "Updated").sub(old_url, new_url))

      preview = described_class.call(suggestion)

      expect(preview[:changes].map { |change| change[:available] }).to eq([true, true])
      expect(
        Nokogiri::HTML5
          .fragment(preview[:changes].last[:inline])
          .css(".suggested-edit-preview__gap")
          .size,
      ).to eq(1)
      expect(preview[:gaps].size).to eq(3)
      expect(preview[:gaps].map { |gap| gap.key?(:html) }).to eq([false, false, false])
      expect(preview[:gaps].first[:raw]).to eq("Leading context.\n\n")
      expect(preview[:gaps].last[:raw]).to eq("\nTrailing context.")
    end

    it "omits rendered context for non-monotonic coverage caused by repeated base blocks" do
      post.update_columns(raw: "Leading.\n\nRepeat.\n\nRepeat.\n\nRepeat.\n\nTrailing.")
      suggestion =
        Fabricate(
          :suggested_edit,
          post: post,
          user: suggester,
          base_post_version: post.version,
          raw_suggestion: "Leading.\n\nRepeat.\n\nInserted.\n\nRepeat.\n\nTrailing.",
        )
      Fabricate(
        :suggested_edit_change,
        suggested_edit: suggestion,
        position: 0,
        start_offset: "Leading.\n\n".length,
        before_text: "Repeat.\n\n",
        after_text: "",
      )
      Fabricate(
        :suggested_edit_change,
        suggested_edit: suggestion,
        position: 1,
        start_offset: "Leading.\n\nRepeat.\n\nRepeat.\n\n".length,
        before_text: "",
        after_text: "Inserted.\n\n",
      )

      preview = described_class.call(suggestion)

      expect(preview[:changes].map { |change| change[:available] }).to eq([true, true])
      expect(
        preview[:changes].map do |change|
          Nokogiri::HTML5.fragment(change[:inline]).css(".suggested-edit-preview__gap").size
        end,
      ).to eq([0, 0])
      expect(preview[:gaps].map { |gap| gap[:raw] }).to eq(
        ["Leading.\n\n", "Repeat.\n\n", "Repeat.\n\nTrailing."],
      )
      expect(preview[:gaps].map { |gap| gap.key?(:html) }).to eq([false, false, false])
    end

    it "reuses the base's neutralized iframe context without another cook" do
      SiteSetting.allowed_iframes = "https://example.com/embed/"
      post.update_columns(
        raw:
          "<iframe src=\"https://example.com/embed/1\"></iframe>\n\nOriginal sentence.\n\nTrailing.",
      )
      suggestion = create_suggestion(raw: post.raw.sub("Original", "Updated"))

      preview = described_class.call(suggestion)

      leading = Nokogiri::HTML5.fragment(preview[:gaps].first[:html])
      expect(leading.css("iframe")).to be_empty
      expect(leading.css("a").map { |anchor| anchor["href"] }).to eq(
        ["https://example.com/embed/1"],
      )
    end
  end
end
