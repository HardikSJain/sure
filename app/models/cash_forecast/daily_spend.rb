# Everyday spending paid straight from a bank account (autos, chai, UPI to
# people): what bills don't capture but drains the balance every day. The
# average daily outflow over the WINDOW_DAYS ending on `through`, leaving out
# big one-offs, transfers and lines that paid a bill (those are forecast
# separately).
class CashForecast::DailySpend
  WINDOW_DAYS = 90
  # Single lines above this, in the account's currency, are one-offs, not habit.
  ONE_OFF_ABOVE = 5_000

  def initialize(account, through:)
    @account = account
    @through = through
  end

  def amount
    @amount ||= (lines.sum(:amount) / WINDOW_DAYS).round(4)
  end

  private
    attr_reader :account, :through

    def lines
      account.entries
             .excluding_pending
             .joins("JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
             .where(date: (through - (WINDOW_DAYS - 1))..through, excluded: false)
             .where("entries.amount > 0 AND entries.amount <= ?", ONE_OFF_ABOVE)
             .where(transactions: { kind: "standard" })
             .where.not(id: RecurringAllocation.confirmed.where.not(entry_id: nil).select(:entry_id))
    end
end
