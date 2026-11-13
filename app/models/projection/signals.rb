# What the family's own data says about the months ahead: the salary they
# declared in Bills, what they usually spend, and bills set to end (a tax
# instalment, the last few payments of something), which come out of the
# month they fall in. Ongoing bills are already in the usual spending.
class Projection::Signals
  SPENDING_MONTHS = 6

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  # Monthly take-home from declared income (transfers in don't count), or
  # nil when none is declared.
  def current_take_home
    series = family.recurring_transactions
                   .where(status: "active", manual: true, bill_type: "income", destination_account_id: nil).to_a
    return nil if series.empty?

    series.sum { |s| convert(s.monthly_equivalent_amount.amount.abs, s.currency) }.round(2)
  end

  # Average spending over the last complete months that have activity (up to
  # six), or nil when there are none.
  def average_spending
    first_activity = family.earliest_activity_date
    return nil unless first_activity

    month_start = today.beginning_of_month
    starts = (1..SPENDING_MONTHS).map { |n| month_start.prev_month(n) }
                                 .select { |start| start >= first_activity.beginning_of_month }
    return nil if starts.empty?

    period = Period.custom(start_date: starts.last, end_date: month_start - 1)
    total = IncomeStatement.new(family, user: user).expense_totals(period: period).total
    (total.to_d / starts.size).round(2)
  end

  # Month start => what bills set to end take out of that month.
  def one_offs(from:, through:)
    family.recurring_transactions
          .where(status: "active", manual: true, bill_type: "bill", destination_account_id: nil)
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

    def convert(amount, currency)
      return amount.to_d if currency.blank? || currency == family.currency

      Money.new(amount, currency).exchange_to(family.currency).amount
    rescue Money::ConversionError
      amount.to_d
    end
end
