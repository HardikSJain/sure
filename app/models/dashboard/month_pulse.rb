# The month so far, in one card: what came in, what went out, what was put
# away, and whether spending is on pace — against the month's budget and
# against how the same days went in recent months.
#
# Read-only. It looks the budget up but never creates one (the budgets page
# does), so a month without a budget simply shows no pace bar.
class Dashboard::MonthPulse
  # Recent full months the "usual by this day" comparison averages over.
  HISTORY_MONTHS = 6
  # Budgeted categories listed under the pace bar.
  CATEGORY_LIMIT = 4

  CategoryPace = Data.define(:name, :color, :spent, :budgeted, :percent, :over)

  attr_reader :family, :income_statement, :today, :month_start, :month_end

  def initialize(family, income_statement:, user: nil, today: Date.current)
    @family = family
    @income_statement = income_statement
    @user = user
    @today = today
    @month_start, @month_end = Budget.period_for(today, family: family)
  end

  def period
    @period ||= Period.custom(start_date: month_start, end_date: today)
  end

  def month_label
    I18n.l(month_start, format: :month_year).capitalize
  end

  # Today counts as a day gone: by tonight it has been spent in.
  def day_of_month
    (today - month_start).to_i + 1
  end

  def days_in_month
    (month_end - month_start).to_i + 1
  end

  def days_left
    [ (month_end - today).to_i, 0 ].max
  end

  def month_progress
    (day_of_month.to_d / days_in_month * 100).round(1)
  end

  def income
    money(net_totals.total_net_income)
  end

  def spent
    money(net_totals.total_net_expense)
  end

  def invested
    income_statement.invested_total(period: period)
  end

  # What is left of the month's income once spending and investing are out.
  def kept
    money(income.amount - spent.amount - invested.amount)
  end

  # Share of income still left once spending and investing are out.
  def kept_rate
    return nil unless income.amount.positive?
    (kept.amount / income.amount * 100).round
  end

  def invest_rate
    return nil unless income.amount.positive?
    (invested.amount / income.amount * 100).round
  end

  # --- Is the month's data in yet -------------------------------------------

  # Bank and card accounts whose last transaction is older than this are
  # treated as not imported up to date (statement-based accounts lag).
  STALE_AFTER_DAYS = 3

  Stale = Data.define(:account, :last_date)

  # Bank and card accounts with nothing recent: the month's spending is
  # missing whatever they have done since, so totals here are a floor.
  def stale_accounts
    @stale_accounts ||= begin
      accounts = income_statement.eligible_accounts.where(accountable_type: %w[Depository CreditCard]).to_a
      last = Entry.where(account_id: accounts.map(&:id), entryable_type: "Transaction").group(:account_id).maximum(:date)
      accounts.filter_map do |account|
        date = last[account.id]
        Stale.new(account: account, last_date: date) if date && date < today - STALE_AFTER_DAYS
      end.sort_by(&:last_date)
    end
  end

  def up_to_date?
    stale_accounts.empty?
  end

  # --- Budget pace --------------------------------------------------------

  def budget
    return @budget if defined?(@budget)

    owner = family.personal_budgets? ? @user : nil
    @budget = Budget.find_by(family: family, start_date: month_start, end_date: month_end, user: owner)
    @budget&.current_user = @user
    @budget = nil unless @budget&.initialized? && @budget.budgeted_spending.to_d.positive?
    @budget
  end

  def budgeted
    budget && money(budget.budgeted_spending)
  end

  def budget_spent
    budget && money(budget.actual_spending)
  end

  def budget_percent
    return 0 unless budget
    (budget_spent.amount / budgeted.amount * 100).round(1)
  end

  # Where spending would be today if the budget were spread evenly.
  def on_pace_amount
    budget && money(budgeted.amount * day_of_month / days_in_month)
  end

  def ahead_of_pace?
    budget.present? && budget_spent.amount > on_pace_amount.amount
  end

  def left_to_spend
    budget && money([ budgeted.amount - budget_spent.amount, 0 ].max)
  end

  # What can go out each remaining day, today included, to land on budget.
  def daily_allowance
    budget && money(left_to_spend.amount / (days_left + 1))
  end

  def over_budget?
    budget.present? && budget_spent.amount > budgeted.amount
  end

  def category_paces
    return [] unless budget

    budget.budget_categories
          .reject(&:subcategory?)
          .select(&:budgeted?)
          .map do |bc|
            limit = bc.display_budgeted_spending.to_d + bc.display_rolled_over_amount.to_d
            CategoryPace.new(name: bc.name, color: bc.category.color, spent: money(bc.actual_spending),
                             budgeted: money(limit), percent: bc.percent_of_budget_spent.to_f.round,
                             over: bc.over_budget?)
          end
          .sort_by { |c| -c.percent }
          .first(CATEGORY_LIMIT)
  end

  # --- Against recent months ----------------------------------------------

  # Average spent by this day of the month over the last HISTORY_MONTHS full
  # months (a short month counts through its last day).
  def usual_by_today
    return @usual_by_today if defined?(@usual_by_today)

    starts = (1..HISTORY_MONTHS).map { |n| month_start.prev_month(n) }
    oldest = starts.last
    return @usual_by_today = nil if oldest < family.oldest_entry_date.beginning_of_month

    history = Period.custom(start_date: oldest, end_date: month_start - 1)
    daily = income_statement.daily_expense_series(period: history)
    totals = starts.map do |start|
      cutoff = [ start + day_of_month - 1, start.end_of_month ].min
      daily.sum { |d| d.date >= start && d.date <= cutoff ? d.total.to_d : 0 }
    end
    @usual_by_today = money(totals.sum / totals.size)
  end

  def vs_usual
    usual = usual_by_today
    return nil if usual.nil? || usual.amount.zero?

    ((spent.amount - usual.amount) / usual.amount * 100).round
  end

  private
    def net_totals
      @net_totals ||= income_statement.net_category_totals(period: period)
    end

    def money(amount)
      Money.new(amount || 0, family.currency)
    end
end
