# Where the family's net worth is headed, month by month, against a goal.
#
# Today's counted buckets are the start. Each month, what's left of take-home
# after spending (and after any bill set to end that month) is invested at
# month end. Investments and those contributions grow at the chosen return;
# EPF at its own rate; everything else stays flat. Three returns give the
# middle estimate and the weak-to-strong band around it. These are
# estimates, and the views say so.
class Projection
  # What can count toward the goal, each with a toggle.
  BUCKET_KEYS = %w[investments epf bank gold owed other debts].freeze
  FLAT_KEYS = %w[bank gold owed other].freeze

  WEAK_GAP = 4      # points below the middle return
  STRONG_GAP = 3    # points above it
  EPF_RATE = 0.0825
  YEARS_AHEAD = 5   # the horizon runs at least this far, to December
  DEFAULT_YEARS_AHEAD = 4
  FIRST_SWITCHER_YEAR = 2

  Bucket = Data.define(:key, :amount, :counted)
  Point = Data.define(:month, :middle, :weak, :strong)

  attr_reader :family, :user, :today

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def assumptions
    @assumptions ||= Projection::Assumptions.new(user, today: today)
  end

  def india?
    family.country == "IN"
  end

  # A take-home is known: a declared salary, or a CTC to work it out from.
  def ready?
    signals.current_take_home.present? || (india? && assumptions.ctc.present?)
  end

  def buckets
    @buckets ||= starting.buckets.map do |b|
      Bucket.new(key: b.key, amount: b.amount, counted: counted?(b.key))
    end
  end

  def today_total
    money(growing + flat + (epf_counted? ? epf_balance : 0))
  end

  # --- Time ------------------------------------------------------------------

  def months
    @months ||= begin
      last = Date.new(last_year, 12, 1)
      month = today.beginning_of_month.next_month
      list = []
      while month <= last
        list << month
        month = month.next_month
      end
      list
    end
  end

  def years
    (today.year + FIRST_SWITCHER_YEAR)..last_year
  end

  def default_year
    (assumptions.goal_year || today.year + DEFAULT_YEARS_AHEAD).clamp(years.min, years.max)
  end

  # --- Values ----------------------------------------------------------------

  def points
    @points ||= months.each_with_index.map do |month, i|
      Point.new(month: month, middle: model(:middle).values[i], weak: model(:weak).values[i], strong: model(:strong).values[i])
    end
  end

  # Net worth at the end of December of `year`.
  def value_at(year, scenario = :middle)
    money(model(scenario).values[december_index(year)])
  end

  def return_pct(scenario = :middle)
    middle = assumptions.return_pct
    case scenario
    when :weak then [ middle - WEAK_GAP, 0 ].max
    when :strong then middle + STRONG_GAP
    else middle
    end
  end

  # --- Money in and out ------------------------------------------------------

  def spending_from_data
    signals.average_spending&.then { |amount| money(amount) }
  end

  def spending
    money(assumptions.spending || signals.average_spending || 0)
  end

  def contribution_for(month)
    month = month.beginning_of_month
    rise = (1 + assumptions.spending_rise_pct / 100)**aprils_through(month)
    (take_home.for(month) - spending.amount * rise - one_offs.fetch(month, 0)).round(2)
  end

  def monthly_investing_now
    money(contributions.first)
  end

  def take_home_changes
    take_home.changes(months)
  end

  # --- The goal --------------------------------------------------------------

  def goal
    assumptions.goal_amount&.then { |amount| money(amount) }
  end

  def goal_month
    goal && assumptions.goal_year && Date.new(assumptions.goal_year, 12, 1)
  end

  # Today's share of the goal, as a whole percent up to 100.
  def goal_share
    return nil unless goal

    (today_total.amount / goal.amount * 100).round.clamp(0, 100)
  end

  # The first month the middle estimate reaches the goal, if it does.
  def crossing
    return nil unless goal

    index = model(:middle).crossing(goal.amount)
    index && months[index]
  end

  # Months after the goal date that the crossing comes (negative: early).
  def months_late
    crossing && goal_month && month_number(crossing) - month_number(goal_month)
  end

  # The extra a month, from now, that lands the goal by its date.
  def extra_needed(scenario)
    return nil unless goal_month

    money(model(scenario).extra_needed(goal: goal.amount, by: months.index(goal_month)))
  end

  # What the value at December of `year` is made of. The three add up to it.
  def composition(year)
    value = value_at(year)
    put_in = money(model(:middle).put_in(december_index(year)))
    { today: today_total, put_in: put_in, growth: value - today_total - put_in }
  end

  # The EPF pot at December of `year` while it isn't counted (no EPF account
  # yet, or left out), so the page can say what's missing.
  def epf_aside(year)
    return nil if epf_counted?

    balance = starting.epf_account? ? epf_balance : 0.to_d
    return nil if epf_monthly.zero? && balance.zero?

    count = december_index(year) + 1
    pot = Projection::Model.new(growing: 0, flat: 0, contributions: Array.new(count, 0), annual_return: 0,
                                epf: { balance: balance, monthly: epf_monthly, annual_rate: EPF_RATE })
    money(pot.values.last)
  end

  private
    def starting
      @starting ||= Projection::StartingPoint.new(family, user: user)
    end

    def signals
      @signals ||= Projection::Signals.new(family, user: user, today: today)
    end

    def take_home
      @take_home ||= Projection::TakeHome.new(
        current: signals.current_take_home, ctc: india? ? assumptions.ctc : nil,
        employee_pf: assumptions.employee_pf, other_deductions: assumptions.other_deductions,
        appraisal: assumptions.appraisal_pct / 100, today: today
      )
    end

    def one_offs
      @one_offs ||= signals.one_offs(from: months.first, through: months.last.end_of_month)
    end

    def contributions
      @contributions ||= months.map { |month| contribution_for(month) }
    end

    def model(scenario)
      @models ||= {}
      @models[scenario] ||= Projection::Model.new(
        growing: growing, flat: flat, contributions: contributions, annual_return: return_pct(scenario) / 100,
        epf: epf_counted? ? { balance: epf_balance, monthly: epf_monthly, annual_rate: EPF_RATE } : nil
      )
    end

    def counted?(key)
      !assumptions.excluded.include?(key)
    end

    def amount_of(key)
      starting.buckets.find { |b| b.key == key }&.amount || 0.to_d
    end

    def growing
      counted?("investments") ? amount_of("investments") : 0.to_d
    end

    def flat
      FLAT_KEYS.sum(0.to_d) { |key| counted?(key) ? amount_of(key) : 0 } - (counted?("debts") ? amount_of("debts") : 0)
    end

    def epf_counted?
      starting.epf_account? && counted?("epf")
    end

    def epf_balance
      amount_of("epf")
    end

    # Both sides of PF go into EPF each month.
    def epf_monthly
      assumptions.employee_pf * 2 / 12
    end

    def last_year
      [ (assumptions.goal_year || 0) + 1, today.year + YEARS_AHEAD ].max
    end

    # December of `year`, held inside the horizon.
    def december_index(year)
      months.index(Date.new(year.to_i.clamp(months.first.year, last_year), 12, 1))
    end

    # Aprils after today's month, up to and including `month`.
    def aprils_through(month)
      first = months.first
      (first.year..month.year).count { |year| (first..month).cover?(Date.new(year, 4, 1)) }
    end

    def month_number(date)
      date.year * 12 + date.month
    end

    def money(amount)
      Money.new(amount, family.currency)
    end
end
