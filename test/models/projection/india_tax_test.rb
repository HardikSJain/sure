require "test_helper"

class Projection::IndiaTaxTest < ActiveSupport::TestCase
  test "no tax up to 12 lakh taxable after the rebate" do
    assert_equal 0, Projection::IndiaTax.annual_tax(300_000)
    assert_equal 0, Projection::IndiaTax.annual_tax(1_200_000)
  end

  test "marginal relief caps tax just above 12 lakh" do
    assert_equal 10_400, Projection::IndiaTax.annual_tax(1_210_000)
    assert_equal 52_000, Projection::IndiaTax.annual_tax(1_250_000)
  end

  test "slab tax plus cess above the relief band" do
    assert_equal 109_200, Projection::IndiaTax.annual_tax(1_500_000)
    assert_equal 343_200, Projection::IndiaTax.annual_tax(2_500_000)
  end

  test "monthly take-home from CTC" do
    assert_equal 79_525, Projection::IndiaTax.monthly_take_home(ctc: 1_000_000, employee_pf: 21_600, other_deductions: 2_500)
    assert_equal BigDecimal("147199.40"), Projection::IndiaTax.monthly_take_home(ctc: 2_000_000, employee_pf: 21_600, other_deductions: 2_500)
  end
end
