require "test_helper"

class Dashboard::SpendingCalendarTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family
  end

  test "whole weeks, Monday first, ending with this week" do
    cal = calendar

    assert_equal Dashboard::SpendingCalendar::WEEKS, cal.weeks.size
    assert cal.weeks.all? { |week| week.size == 7 }
    assert cal.weeks.first.first.date.monday?
    assert_includes cal.weeks.last.map(&:date), Date.current
  end

  test "a day carries its total and its biggest lines" do
    day = 3.days.ago.to_date
    create_transaction(account: accounts(:depository), amount: 40, name: "Chai", date: day, currency: @family.currency)
    create_transaction(account: accounts(:depository), amount: 160, name: "Dinner out", date: day, currency: @family.currency)

    cal = calendar
    cell = cal.days.find { |d| d.date == day }
    expected = IncomeStatement.new(@family, user: @user).daily_expense_series(period: cal.period).find { |d| d.date == day }.total

    assert_equal expected.to_d, cell.total.amount
    assert_operator cell.level, :>, 0
    assert_equal "Dinner out", cell.items.first.name if cell.items.size <= Dashboard::SpendingCalendar::TOP_ITEMS_PER_DAY
    assert_includes cell.items.map(&:name), "Dinner out"
  end

  test "month labels sit on the week holding the 1st, and never crowd the first column" do
    labels = calendar.month_labels
    assert labels.each_cons(2).all? { |(a, _), (b, _)| b - a >= 3 }
    labels.drop(1).each do |column, _|
      assert calendar.weeks[column].any? { |d| d.date.day == 1 }
    end
  end

  test "days after today are not tracked" do
    assert calendar.days.select(&:future?).none?(&:in_range)
  end

  private
    def calendar
      Dashboard::SpendingCalendar.new(@family, income_statement: IncomeStatement.new(@family, user: @user))
    end
end
