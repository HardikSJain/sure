# The dashboard's "Next 30 days": the first 30 days of the Bills page's room
# forecast (CashForecast) for the bank account most bills are attached to, so
# both pages always tell the same story: the walk starts from the account's
# last-known balance, draws down everyday spending, and includes card bills at
# their statement amount, wallet top-ups and lines not on a statement yet.
class Dashboard::UpcomingMoney
  DAYS_AHEAD = 30

  Row = Data.define(:event, :date, :name, :amount, :income, :autopay, :balance_after) do
    # The bill behind the row, when there is one (top-ups and pending lines have none).
    def series
      event.source.is_a?(RecurringOccurrence) ? event.source.recurring_transaction : nil
    end
  end

  attr_reader :family, :user

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def account
    return @account if defined?(@account)

    accessible = user ? user.accessible_accounts.pluck(:id).to_set : nil
    @account = CashForecast.accounts_for(family).find { |a| accessible.nil? || accessible.include?(a.id) }
  end

  def forecast
    @forecast ||= account && CashForecast.new(account, user: user, today: @today).window(DAYS_AHEAD)
  end

  def any?
    forecast.present? && rows.any?
  end

  def last_known_date
    forecast&.last_known_date
  end

  # Where the walk starts, kept under its old name for the view.
  def today
    last_known_date
  end

  def horizon
    forecast&.end_date
  end

  def days
    forecast ? forecast.days : []
  end

  def floor
    forecast ? forecast.floor : BigDecimal("0")
  end

  def under_floor?
    forecast.present? && forecast.tight?
  end

  def starting_cash
    money(forecast ? forecast.starting_balance : 0)
  end

  # One row per event, each with the balance right after it (a day's everyday
  # spending comes off before its events).
  def rows
    @rows ||= begin
      previous = forecast ? forecast.starting_balance : 0
      days.flat_map do |day|
        balance = previous - forecast.daily_spend
        previous = day.balance
        day.events.map do |event|
          balance += event.amount
          series = event.source.is_a?(RecurringOccurrence) ? event.source.recurring_transaction : nil
          Row.new(event: event, date: day.date, name: event.name, amount: money(event.amount.abs), income: event.inflow?,
                  autopay: series&.autopay? || false, balance_after: money(balance))
        end
      end
    end
  end

  def money_in
    money(rows.select(&:income).sum { |r| r.amount.amount })
  end

  def money_out
    money(rows.reject(&:income).sum { |r| r.amount.amount })
  end

  def ending_cash
    money(days.last&.balance || (forecast ? forecast.starting_balance : 0))
  end

  # The lowest day in the 30 (the forecast's LowPoint), or nil.
  def low_point
    forecast&.low_points&.min_by(&:balance)
  end

  def goes_negative?
    low_point.present? && low_point.balance.negative?
  end

  private
    def money(amount)
      Money.new(amount, account&.currency || family.currency)
    end
end
