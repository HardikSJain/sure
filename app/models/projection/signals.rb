# What the family's own data says about the months ahead: the salary they
# declared in Bills, what they usually spend, and bills set to end (a tax
# instalment, the last few payments of something), which come out of the
# month they fall in. Ongoing bills are already in the usual spending.
class Projection::Signals
  SPENDING_MONTHS = 6
  # A category spent in at least this often (lines a month, on average) is a
  # habit, where trimming is easiest; a monthly lump sum isn't.
  HABIT_LINES_A_MONTH = 2

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  # Monthly take-home from declared income (transfers in don't count), or
  # nil when none is declared.
  def current_take_home
    return @current_take_home if defined?(@current_take_home)

    series = recurring.where(status: "active", manual: true, bill_type: "income", destination_account_id: nil).to_a
    @current_take_home = series.empty? ? nil : series.sum { |s| convert(s.monthly_equivalent_amount.amount.abs, s.currency) }.round(2)
  end

  # Average spending over the last complete months that have activity (up to
  # six), or nil when there are none.
  def average_spending
    return @average_spending if defined?(@average_spending)

    @average_spending = spending_months.empty? ? nil : ((expense_totals.total.to_d - contributions_in_spending) / spending_months.size).round(2)
  end

  # [name, monthly average] of the biggest categories that are habits,
  # largest first, over the same months as the average.
  def habitual_categories(limit:)
    months = spending_months.size
    return [] if months.zero?

    expense_totals.category_totals
                  .reject { |ct| ct.category.id.nil? || ct.category.subcategory? }
                  .select { |ct| lines_in(ct.category) >= HABIT_LINES_A_MONTH * months }
                  .sort_by { |ct| -ct.total }
                  .first(limit)
                  .map { |ct| [ ct.category.name, (ct.total.to_d / months).round(2) ] }
  end

  # Month start => what bills set to end take out of that month.
  def one_offs(from:, through:)
    recurring.where(status: "active", manual: true, bill_type: "bill", destination_account_id: nil)
          .where.not(end_mode: "never")
          .includes(:recurring_occurrences)
          .each_with_object(Hash.new(0.to_d)) do |series, months|
            by_date = series.recurring_occurrences.index_by(&:due_on)
            series.schedule.occurrences_between(from, through).each do |date|
              occurrence = by_date[date]
              next if occurrence&.status.in?(%w[skipped missed])

              amount = occurrence ? occurrence.resolved_expected_amount : series.amount.abs
              months[date.beginning_of_month] += convert(amount.to_d.abs, series.currency)
            end
          end
          .transform_values { |v| v.round(2) }
  end

  private
    attr_reader :family, :user, :today

    # Month starts of the last complete months that have activity (up to six).
    def spending_months
      @spending_months ||= begin
        first_activity = family.earliest_activity_date
        month_start = today.beginning_of_month
        first_activity ? (1..SPENDING_MONTHS).map { |n| month_start.prev_month(n) }.select { |s| s >= first_activity.beginning_of_month } : []
      end
    end

    # Bills on accounts this user can open; another member's private salary
    # and bills are theirs.
    def recurring
      family.recurring_transactions.merge(RecurringTransaction.accessible_by(user))
    end

    # Money moved into investments is saving, not spending, even when the
    # family counts it as spending in its reports.
    def contributions_in_spending
      return 0.to_d unless family.investment_contributions_as_spending?

      scope = family.transactions.visible.excluding_pending.merge(Entry.excluding_scheduled).where(kind: "investment_contribution")
      IncomeStatement.new(family, user: user)
                     .totals(transactions_scope: scope, date_range: spending_period.start_date..spending_period.end_date)
                     .expense_money.amount.to_d
    end

    def spending_period
      Period.custom(start_date: spending_months.last, end_date: today.beginning_of_month - 1)
    end

    def expense_totals
      @expense_totals ||= IncomeStatement.new(family, user: user).expense_totals(period: spending_period)
    end

    def lines_in(category)
      @line_counts ||= family.entries.where(entryable_type: "Transaction", date: spending_period.start_date..spending_period.end_date)
                             .where("entries.amount > 0")
                             .joins("JOIN transactions ON transactions.id = entries.entryable_id")
                             .group("transactions.category_id").count
      ([ category.id ] + category.subcategories.ids).sum { |id| @line_counts[id].to_i }
    end

    def convert(amount, currency)
      return amount.to_d if currency.blank? || currency == family.currency

      Money.new(amount, currency).exchange_to(family.currency).amount
    rescue Money::ConversionError
      amount.to_d
    end
end
