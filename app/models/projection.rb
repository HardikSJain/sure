# Where the family's net worth is headed, month by month, and when it reaches
# the goal.
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
  YEARS_AHEAD = 5   # the chart runs at least this far, to December
  SEARCH_YEARS = 30 # how far ahead the goal is looked for
  DEFAULT_YEARS_AHEAD = 4
  FIRST_SWITCHER_YEAR = 2

  # Ways to get there sooner: spend this share of monthly spending less, or a
  # fifth less on each of the biggest everyday categories.
  CUTS = [ BigDecimal("0.05"), BigDecimal("0.10"), BigDecimal("0.20") ].freeze
  CATEGORY_TRIM = BigDecimal("0.2")
  HABITS = 3

  Bucket = Data.define(:key, :amount, :counted)
  Point = Data.define(:month, :middle, :weak, :strong)
  Way = Data.define(:kind, :name, :amount, :crossing, :months_sooner)

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

  # Ready when both sides are known: a take-home (a declared salary, or a CTC
  # to work it out from) and spending (the data's average, or the user's).
  def ready?
    missing.nil?
  end

  # What's needed before projecting: :salary, :spending, or nil.
  def missing
    if signals.current_take_home.nil? && !(india? && assumptions.ctc.present?)
      :salary
    elsif assumptions.spending.nil? && signals.average_spending.nil?
      :spending
    end
  end

  def buckets
    @buckets ||= starting.buckets.map do |b|
      Bucket.new(key: b.key, amount: b.amount, counted: counted?(b.key))
    end
  end

  def today_total
    money(growing + flat + (epf_counted? ? epf_balance : 0))
  end

  # The user's age on `date`, when their birth date is known.
  def age_at(date)
    born = assumptions.birth_date
    return nil unless born

    date.year - born.year - ((date.month > born.month || (date.month == born.month && date.day >= born.day)) ? 0 : 1)
  end

  # --- Time ------------------------------------------------------------------

  # The months the chart shows: from next month to December of the later of
  # five years out and the year a weak market reaches the goal.
  def months
    @months ||= search_months.take_while { |month| month <= Date.new(last_year, 12, 1) }
  end

  def years
    (today.year + FIRST_SWITCHER_YEAR)..last_year
  end

  def default_year
    (crossing&.year || today.year + DEFAULT_YEARS_AHEAD).clamp(years.min, years.max)
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
    @spending ||= money(assumptions.spending || signals.average_spending || 0)
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

  # Today's share of the goal, as a whole percent up to 100.
  def goal_share
    return nil unless goal

    (today_total.amount / goal.amount * 100).round.clamp(0, 100)
  end

  # The first month the goal is reached at that scenario's return, with
  # `extra` more invested every month; nil if not within SEARCH_YEARS.
  def crossing(scenario = :middle, extra: 0)
    return nil unless goal

    index = model(scenario, extra: extra).crossing(goal.amount)
    index && search_months[index]
  end

  # Spending options that bring the goal closer, worked out from the data:
  # a share of all spending, and a fifth of each everyday category.
  def ways_sooner
    return [] unless goal

    @ways_sooner ||= begin
      cuts = CUTS.map { |share| two_figures(spending.amount * share) }.uniq.select(&:positive?)
                 .map { |amount| way(:spend_less, nil, amount) }
      habits = signals.habitual_categories(limit: HABITS).filter_map do |name, monthly|
        amount = two_figures(monthly * CATEGORY_TRIM)
        way(:category, name, amount) if amount.positive?
      end
      cuts + habits
    end
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

    # Every month the goal is looked for in, from next month on.
    def search_months
      @search_months ||= begin
        last = Date.new(today.year + SEARCH_YEARS, 12, 1)
        month = today.beginning_of_month.next_month
        list = []
        while month <= last
          list << month
          month = month.next_month
        end
        list
      end
    end

    def one_offs
      @one_offs ||= signals.one_offs(from: search_months.first, through: search_months.last.end_of_month)
    end

    def contributions
      @contributions ||= search_months.map { |month| contribution_for(month) }
    end

    def model(scenario, extra: 0)
      @models ||= {}
      @models[[ scenario, extra ]] ||= Projection::Model.new(
        growing: growing, flat: flat, annual_return: return_pct(scenario) / 100,
        contributions: extra.zero? ? contributions : contributions.map { |c| c + extra },
        epf: epf_counted? ? { balance: epf_balance, monthly: epf_monthly, annual_rate: EPF_RATE } : nil
      )
    end

    def way(kind, name, amount)
      sooner = crossing(:middle, extra: amount)
      middle = crossing
      Way.new(kind: kind, name: name, amount: money(amount), crossing: sooner,
              months_sooner: middle && sooner && month_number(middle) - month_number(sooner))
    end

    # 1,994 -> 2,000; 1,312 -> 1,300: an amount a person would say.
    def two_figures(amount)
      return 0.to_d unless amount.positive?

      step = 10**[ amount.to_i.to_s.length - 2, 0 ].max
      ((amount / step).round * step).to_d
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
      reached = crossing(:weak) || crossing(:middle)
      [ today.year + YEARS_AHEAD, reached&.year || 0 ].max
    end

    # December of `year`, held inside the chart's months.
    def december_index(year)
      search_months.index(Date.new(year.to_i.clamp(search_months.first.year, last_year), 12, 1))
    end

    # Aprils after today's month, up to and including `month`.
    def aprils_through(month)
      first = search_months.first
      (first.year..month.year).count { |year| (first..month).cover?(Date.new(year, 4, 1)) }
    end

    def month_number(date)
      date.year * 12 + date.month
    end

    def money(amount)
      Money.new(amount, family.currency)
    end
end
