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
    @assumptions.update!(goal_amount: "2000000")
  end

  test "starts from today's counted buckets and invests what's left after spending" do
    assert_equal Money.new(150_000, "INR"), projection.today_total
    assert_equal 55_000, projection.monthly_investing_now.amount
  end

  test "the value in a year sits inside the band" do
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

  test "the parts of a year's value add up to it" do
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

  test "when: strong markets get there first, weak markets last" do
    p = projection
    assert p.crossing
    assert_operator p.crossing(:strong), :<=, p.crossing
    assert_operator p.crossing, :<=, p.crossing(:weak)
    assert_operator p.value_at(p.crossing.year, :middle).amount, :>=, 0
    assert_equal 8, p.goal_share
  end

  test "spending less gets there sooner, the bigger cut never later" do
    ways = projection.ways_sooner.select { |w| w.kind == :spend_less }
    assert_equal [ 1_500, 3_000, 6_000 ], ways.map { |w| w.amount.amount }
    middle = projection.crossing
    ways.each do |w|
      assert_operator w.crossing, :<=, middle
      assert_equal (middle.year * 12 + middle.month) - (w.crossing.year * 12 + w.crossing.month), w.months_sooner
    end
    assert_equal ways.map(&:crossing).sort.reverse, ways.map(&:crossing)
  end

  test "a fifth off each habitual category" do
    travel = @family.categories.create!(name: "Travel", color: "#123456", lucide_icon: "plane")
    (5..10).each { |m| 2.times { |i| spend(@bank, 2_500, date: Date.new(2026, m, 3 + i), category: travel) } }
    way = projection.ways_sooner.find { |w| w.kind == :category }
    assert_equal "Travel", way.name
    assert_equal 1_000, way.amount.amount
  end

  test "the chart runs to the later of the weak-market year and five years out" do
    assert_equal Date.new(2026, 12, 1), projection.months.first
    assert_equal Date.new(2031, 12, 1), projection.months.last
    assert_equal 2028..2031, projection.years

    @assumptions.update!(goal_amount: "50000000")
    p = projection
    assert p.crossing(:weak)
    assert_equal Date.new(p.crossing(:weak).year, 12, 1), p.months.last
  end

  test "a goal out of reach in thirty years" do
    @assumptions.update!(goal_amount: "1000000000000")
    p = projection
    assert_nil p.crossing
    assert_equal Date.new(2031, 12, 1), p.months.last
    assert p.ways_sooner.all? { |w| w.crossing.nil? }
  end

  test "not ready without a declared salary or a CTC" do
    @family.recurring_transactions.destroy_all
    assert_not projection.ready?
    @assumptions.update!(ctc: "1000000")
    assert projection.ready?
  end

  test "not ready without spending to go on" do
    @bank.entries.destroy_all
    assert_not projection.ready?
    assert_equal :spending, projection.missing
    @assumptions.update!(spending: "30000")
    assert projection.ready?
  end

  test "works out spending and take-home once, not once a month" do
    @family.update!(investment_contributions_as_spending: true)
    p = projection
    statements = 0
    counter = ->(*, payload) { statements += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      p.points
      p.crossing(:weak)
      p.ways_sooner
      p.value_at(2030)
    end
    assert_operator statements, :<, 40, "every statement, cached or not"
  end

  test "a goal already reached" do
    @assumptions.update!(goal_amount: "100000")
    p = projection
    assert_equal 100, p.goal_share
    assert_equal p.months.first, p.crossing
  end

  test "no goal leaves out the goal parts" do
    @assumptions.update!(goal_amount: "")
    p = projection
    assert_nil p.goal
    assert_nil p.crossing
    assert_equal [], p.ways_sooner
    assert_equal 2030, p.default_year
  end

  test "age at a date, from the birth date" do
    assert_nil projection.age_at(TODAY)
    @assumptions.update!(birth_date: "1995-03-07")
    assert_equal 31, projection.age_at(TODAY)
    assert_equal 34, projection.age_at(Date.new(2030, 3, 6))
    assert_equal 35, projection.age_at(Date.new(2030, 3, 7))
  end

  test "take-home steps for an Indian salary with a CTC" do
    @assumptions.update!(ctc: "1000000", employee_pf: "21600", other_deductions: "2500")
    assert_equal %i[now new_tax_year appraisal], projection.take_home_changes.first(3).map(&:reason)
  end

  private
    def projection
      Projection.new(@family, user: @user, today: TODAY)
    end
end
