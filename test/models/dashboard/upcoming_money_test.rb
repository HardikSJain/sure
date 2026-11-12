require "test_helper"

class Dashboard::UpcomingMoneyTest < ActiveSupport::TestCase
  setup do
    @family = users(:family_admin).family
  end

  test "walks bank cash forward through bills and income, in date order" do
    bill_due = Date.current + 5
    pay_due = Date.current + 10
    create_series(name: "Phone bill", amount: 300, due: bill_due)
    create_series(name: "Salary", amount: -1000, due: pay_due, bill_type: "income")

    upcoming = Dashboard::UpcomingMoney.new(@family)
    bill = upcoming.rows.find { |r| r.name == "Phone bill" }
    pay = upcoming.rows.find { |r| r.name == "Salary" }

    assert bill && pay
    assert_not bill.income
    assert pay.income
    assert_operator upcoming.rows.index(bill), :<, upcoming.rows.index(pay)
    assert_equal 300, bill.amount.amount
    assert_equal 1000, pay.amount.amount
    before_bill = upcoming.rows.take_while { |r| r != bill }.sum { |r| r.income ? r.amount.amount : -r.amount.amount }
    assert_equal upcoming.starting_cash.amount + before_bill - 300, bill.balance_after.amount
  end

  test "nothing past the horizon" do
    create_series(name: "Far away", amount: 50, due: Date.current + Dashboard::UpcomingMoney::DAYS_AHEAD + 10)

    assert_not Dashboard::UpcomingMoney.new(@family).rows.any? { |r| r.name == "Far away" }
  end

  private
    def create_series(name:, amount:, due:, bill_type: "bill")
      @family.recurring_transactions.create!(
        account: accounts(:depository), name: name, amount: amount, dedup_scope: amount.to_s,
        currency: @family.currency, expected_day_of_month: due.day, anchor_date: due,
        last_occurrence_date: due.prev_month, next_expected_date: due, status: "active",
        manual: true, bill_type: bill_type
      )
    end
end
