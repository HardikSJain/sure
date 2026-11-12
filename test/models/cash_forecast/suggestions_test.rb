require "test_helper"
require Rails.root.join("test/support/cash_forecast_test_helper").to_s

class CashForecast::SuggestionsTest < ActiveSupport::TestCase
  include CashForecastTestHelper
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 6, 15)
    @user = users(:family_admin)
    @bank = create_bank(balance: 1000)
    @known = Date.current
    known_until(@bank, @known, 1000)
    @user.update_cash_floor!(@bank, 500)
    @payday = @known + 10
    create_series(@bank, name: "Salary", amount: -3000, due: @payday, bill_type: "income")
  end

  test "a card bill due just before payday suggests moving its due date" do
    card = other_account("Travel card", CreditCard.new, balance: 800)
    known_until(card, @known - 10, 800) # this cycle's statement is in
    create_series(@bank, name: "Travel card bill", amount: 800, due: @payday - 2, destination_account: card)

    move = suggestions.find { |s| s.kind == :move_due_date }
    assert_equal [ "Travel card", 800 ], [ move.name, move.amount ]
  end

  test "money owed comes back as a suggestion, unless it is already being repaid on a schedule" do
    create_series(@bank, name: "Rent", amount: 800, due: @payday - 2)
    other_account("Lent to a friend", OtherAsset.new(subtype: "receivable"), balance: 650)
    scheduled = other_account("Lent, repaid monthly", OtherAsset.new(subtype: "receivable"), balance: 900)
    create_series(scheduled, name: "Monthly repayment", amount: 100, due: @known + 20, destination_account: @bank)

    owed = suggestions.select { |s| s.kind == :receivable }
    assert_equal [ [ "Lent to a friend", 650 ] ], owed.map { |s| [ s.name, s.amount ] }
  end

  test "gold and investments are never suggested" do
    create_series(@bank, name: "Rent", amount: 800, due: @payday - 2)
    other_account("Gold coins", OtherAsset.new(subtype: "precious_metal"), balance: 5000)
    other_account("Brokerage", Investment.new, balance: 5000)

    assert_empty suggestions.select { |s| s.kind == :receivable }
    assert_not suggestions.any? { |s| s.name.in?([ "Gold coins", "Brokerage" ]) }
  end

  test "income before the low point is something it depends on" do
    owed = other_account("Lent, repaid monthly", OtherAsset.new(subtype: "receivable"), balance: 900)
    create_series(owed, name: "Friend repays", amount: 100, due: @known + 3, destination_account: @bank)
    create_series(@bank, name: "Rent", amount: 800, due: @payday - 2)

    depends = suggestions.find { |s| s.kind == :income_dependency }
    assert_equal "Friend repays", depends.name
    assert_equal forecast.first_tight.balance - 100, depends.balance_if
  end

  test "a wallet top-up is listed so it is no surprise" do
    create_series(@bank, name: "Rent", amount: 800, due: @payday - 2)
    wallet = other_account("Broker wallet", Investment.new, balance: 0, cash_balance: 0)
    create_transfer(from_account: @bank, to_account: wallet, amount: 50, date: @known - 5)
    create_series(wallet, name: "Index SIP", amount: 200, due: @known + 4)

    top_up = suggestions.find { |s| s.kind == :wallet_top_up }
    assert_equal [ "Top up Broker wallet", 200 ], [ top_up.name, top_up.amount ]
  end

  test "nothing to suggest when there is room" do
    assert_empty suggestions
  end

  test "money owed in someone else's private account is not suggested, and their card stays unnamed" do
    create_series(@bank, name: "Rent", amount: 800, due: @payday - 2)
    member = users(:family_member)
    families(:dylan_family).accounts.create!(name: "Member's loan to a friend", balance: 700, currency: @bank.currency,
                                             owner: member, accountable: OtherAsset.new(subtype: "receivable"), status: "active")
    private_card = families(:dylan_family).accounts.create!(name: "Member's private card", balance: 500, currency: @bank.currency,
                                                            owner: member, accountable: CreditCard.new, status: "active")
    known_until(private_card, @known - 5, 500)
    create_series(@bank, name: "Their card bill", amount: 500, due: @payday - 1, destination_account: private_card)

    names = suggestions.map(&:name)
    assert_not_includes names, "Member's loan to a friend"
    assert_not_includes names, "Member's private card"
  end

  private
    def forecast
      CashForecast.new(@bank, user: @user)
    end

    def suggestions
      forecast.suggestions
    end

    def other_account(name, accountable, balance:, cash_balance: nil)
      families(:dylan_family).accounts.create!(name: name, balance: balance, cash_balance: cash_balance || balance,
                                               currency: @bank.currency, owner: @user, accountable: accountable, status: "active")
    end
end
