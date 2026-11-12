class OtherAsset < ApplicationRecord
  include Accountable

  # Kinds an "other asset" can be when it matters what it is: money someone owes
  # you comes back as cash; gold is an investment and never something to spend.
  SUBTYPES = {
    "receivable" => { short: "Money owed", long: "Money owed to you" },
    "precious_metal" => { short: "Gold", long: "Gold & precious metals" }
  }.freeze

  class << self
    def color
      "#12B76A"
    end

    def icon
      "plus"
    end

    def classification
      "asset"
    end
  end
end
