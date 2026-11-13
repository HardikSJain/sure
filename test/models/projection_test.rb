require "test_helper"
require Rails.root.join("test/support/projection_test_helper").to_s

class ProjectionTest < ActiveSupport::TestCase
  include ProjectionTestHelper

  TODAY = Date.new(2026, 11, 13)

  setup do
    @user = users(:empty)
    @family = @user.family
    @family.update!(currency: "INR", country: "IN")
    @bank = create_account(@family, :depository, balance: 50_000)
    create_account(@family, :investment, balance: 100_000)
    declare_bill(@bank, user: @user, name: "Pay", amount: 85_000, first_due_on: Date.new(2026, 12, 1), is_income: true)
    (5..10).each { |m| spend(@bank, 30_000, date: Date.new(2026, m, 10)) }
    @assumptions = Projection::Assumptions.new(@user, today: TODAY)
    @assumptions.update!(goal_amount: "2000000", goal_year: "2030")
  end

  test "starts from today's counted buckets and invests what's left after spending" do
    assert_equal Money.new(150_000, "INR"), projection.today_total
    assert_equal 55_000, projection.monthly_investing_now.amount
  end

  test "the headline sits inside the band" do
    p = projection
    assert_operator p.value_at(2030, :weak), :<, p.value_at(2030)
    assert_operator p.value_at(2030), :<, p.value_at(2030, :strong)
  end

  test "spending rises each April" do
    assert_equal 53_200, projection.contribution_for(Date.new(2027, 4, 1))
  end

  test "a bill set to end comes out of that month" do
    declare_bill(@bank, user: @user, name: "Tax instalment", amount: 27_000, first_due_on: Date.new(2026, 12, 15),
                        frequency_preset: "annual", end_after_count: 1)
    assert_equal 28_000, projection.contribution_for(Date.new(2026, 12, 1))
  end

  test "leaving a flat bucket out takes it off today and off every month" do
    with_all = projection.value_at(2030)
    @assumptions.update!(counted: Projection::BUCKET_KEYS - %w[bank])
    assert_equal 100_000, projection.today_total.amount
    assert_equal with_all.amount - 50_000, projection.value_at(2030).amount
  end

  test "the parts of the headline add up to it" do
    c = projection.composition(2030)
    assert_equal projection.value_at(2030), c[:today] + c[:put_in] + c[:growth]
  end

  test "EPF is set aside when there is no EPF account, counted when there is" do
    @assumptions.update!(employee_pf: "21600")
    assert_operator projection.epf_aside(2030).amount, :>, 0
    create_account(@family, :investment, balance: 40_000, subtype: "epf")
    assert_nil projection.epf_aside(2030)
    assert_includes projection.buckets.select(&:counted).map(&:key), "epf"
  end

  test "goal share, crossing and lateness agree" do
    p = projection
    assert_equal 8, p.goal_share
    assert p.crossing
    assert_equal (p.crossing.year * 12 + p.crossing.month) - (2030 * 12 + 12), p.months_late
    assert_operator p.extra_needed(:middle).amount, :>, 0 if p.months_late.positive?
  end

  test "not ready without a declared salary or a CTC" do
    @family.recurring_transactions.destroy_all
    assert_not projection.ready?
    @assumptions.update!(ctc: "1000000")
    assert projection.ready?
  end

  test "a goal already reached" do
    @assumptions.update!(goal_amount: "100000")
    p = projection
    assert_equal 100, p.goal_share
    assert_equal 0, p.extra_needed(:middle).amount
    assert_equal p.months.first, p.crossing
  end

  test "no goal leaves out the goal parts" do
    @assumptions.update!(goal_amount: "")
    p = projection
    assert_nil p.goal
    assert_nil p.crossing
    assert_nil p.extra_needed(:middle)
    assert_equal 2030, p.default_year
  end

  test "take-home steps for an Indian salary with a CTC" do
    @assumptions.update!(ctc: "1000000", employee_pf: "21600", other_deductions: "2500")
    assert_equal %i[now new_tax_year appraisal], projection.take_home_changes.first(3).map(&:reason)
  end

  test "the horizon runs a year past the goal, and at least five years" do
    p = projection
    assert_equal Date.new(2026, 12, 1), p.months.first
    assert_equal Date.new(2031, 12, 1), p.months.last
    assert_equal 2028..2031, p.years
  end

  private
    def projection
      Projection.new(@family, user: @user, today: TODAY)
    end
end
