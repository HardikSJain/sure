require "test_helper"
require Rails.root.join("test/support/projection_test_helper").to_s

class Projection::SignalsTest < ActiveSupport::TestCase
  include ProjectionTestHelper

  setup do
    @user = users(:empty)
    @family = @user.family
    @family.update!(currency: "USD")
    @bank = create_account(@family, :depository, balance: 10_000)
  end

  test "today's take-home is the declared salary, not transfers in" do
    declare_bill(@bank, user: @user, name: "Pay", amount: 85_000, first_due_on: Date.new(2026, 12, 1), is_income: true)
    assert_equal 85_000, signals.current_take_home
  end

  test "no declared income means no take-home" do
    declare_bill(@bank, user: @user, name: "Rent", amount: 20_000, first_due_on: Date.new(2026, 12, 1))
    assert_nil signals.current_take_home
  end

  test "spending averages the last six complete months, not this one" do
    (5..10).each { |m| spend(@bank, 30_000, date: Date.new(2026, m, 10)) }
    spend(@bank, 99_999, date: Date.new(2026, 11, 2))
    assert_equal 30_000, signals.average_spending
  end

  test "a short history averages only the months it has" do
    (8..10).each { |m| spend(@bank, 24_000, date: Date.new(2026, m, 1)) }
    assert_equal 24_000, signals.average_spending
  end

  test "a brand-new family has no average" do
    assert_nil signals.average_spending
  end

  test "a bill set to end is a one-off in its month; ongoing ones are not" do
    declare_bill(@bank, user: @user, name: "Tax instalment", amount: 27_000, first_due_on: Date.new(2026, 12, 15),
                        frequency_preset: "annual", end_after_count: 1)
    declare_bill(@bank, user: @user, name: "Rent", amount: 20_000, first_due_on: Date.new(2026, 12, 1))
    assert_equal({ Date.new(2026, 12, 1) => 27_000 }, signals.one_offs(from: Date.new(2026, 12, 1), through: Date.new(2027, 12, 31)))
  end

  test "a skipped one-off doesn't count" do
    bill = declare_bill(@bank, user: @user, name: "Tax instalment", amount: 27_000, first_due_on: Date.new(2026, 12, 15),
                               frequency_preset: "annual", end_after_count: 1)
    occurrence = bill.recurring_occurrences.find_by(due_on: Date.new(2026, 12, 15)) ||
                 bill.recurring_occurrences.create!(due_on: Date.new(2026, 12, 15), expected_amount: 27_000, currency: bill.currency)
    occurrence.skip!
    assert_equal({}, signals.one_offs(from: Date.new(2026, 12, 1), through: Date.new(2027, 12, 31)))
  end

  test "habitual categories: the biggest that come up at least twice a month" do
    travel = category("Travel")
    shopping = category("Shopping")
    lumps = category("Lump sums")
    (5..10).each do |m|
      3.times { |i| spend(@bank, 1_000, date: Date.new(2026, m, 5 + i), category: travel) }
      2.times { |i| spend(@bank, 500, date: Date.new(2026, m, 12 + i), category: shopping) }
      spend(@bank, 9_000, date: Date.new(2026, m, 20), category: lumps)
    end
    assert_equal [ [ "Travel", 3_000 ], [ "Shopping", 1_000 ] ], signals.habitual_categories(limit: 3)
    assert_equal [ [ "Travel", 3_000 ] ], signals.habitual_categories(limit: 1)
  end

  test "another member's private salary and bills don't count" do
    other = @family.users.create!(email: "member-signals@example.com", password: "password123A!", role: "member",
                                  first_name: "M", last_name: "S")
    theirs = create_account(@family, :depository, balance: 1_000, owner: other)
    declare_bill(theirs, user: other, name: "Their pay", amount: 123_000, first_due_on: Date.new(2026, 12, 1), is_income: true)
    declare_bill(theirs, user: other, name: "Their tax", amount: 9_000, first_due_on: Date.new(2026, 12, 15),
                         frequency_preset: "annual", end_after_count: 1)
    assert_nil signals.current_take_home
    assert_equal({}, signals.one_offs(from: Date.new(2026, 12, 1), through: Date.new(2027, 12, 31)))
  end

  test "money moved into investments isn't spending, whatever the family's setting" do
    @family.update!(investment_contributions_as_spending: true)
    (5..10).each do |m|
      spend(@bank, 30_000, date: Date.new(2026, m, 10))
      @bank.entries.create!(name: "SIP", date: Date.new(2026, m, 5), amount: 20_000, currency: @bank.currency,
                            entryable: Transaction.new(kind: "investment_contribution"))
    end
    assert_equal 30_000, signals.average_spending
  end

  private
    def category(name)
      @family.categories.create!(name: name, color: "#123456", lucide_icon: "shapes")
    end

    def signals
      Projection::Signals.new(@family, user: @user, today: Date.new(2026, 11, 13))
    end
end
