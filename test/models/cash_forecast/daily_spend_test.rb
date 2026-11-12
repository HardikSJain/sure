require "test_helper"
require Rails.root.join("test/support/cash_forecast_test_helper").to_s

class CashForecast::DailySpendTest < ActiveSupport::TestCase
  include CashForecastTestHelper

  setup do
    @bank = create_bank
    @through = Date.current
  end

  test "averages everyday outflows over the 90 days up to the last-known date" do
    spend(@bank, 90, date: @through - 10)
    spend(@bank, 180, date: @through - 80)

    assert_in_delta 3.0, daily(@through), 0.0001
  end

  test "leaves out one-offs over 5,000, transfers, excluded and pending lines, and money in" do
    spend(@bank, 270, date: @through - 1)
    spend(@bank, 6_000, date: @through - 2)
    spend(@bank, 500, date: @through - 3, kind: "funds_movement")
    spend(@bank, 500, date: @through - 4, excluded: true)
    spend(@bank, 500, date: @through - 5, extra: { "statement_import" => { "pending" => true } })
    spend(@bank, -500, date: @through - 6)

    assert_in_delta 3.0, daily(@through), 0.0001
  end

  test "leaves out lines that paid a bill" do
    spend(@bank, 270, date: @through - 1)
    paid = spend(@bank, 900, date: @through - 2)
    series = create_series(@bank, name: "Phone", amount: 900, due: @through - 2)
    occurrence = series.recurring_occurrences.find_by!(due_on: @through - 2)
    RecurringAllocation.create!(recurring_occurrence: occurrence, entry_id: paid.id, allocated_amount: 900,
                                currency: @bank.currency, source: "user_confirmed", state: "confirmed")

    assert_in_delta 3.0, daily(@through), 0.0001
  end

  test "ignores lines older than the window" do
    spend(@bank, 270, date: @through - 1)
    spend(@bank, 900, date: @through - 90)

    assert_in_delta 3.0, daily(@through), 0.0001
  end

  private
    def daily(through)
      CashForecast::DailySpend.new(@bank, through: through).amount
    end
end
