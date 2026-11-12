# Every day's spending over the last few months as a calendar heatmap (weeks
# as columns, weekdays as rows), plus the patterns it shows: the usual day,
# the heaviest weekday, the biggest days and how many days had no spending.
#
# Days add up the same rows the dashboard's other spending numbers do
# (IncomeStatement#daily_expense_series), so a day here, summed over a month,
# matches the month's spending elsewhere.
class Dashboard::SpendingCalendar
  include IncomeStatement::ScopedTransactionsQuery

  WEEKS = 26
  # Intensity steps above zero; cells are shaded 1..LEVELS by where the day
  # falls among the spending days (quantiles), so one huge purchase does not
  # flatten every other day to the palest shade.
  LEVELS = 4
  TOP_ITEMS_PER_DAY = 3
  BIGGEST_DAYS = 3

  Day = Data.define(:date, :total, :level, :items, :in_range) do
    def future? = date > Date.current
    def weekday_index = (date.wday + 6) % 7 # Monday first
  end
  Item = Data.define(:name, :amount)
  Weekday = Data.define(:label, :average, :share)

  attr_reader :family, :today

  def initialize(family, income_statement:, today: Date.current)
    @family = family
    @income_statement = income_statement
    @today = today
  end

  # Monday of the first week shown: WEEKS whole weeks, the last one this
  # week. Days before the family's first entry, and after today, stay blank.
  def start_date
    @start_date ||= today.beginning_of_week(:monday) - (WEEKS - 1).weeks
  end

  def period
    @period ||= Period.custom(start_date: start_date, end_date: today)
  end

  def weeks
    @weeks ||= days.each_slice(7).to_a
  end

  # Month labels over the columns: [column index, label] at each week that
  # holds a month's first day.
  def month_labels
    labels = weeks.each_with_index.filter_map do |week, i|
      first = week.find { |d| d.date.day == 1 } || (i.zero? ? week.first : nil)
      [ i, I18n.l(first.date, format: "%b") ] if first
    end
    # The first column's partial month only gets a label with room before the next one.
    labels.shift if labels.size > 1 && labels[0][0].zero? && labels[1][0] < 3
    labels
  end

  def weekday_labels
    I18n.t("date.abbr_day_names").rotate(1) # Monday first
  end

  def days
    @days ||= begin
      thresholds = level_thresholds
      first_data_day = family.oldest_entry_date
      (start_date..(start_date + WEEKS * 7 - 1)).map do |date|
        total = totals_by_date[date] || 0
        in_range = date <= today && date >= first_data_day
        level = in_range && total.positive? ? (thresholds.index { |t| total <= t } || LEVELS - 1) + 1 : 0
        Day.new(date: date, total: money(total), level: level, items: items_by_date[date] || [], in_range: in_range)
      end
    end
  end

  def tracked_days
    @tracked_days ||= days.select(&:in_range)
  end

  def total
    money(tracked_days.sum { |d| d.total.amount })
  end

  def average_day
    return money(0) if tracked_days.empty?
    money(total.amount / tracked_days.size)
  end

  def no_spend_days
    tracked_days.count { |d| d.total.amount.zero? }
  end

  def biggest_days
    tracked_days.select { |d| d.total.amount.positive? }.max_by(BIGGEST_DAYS) { |d| d.total.amount }
  end

  # Average spend per weekday, Monday first, with each one's share of the
  # heaviest weekday (for the bar width).
  def weekdays
    @weekdays ||= begin
      labels = weekday_labels
      averages = (0..6).map do |i|
        same = tracked_days.select { |d| d.weekday_index == i }
        same.empty? ? 0 : same.sum { |d| d.total.amount } / same.size
      end
      top = averages.max.to_d
      averages.each_with_index.map do |avg, i|
        Weekday.new(label: labels[i], average: money(avg), share: top.positive? ? (avg / top * 100).round : 0)
      end
    end
  end

  def heaviest_weekday
    weekdays.max_by { |w| w.average.amount }
  end

  # Weekend days (Sat, Sun) against weekdays, as average per day.
  def weekend_vs_weekday
    weekend, weekday = tracked_days.partition { |d| d.weekday_index >= 5 }
    avg = ->(set) { set.empty? ? 0 : set.sum { |d| d.total.amount } / set.size }
    [ money(avg.(weekend)), money(avg.(weekday)) ]
  end

  def any?
    tracked_days.any? { |d| d.total.amount.positive? }
  end

  private
    attr_reader :income_statement

    def totals_by_date
      @totals_by_date ||= income_statement.daily_expense_series(period: period).to_h { |d| [ d.date, d.total.to_d ] }
    end

    # Upper bounds of each shade, from the quantiles of the spending days.
    def level_thresholds
      amounts = totals_by_date.values.select(&:positive?).sort
      return Array.new(LEVELS, Float::INFINITY) if amounts.empty?

      (1..LEVELS).map do |step|
        step == LEVELS ? amounts.last : amounts[((amounts.size * step / LEVELS.to_f).ceil - 1).clamp(0, amounts.size - 1)]
      end
    end

    # The biggest few expense lines of each day, for the hover card. Same
    # scoping as the daily totals (ScopedTransactionsQuery), one row per entry.
    def items_by_date
      @items_by_date ||= begin
        # The same account scope the daily totals use (IncomeStatement#included_account_ids).
        @included_account_ids = income_statement.user&.finance_accounts&.pluck(:id)
        rows = @included_account_ids&.empty? ? [] : ActiveRecord::Base.connection.select_all(items_sql)
        rows.group_by { |r| r["day"].to_date }.transform_values do |list|
          list.map { |r| Item.new(name: r["name"], amount: money(r["total"])) }
        end
      end
    end

    def items_sql
      transactions_scope = family.transactions.visible.excluding_pending.merge(Entry.excluding_scheduled).in_period(period)
      params = base_sql_params(start_date: start_date, end_date: today, limit: TOP_ITEMS_PER_DAY)
      params[:included_account_ids] = @included_account_ids if @included_account_ids
      ActiveRecord::Base.sanitize_sql_array([ <<~SQL, params ])
        SELECT day, name, total FROM (
          SELECT ae.date AS day, ae.name AS name,
                 #{converted_amount_sql("at")} AS total,
                 ROW_NUMBER() OVER (PARTITION BY ae.date ORDER BY #{converted_amount_sql("at")} DESC) AS rank
          FROM (#{transactions_scope.to_sql}) at
          #{entries_join_sql("at")}
          #{accounts_join_sql}
          #{exchange_rates_join_sql}
          WHERE at.kind NOT IN (#{budget_excluded_kinds_sql})
            #{investment_activity_label_sql("at")}
            AND ae.excluded = false
            AND a.family_id = :family_id
            AND a.status IN ('draft', 'active')
            AND a.exclude_from_reports = false
            #{exclude_tax_advantaged_sql}
            #{include_finance_accounts_sql}
            AND #{classification_sql("at")} = 'expense'
        ) ranked
        WHERE rank <= :limit
        ORDER BY day, total DESC
      SQL
    end

    def money(amount)
      Money.new(amount || 0, family.currency)
    end
end
