# Will a bank account have room? Walks its balance day by day from the last
# date it is known (statement-based accounts lag), through the next two
# paydays and at least `min_days`, drawing down everyday spending and applying
# every expected event, then finds the lowest day before each payday and
# compares it with the floor the user set for the account.
#
# Read-only: it never creates or changes bills, occurrences or entries.
class CashForecast
  DEFAULT_MIN_DAYS = 60
  # A low point within this share above the floor is "near" it.
  NEAR_FLOOR_MARGIN = BigDecimal("1.1")
  # Far enough out to find two paydays for any monthly income.
  LOOKAHEAD_DAYS = 93

  Day = Data.define(:date, :balance, :events)
  LowPoint = Data.define(:date, :balance, :under_floor, :near_floor, :next_payday, :events_before)
  # A stretch up to a payday (payday nil for the stretch after the last one,
  # or the whole forecast when there is no payday). `room` is how far its
  # lowest day sits above the floor (negative when short).
  Cycle = Data.define(:starts_on, :payday, :low_point, :status, :room)
  # One event with the balance right after it (everyday spending for the day
  # comes off before the day's events).
  Step = Data.define(:date, :event, :balance_after)

  # Visible bank accounts that bills or income are attached to, the one with
  # the most attached first.
  def self.accounts_for(family)
    counts = family.recurring_transactions.where(status: "active")
                   .pluck(:account_id, :destination_account_id).flatten.compact.tally
    family.accounts.visible.where(accountable_type: "Depository", id: counts.keys)
          .sort_by { |account| [ -counts[account.id], account.name.to_s ] }
  end

  attr_reader :account, :user, :today

  def initialize(account, user:, today: Date.current, min_days: DEFAULT_MIN_DAYS, horizon_days: nil)
    @account = account
    @user = user
    @today = today
    @min_days = min_days
    @horizon_days = horizon_days
  end

  def last_known_date
    @last_known_date ||= CashForecast::Events.last_known_date(account, today: today)
  end

  def starting_balance
    @starting_balance ||= account.balances.where(currency: account.currency, date: ..last_known_date)
                                 .order(date: :desc).pick(:end_balance)&.to_d || account.balance.to_d
  end

  def floor
    @floor ||= user ? user.cash_floor(account) : BigDecimal("0")
  end

  def daily_spend
    @daily_spend ||= CashForecast::DailySpend.new(account, through: last_known_date).amount
  end

  def end_date
    @end_date ||= if @horizon_days
      last_known_date + @horizon_days
    else
      [ last_known_date + @min_days, all_paydays.second ].compact.max
    end
  end

  def events
    @events ||= all_events.select { |event| event.date <= end_date }
  end

  def paydays
    @paydays ||= all_paydays.select { |date| date <= end_date }
  end

  def days
    @days ||= begin
      by_date = events.group_by(&:date)
      balance = starting_balance
      ((last_known_date + 1)..end_date).map do |date|
        todays = by_date.fetch(date, [])
        balance = balance - daily_spend + todays.sum(&:amount)
        Day.new(date: date, balance: balance, events: todays)
      end
    end
  end

  # The lowest day of each stretch between paydays (the earliest, on a tie).
  def low_points
    @low_points ||= windows.filter_map do |window_days, next_payday|
      low = window_days.min_by(&:balance)
      next unless low

      under = low.balance < floor
      LowPoint.new(
        date: low.date, balance: low.balance, under_floor: under,
        near_floor: !under && low.balance < floor * NEAR_FLOOR_MARGIN,
        next_payday: next_payday,
        events_before: window_days.select { |d| d.date <= low.date }.flat_map(&:events)
      )
    end
  end

  def tight?
    first_tight.present?
  end

  # The stretches between paydays, each with its lowest day and how it sits
  # against the floor: :short (under it), :tight (within 10% above) or :ok.
  def cycles
    @cycles ||= windows.filter_map do |window_days, payday|
      low = window_days.min_by(&:balance)
      next unless low

      point = low_points.find { |lp| lp.date == low.date }
      status = point.under_floor ? :short : (point.near_floor ? :tight : :ok)
      Cycle.new(starts_on: window_days.first.date, payday: payday, low_point: point, status: status,
                room: point.balance - floor)
    end
  end

  def steps(through:)
    previous = starting_balance
    days.take_while { |day| day.date <= through }.flat_map do |day|
      balance = previous - daily_spend
      previous = day.balance
      day.events.map do |event|
        balance += event.amount
        Step.new(date: day.date, event: event, balance_after: balance)
      end
    end
  end

  # Everyday spending from the day after the last-known date through `through`.
  def everyday_total(through:)
    daily_spend * [ (through - last_known_date).to_i, 0 ].max
  end

  def first_tight
    low_points.find(&:under_floor)
  end

  # Ways to make room, for the first tight day, or else the lowest day that is
  # near the floor; none when there is room throughout.
  def suggestions
    @suggestions ||= begin
      low = first_tight || low_points.select(&:near_floor).min_by(&:balance)
      low ? CashForecast::Suggestions.new(self).for(low) : []
    end
  end

  # The same forecast cut to its first `days` days (the dashboard shows 30).
  def window(days)
    self.class.new(account, user: user, today: today, horizon_days: days)
  end

  private
    def all_events
      @all_events ||= CashForecast::Events.new(account, from: last_known_date + 1,
                                                        through: last_known_date + [ @min_days, LOOKAHEAD_DAYS ].max).to_a
    end

    def all_paydays
      @all_paydays ||= all_events.select { |event| event.kind == :income }.map(&:date).uniq.sort
    end

    # [days in the stretch, the payday that ends it (nil for the last)]
    def windows
      boundaries = paydays.select { |date| date > last_known_date + 1 }
      groups = days.slice_before { |day| boundaries.include?(day.date) }.to_a
      groups.each_with_index.map do |group, i|
        [ group, boundaries[i] ]
      end
    end
end
