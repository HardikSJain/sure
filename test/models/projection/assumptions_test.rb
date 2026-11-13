require "test_helper"

class Projection::AssumptionsTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @a = assumptions
  end

  test "defaults" do
    assert_equal [ 10, 12, 6, 0, 0 ], [ @a.appraisal_pct, @a.return_pct, @a.spending_rise_pct, @a.employee_pf, @a.other_deductions ]
    assert_nil @a.spending
    assert_nil @a.goal_amount
    assert_nil @a.birth_date
    assert_nil @a.ctc
    assert_equal [], @a.excluded
  end

  test "saves per user, Indian commas accepted" do
    @a.update!(appraisal_pct: "8", goal_amount: "1,00,00,000", birth_date: "2000-01-15")
    a = assumptions(@user.reload)
    assert_equal [ 8, 10_000_000, Date.new(2000, 1, 15) ], [ a.appraisal_pct, a.goal_amount, a.birth_date ]
    assert_equal 10, assumptions(users(:family_member)).appraisal_pct
  end

  test "ignores what isn't a number and clamps what is out of range" do
    @a.update!(appraisal_pct: "8", birth_date: "2000-01-15")
    @a.update!(appraisal_pct: "abc", return_pct: "-3", spending_rise_pct: "90", birth_date: "not a date")
    a = assumptions(@user.reload)
    assert_equal [ 8, 0, 20 ], [ a.appraisal_pct, a.return_pct, a.spending_rise_pct ]
    assert_equal Date.new(2000, 1, 15), a.birth_date
    @a.update!(birth_date: "2031-01-01")
    assert_equal Date.new(2000, 1, 15), assumptions(@user.reload).birth_date, "a birth date after today is ignored"
  end

  test "a blank value goes back to the default" do
    @a.update!(spending: "40000")
    @a.update!(spending: "")
    assert_nil assumptions(@user.reload).spending
  end

  test "counted buckets set what is left out" do
    @a.update!(counted: %w[investments bank nonsense])
    assert_equal Projection::BUCKET_KEYS - %w[investments bank], assumptions(@user.reload).excluded
  end

  test "toggling only touches the buckets that were on screen" do
    @a.update!(shown: %w[investments bank], counted: %w[investments])
    assert_equal %w[bank], assumptions(@user.reload).excluded
    @a.update!(shown: %w[investments bank], counted: %w[investments bank])
    assert_equal [], assumptions(@user.reload).excluded
  end

  test "absurd amounts are ignored" do
    @a.update!(goal_amount: "1e400", spending: "100000000000000000000")
    a = assumptions(@user.reload)
    assert_nil a.goal_amount
    assert_nil a.spending
  end

  test "other preferences survive" do
    @user.update!(preferences: (@user.preferences || {}).merge("cash_floors" => { "x" => "5" }))
    @a.update!(appraisal_pct: "9")
    assert_equal({ "x" => "5" }, @user.reload.preferences["cash_floors"])
  end

  private
    def assumptions(user = @user)
      Projection::Assumptions.new(user, today: Date.new(2026, 11, 13))
    end
end
