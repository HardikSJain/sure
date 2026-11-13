require "test_helper"

class ProjectionsHelperTest < ActionView::TestCase
  test "compact money in lakh and crore for rupees, K and M otherwise" do
    assert_equal "₹99.4 L", compact_money(Money.new(9_940_000, "INR"))
    assert_equal "₹1.08 Cr", compact_money(Money.new(10_800_000, "INR"))
    assert_equal "₹89 L", compact_money(Money.new(8_900_000, "INR"))
    assert_equal "$1.5M", compact_money(Money.new(1_500_000, "USD"))
    assert_equal "$250K", compact_money(Money.new(250_000, "USD"))
  end

  test "small amounts stay whole, negatives keep their sign" do
    assert_equal "₹45,000", compact_money(Money.new(45_000, "INR"))
    assert_equal "-₹2.5 L", compact_money(Money.new(-250_000, "INR"))
  end
end
