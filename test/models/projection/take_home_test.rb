require "test_helper"

class Projection::TakeHomeTest < ActiveSupport::TestCase
  test "today's salary until the new tax year, then the formula, then each June's appraisal" do
    th = take_home(current: 85_000, ctc: 1_000_000)
    assert_equal 85_000, th.for(Date.new(2027, 3, 1))
    assert_equal 79_525, th.for(Date.new(2027, 4, 1))
    assert_equal BigDecimal("87858.33"), th.for(Date.new(2027, 6, 1))
    assert_equal 97_025, th.for(Date.new(2028, 6, 1))
  end

  test "the first June can come before April" do
    th = take_home(current: 85_000, ctc: 1_000_000, today: Date.new(2027, 5, 10))
    assert_equal BigDecimal("87858.33"), th.for(Date.new(2027, 6, 1))
  end

  test "a CTC with no salary on record uses the formula from the first month" do
    assert_equal 79_525, take_home(current: nil, ctc: 1_000_000).for(Date.new(2026, 12, 1))
  end

  test "without a CTC, today's salary grows by the appraisal each June" do
    th = take_home(current: 50_000, ctc: nil)
    assert_equal 50_000, th.for(Date.new(2027, 5, 1))
    assert_equal 55_000, th.for(Date.new(2027, 6, 1))
    assert_equal 60_500, th.for(Date.new(2028, 6, 1))
  end

  test "changes list each step once" do
    months = (0..24).map { |i| Date.new(2026, 12, 1) >> i }
    assert_equal %i[now new_tax_year appraisal appraisal], take_home(current: 85_000, ctc: 1_000_000).changes(months).map(&:reason)
  end

  private
    def take_home(current:, ctc:, today: Date.new(2026, 11, 13))
      Projection::TakeHome.new(current: current, ctc: ctc, employee_pf: 21_600, other_deductions: 2_500, appraisal: 0.10, today: today)
    end
end
