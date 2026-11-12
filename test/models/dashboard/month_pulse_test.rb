require "test_helper"

class Dashboard::MonthPulseTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family
  end

  test "spending, earnings and what is left follow the month's transactions" do
    before_spent, before_income = pulse.then { |p| [ p.spent.amount, p.income.amount ] }
    # Categorised apart: Sure nets income against spending within a category.
    create_transaction(account: accounts(:depository), amount: 250, name: "Groceries run", date: Date.current,
                       currency: @family.currency, category: categories(:food_and_drink))
    create_transaction(account: accounts(:depository), amount: -1000, name: "Paycheck", date: Date.current,
                       currency: @family.currency, category: categories(:income))
    after = pulse

    assert_equal before_spent + 250, after.spent.amount
    assert_equal before_income + 1000, after.income.amount
    assert_equal after.income.amount - after.spent.amount - after.invested.amount, after.kept.amount
  end

  test "budget pace spreads the month's budget evenly over its days" do
    budget = Budget.find_or_bootstrap(@family, start_date: Date.current, user: @user)
    budget.update!(budgeted_spending: 3000, expected_income: 5000)
    p = pulse

    assert p.budget
    expected = (3000.to_d * p.day_of_month / p.days_in_month)
    assert_in_delta expected, p.on_pace_amount.amount, 0.01
    unless p.over_budget?
      assert_in_delta (3000 - p.budget_spent.amount) / (p.days_left + 1), p.daily_allowance.amount, 0.01
    end
  end

  test "a month without a budget has no pace, and looking does not create one" do
    @family.budgets.destroy_all
    assert_no_difference -> { Budget.count } do
      assert_nil pulse.budget
    end
  end

  test "a bank or card account with nothing recent marks the month as not all in" do
    account = @family.accounts.create!(name: "Statement card", balance: 0, currency: @family.currency, owner: @user,
                                       accountable: CreditCard.new, status: "active")
    create_transaction(account: account, amount: 10, date: 10.days.ago.to_date, currency: @family.currency)

    stale = pulse.stale_accounts.find { |s| s.account == account }
    assert stale
    assert_equal 10.days.ago.to_date, stale.last_date
    assert_not pulse.up_to_date?

    create_transaction(account: account, amount: 10, date: Date.current, currency: @family.currency)
    assert_not pulse.stale_accounts.any? { |s| s.account == account }
  end

  test "days of the month add up" do
    p = pulse
    assert_equal p.days_in_month, p.day_of_month + p.days_left
  end

  private
    def pulse
      Dashboard::MonthPulse.new(@family, income_statement: IncomeStatement.new(@family, user: @user), user: @user)
    end
end
