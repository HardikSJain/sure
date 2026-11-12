require "test_helper"
require Rails.root.join("test/support/cash_forecast_test_helper").to_s

class Dashboard::UpcomingMoneyTest < ActiveSupport::TestCase
  include CashForecastTestHelper

  setup do
    travel_to Date.new(2026, 6, 15)
    @user = users(:family_admin)
    @family = @user.family
    @family.recurring_transactions.destroy_all
    @bank = create_bank(balance: 1000)
    @known = Date.current - 2
    known_until(@bank, @known, 1000)
  end

  test "walks the same balance as the Bills page's room forecast, for 30 days" do
    spend(@bank, 900, date: @known - 1) # 10 a day of everyday spending
    create_series(@bank, name: "Phone bill", amount: 300, due: @known + 5)
    create_series(@bank, name: "Salary", amount: -1000, due: @known + 10, bill_type: "income")
    forecast = CashForecast.new(@bank, user: @user).window(30)

    assert_equal @bank, upcoming.account
    assert_equal @known, upcoming.last_known_date
    assert_equal [ "Phone bill", "Salary" ], upcoming.rows.first(2).map(&:name)
    bill = upcoming.rows.first
    assert_in_delta forecast.days.find { |d| d.date == @known + 5 }.balance, bill.balance_after.amount, 0.01
    assert_in_delta forecast.days.last.balance, upcoming.ending_cash.amount, 0.01
    assert_equal Date.current + 30, upcoming.horizon # 30 days ahead of today, walked from the last-known date
  end

  test "under the floor it says so, with the low point" do
    create_series(@bank, name: "Rent", amount: 900, due: @known + 5)
    @user.update_cash_floor!(@bank, 500)

    assert upcoming.under_floor?
    assert_equal @known + 5, upcoming.low_point.date
    assert_equal 500, upcoming.floor
  end

  test "nothing to show without a bank account that bills are attached to" do
    assert_not upcoming.any?
    assert_nil upcoming.account
  end

  private
    def upcoming
      Dashboard::UpcomingMoney.new(@family, user: @user)
    end
end
