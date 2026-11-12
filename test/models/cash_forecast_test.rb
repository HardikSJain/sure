require "test_helper"
require Rails.root.join("test/support/cash_forecast_test_helper").to_s

class CashForecastTest < ActiveSupport::TestCase
  include CashForecastTestHelper

  setup do
    travel_to Date.new(2026, 6, 15)
    @user = users(:family_admin)
    @bank = create_bank(balance: 1000)
    @known = Date.current
    known_until(@bank, @known, 1000)
  end

  test "the lowest day before payday, against the floor" do
    create_series(@bank, name: "Rent", amount: 900, due: @known + 5)
    create_series(@bank, name: "Salary", amount: -2000, due: @known + 6, bill_type: "income")
    @user.update_cash_floor!(@bank, 200)

    low = forecast.low_points.first
    assert_equal [ @known + 5, 100 ], [ low.date, low.balance ]
    assert low.under_floor
    assert_equal @known + 6, low.next_payday
    assert_includes low.events_before.map(&:name), "Rent"
    assert forecast.tight?
    assert_equal low, forecast.first_tight
  end

  test "just above the floor is near it, not under" do
    create_series(@bank, name: "Rent", amount: 900, due: @known + 5)
    create_series(@bank, name: "Salary", amount: -2000, due: @known + 6, bill_type: "income")
    @user.update_cash_floor!(@bank, 95)

    low = forecast.low_points.first
    assert low.near_floor
    assert_not low.under_floor
    assert_not forecast.tight?
  end

  test "everyday spending comes off every day" do
    spend(@bank, 900, date: @known - 1)

    day3 = forecast.days.find { |d| d.date == @known + 3 }
    assert_in_delta 970, day3.balance, 0.01
  end

  test "with no payday the forecast is one 60-day window" do
    create_series(@bank, name: "Rent", amount: 300, due: @known + 10)

    assert_empty forecast.paydays
    assert_equal @known + 60, forecast.end_date
    assert_equal 1, forecast.low_points.size
  end

  test "with no floor set it is only tight below zero" do
    create_series(@bank, name: "Rent", amount: 400, due: @known + 5) # 600 left, then 200 a month later
    assert_not forecast.tight?

    create_series(@bank, name: "Big bill", amount: 700, due: @known + 7, frequency_preset: "annual")
    assert forecast.tight?
  end

  test "it runs through the second payday when that is later than 60 days" do
    create_series(@bank, name: "Quarterly pay", amount: -3000, due: @known + 20, bill_type: "income",
                  frequency_preset: "quarterly")
    assert forecast.end_date >= @known + 60
    assert_operator forecast.paydays.size, :<=, 2
  end

  test "an account with no history starts from its balance and today" do
    fresh = create_bank(name: "Fresh", balance: 750)
    f = CashForecast.new(fresh, user: @user)

    assert_equal Date.current, f.last_known_date
    assert_equal 750, f.starting_balance
  end

  test "a 30-day window shows the same days as the full forecast" do
    create_series(@bank, name: "Rent", amount: 900, due: @known + 5)
    window = forecast.window(30)

    assert_equal @known + 30, window.end_date
    assert_equal forecast.days.first(30).map(&:balance), window.days.map(&:balance)
  end

  test "bank accounts with bills attached are the ones forecast" do
    create_series(@bank, name: "Rent", amount: 900, due: @known + 5)
    idle = create_bank(name: "Idle")

    accounts = CashForecast.accounts_for(families(:dylan_family))
    assert_includes accounts, @bank
    assert_not_includes accounts, idle
  end

  test "each stretch until a payday is a cycle: short, tight or fine, by how far the low sits from the floor" do
    create_series(@bank, name: "Rent", amount: 900, due: @known + 5)
    create_series(@bank, name: "Salary", amount: -2000, due: @known + 6, bill_type: "income")
    @user.update_cash_floor!(@bank, 200)

    short, after = forecast.cycles.first(2)
    assert_equal [ @known + 1, @known + 6, :short, -100 ], [ short.starts_on, short.payday, short.status, short.room ]
    assert_equal @known + 6, after.starts_on
    assert_includes %i[ok tight short], after.status
  end

  test "with no payday there is one cycle for the whole forecast" do
    create_series(@bank, name: "Rent", amount: 300, due: @known + 10)

    cycle = forecast.cycles.sole
    assert_nil cycle.payday
    assert_equal :ok, cycle.status
  end

  test "the steps up to a date carry the balance after each one, everyday spending taken first" do
    spend(@bank, 900, date: @known - 1) # 10 a day
    create_series(@bank, name: "Rent", amount: 300, due: @known + 3)
    create_series(@bank, name: "Phone", amount: 50, due: @known + 3)

    steps = forecast.steps(through: @known + 3)
    assert_equal [ "Phone", "Rent" ], steps.map { |s| s.event.name }
    assert_in_delta 1000 - 30 - 50, steps.first.balance_after, 0.01
    assert_in_delta 1000 - 30 - 350, steps.last.balance_after, 0.01
    assert_in_delta 30, forecast.everyday_total(through: @known + 3), 0.01
  end

  private
    def forecast
      CashForecast.new(@bank, user: @user)
    end
end
