# The next few weeks of money already known to be coming and going — bills,
# card dues, SIPs, salary, money owed back — from the bills schedule, walked
# day by day from today's bank balance to show where cash bottoms out.
class Dashboard::UpcomingMoney
  DAYS_AHEAD = 30
  # Overdue rows older than this are history, not something to plan around.
  OVERDUE_WINDOW = 31

  Row = Data.define(:occurrence, :date, :name, :amount, :income, :overdue, :autopay, :balance_after) do
    def series = occurrence.recurring_transaction
  end

  attr_reader :family, :today

  def initialize(family, today: Date.current)
    @family = family
    @today = today
  end

  def horizon
    today + DAYS_AHEAD
  end

  # Cash in bank accounts now, in the family currency.
  def starting_cash
    @starting_cash ||= Money.new(cash_accounts.sum { |a| to_family_currency(a.balance, a.currency) }, family.currency)
  end

  def rows
    @rows ||= begin
      balance = starting_cash.amount
      occurrences.map do |o|
        amount = to_family_currency(o.remaining_amount, o.currency)
        income = o.recurring_transaction.typed_income? || o.recurring_transaction.amount.negative?
        balance += income ? amount : -amount
        Row.new(occurrence: o, date: [ o.effective_due_on, today ].max, name: o.recurring_transaction.display_name,
                amount: Money.new(amount, family.currency), income: income, overdue: o.effective_due_on < today,
                autopay: o.recurring_transaction.autopay?, balance_after: Money.new(balance, family.currency))
      end
    end
  end

  def any?
    rows.any?
  end

  def money_in
    Money.new(rows.select(&:income).sum { |r| r.amount.amount }, family.currency)
  end

  def money_out
    Money.new(rows.reject(&:income).sum { |r| r.amount.amount }, family.currency)
  end

  def ending_cash
    rows.last&.balance_after || starting_cash
  end

  # The day cash is lowest, if it dips below where it starts.
  def low_point
    low = rows.min_by { |r| r.balance_after.amount }
    low if low && low.balance_after.amount < starting_cash.amount
  end

  def goes_negative?
    low_point.present? && low_point.balance_after.negative?
  end

  def overdue_count
    rows.count(&:overdue)
  end

  private
    def cash_accounts
      family.accounts.visible.included_in_reports.where(accountable_type: "Depository")
    end

    def occurrences
      list = family.recurring_occurrences
                   .open_status
                   .joins(:recurring_transaction)
                   .merge(RecurringTransaction.where(status: "active"))
                   .where("#{RecurringOccurrence::EFFECTIVE_DUE_ON_SQL} BETWEEN ? AND ?", today - OVERDUE_WINDOW, horizon)
                   .includes(recurring_transaction: { merchant: { logo_attachment: :blob } })
                   .to_a
      preload_allocation_sums(list)
      list.select { |o| o.remaining_amount.to_d.positive? }
          .sort_by { |o| [ o.effective_due_on, o.recurring_transaction.typed_income? ? 0 : 1, o.recurring_transaction.display_name.to_s ] }
    end

    # One grouped query instead of a SUM per row (as BillsController does).
    def preload_allocation_sums(list)
      sums = RecurringAllocation.confirmed.where(recurring_occurrence_id: list.map(&:id))
                                .group(:recurring_occurrence_id).sum(:allocated_amount)
      list.each { |o| o.cached_confirmed_allocated = sums.fetch(o.id, 0) }
    end

    def to_family_currency(amount, currency)
      return amount.to_d if currency == family.currency

      Money.new(amount, currency).exchange_to(family.currency).amount
    rescue Money::ConversionError
      amount.to_d
    end
end
