# frozen_string_literal: true

Fabricator(:suggested_edit) do
  post
  user
  raw_suggestion "This is the suggested edit content."
  base_post_version 1
  status 0
end

Fabricator(:suggested_edit_change) do
  suggested_edit
  position 0
  start_offset 0
  before_text "original text"
  after_text "modified text"
end
