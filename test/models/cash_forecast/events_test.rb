require "test_helper"
require Rails.root.join("test/support/cash_forecast_test_helper").to_s

class CashForecast::EventsTest < ActiveSupport::TestCase
  include CashForecastTestHelper
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 6, 15)
    @bank = create_bank
    @known = Date.current - 3
    known_until(@bank, @known, 1000)
  end

  test "a bill due on or before the last-known date is already in the balance; one after it counts" do
    create_series(@bank, name: "Old bill", amount: 50, due: @known - 1)
    create_series(@bank, name: "Rent", amount: 400, due: Date.current + 5)

    assert events.select { |e| e.name == "Old bill" }.all? { |e| e.date > @known }
    rent = events.find { |e| e.name == "Rent" }
    assert_equal Date.current + 5, rent.date
    assert_equal(-400, rent.amount)
    assert_equal :bill, rent.kind
  end

  test "a bill marked paid still counts unless the payment is in the known balance" do
    paid_later = create_series(@bank, name: "Paid later", amount: 80, due: Date.current + 2)
    paid_later.recurring_occurrences.find_by!(due_on: Date.current + 2).close!("paid", source: "user")

    paid_early = create_series(@bank, name: "Paid early", amount: 90, due: Date.current + 4)
    occurrence = paid_early.recurring_occurrences.find_by!(due_on: Date.current + 4)
    payment = spend(@bank, 90, date: @known - 1)
    RecurringAllocation.create!(recurring_occurrence: occurrence, entry_id: payment.id, allocated_amount: 90,
                                currency: @bank.currency, source: "user_confirmed", state: "confirmed")
    occurrence.close!("paid", source: "user")

    assert events.any? { |e| e.name == "Paid later" && e.date == Date.current + 2 }
    assert_not events.any? { |e| e.name == "Paid early" && e.date == Date.current + 4 }
  end

  test "skipped occurrences never count and snoozed ones count on their snoozed date" do
    skipped = create_series(@bank, name: "Skipped", amount: 30, due: Date.current + 3)
    skipped.recurring_occurrences.find_by!(due_on: Date.current + 3).skip!
    snoozed = create_series(@bank, name: "Snoozed", amount: 40, due: Date.current + 3)
    snoozed.recurring_occurrences.find_by!(due_on: Date.current + 3).update_columns(snoozed_until: Date.current + 9)

    assert_not events.any? { |e| e.name == "Skipped" && e.date == Date.current + 3 }
    assert_equal Date.current + 9, events.find { |e| e.name == "Snoozed" }.date
  end

  test "income and transfers into the account come in" do
    create_series(@bank, name: "Salary", amount: -2000, due: Date.current + 6, bill_type: "income")
    owed = families(:dylan_family).accounts.create!(name: "Owed by a friend", balance: 600, currency: @bank.currency,
                                                    owner: users(:family_admin), accountable: OtherAsset.new, status: "active")
    create_series(owed, name: "Friend repays", amount: 100, due: Date.current + 8, destination_account: @bank)

    salary = events.find { |e| e.name == "Salary" }
    assert_equal [ 2000, :income ], [ salary.amount, salary.kind ]
    repay = events.find { |e| e.name == "Friend repays" }
    assert_equal [ 100, :transfer_in ], [ repay.amount, repay.kind ]
  end

  test "a card bill uses the statement once it is in, and the declared amount until then" do
    due = Date.current + 10
    fresh = create_card("Fresh card", balance: 300, known: due - 20)
    stale = create_card("Stale card", balance: 999, known: due - 40)
    create_series(@bank, name: "Fresh card bill", amount: 250, due: due, destination_account: fresh)
    create_series(@bank, name: "Stale card bill", amount: 250, due: due, destination_account: stale)

    fresh_bill = events.find { |e| e.name == "Fresh card bill" }
    assert_equal [ -300, :card_bill, false ], [ fresh_bill.amount, fresh_bill.kind, fresh_bill.estimate ]
    stale_bill = events.find { |e| e.name == "Stale card bill" }
    assert_equal [ -250, :card_bill, true ], [ stale_bill.amount, stale_bill.kind, stale_bill.estimate ]
  end

  test "money already moved but not on the statement yet counts on its date" do
    spend(@bank, 40, date: @known + 1, name: "Top-up not on statement", extra: { "statement_import" => { "pending" => true } })

    pending = events.find { |e| e.kind == :pending }
    assert_equal [ @known + 1, -40, "Top-up not on statement" ], [ pending.date, pending.amount, pending.name ]
  end

  test "a wallet bill the wallet can't cover becomes a top-up from the bank that funds it" do
    wallet = create_wallet("Broker wallet", cash: 100)
    create_transfer(from_account: @bank, to_account: wallet, amount: 500, date: @known - 10)
    create_series(wallet, name: "Index SIP", amount: 270, due: Date.current + 7)

    top_ups = events.select { |e| e.kind == :top_up }
    assert_equal [ -170, -270 ], top_ups.first(2).map(&:amount)
    assert_equal Date.current + 7, top_ups.first.date
  end

  test "a wallet funded by another bank adds nothing here" do
    other_bank = create_bank(name: "Other bank")
    wallet = create_wallet("Other wallet", cash: 0)
    create_transfer(from_account: other_bank, to_account: wallet, amount: 500, date: @known - 10)
    create_series(wallet, name: "Other SIP", amount: 270, due: Date.current + 7)

    assert_empty events.select { |e| e.kind == :top_up }
  end

  test "a bill in another currency without a rate falls back to its own amount" do
    create_series(@bank, name: "Foreign bill", amount: 50, due: Date.current + 5, currency: "EUR")

    assert_equal(-50, events.find { |e| e.name == "Foreign bill" }.amount)
  end

  private
    def events
      CashForecast::Events.new(@bank, from: @known + 1, through: Date.current + 60).to_a
    end

    def create_card(name, balance:, known:)
      card = families(:dylan_family).accounts.create!(name: name, balance: balance, currency: @bank.currency,
                                                      owner: users(:family_admin), accountable: CreditCard.new, status: "active")
      known_until(card, known, balance)
      card
    end

    def create_wallet(name, cash:)
      families(:dylan_family).accounts.create!(name: name, balance: cash, cash_balance: cash, currency: @bank.currency,
                                               owner: users(:family_admin), accountable: Investment.new, status: "active")
    end
end
