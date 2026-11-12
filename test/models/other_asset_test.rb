require "test_helper"

class OtherAssetTest < ActiveSupport::TestCase
  test "money owed and gold are other-asset subtypes with labels" do
    assert_equal "Money owed", OtherAsset.short_subtype_label_for("receivable")
    assert_equal "Gold", OtherAsset.short_subtype_label_for("precious_metal")
  end
end
