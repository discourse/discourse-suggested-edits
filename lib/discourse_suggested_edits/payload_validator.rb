# frozen_string_literal: true

module DiscourseSuggestedEdits
  class PayloadValidator
    include ActiveModel::Model

    attr_accessor :raw, :reason

    validates :reason, length: { maximum: 1000 }, allow_blank: true
    validate :raw_length

    private

    def raw_length
      StrippedLengthValidator.validate(self, :raw, raw.to_s, SiteSetting.first_post_length)
    end
  end
end
