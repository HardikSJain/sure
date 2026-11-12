# Everything the room forecast expects to hit a bank account between `from`
# (the day after its last-known date) and `through`: bills and income attached
# to it, card bills at their statement amount, transfers in, top-ups it will
# have to send to a wallet, and lines already known to have moved but not yet
# on its statement (pending).
#
# Which bills count: the balance is only known up to the last-known date, and
# a bill's "paid" status is not proof the payment is in that balance (the
# matcher often can't see statement payments). So an occurrence due on or
# before the last-known date is taken as already in the balance; one due after
# counts whatever its status, less any confirmed payment dated on or before the
# last-known date. Skipped and missed occurrences never count.
class CashForecast::Events
  # A card's statement is generated this many days or fewer before its bill is
  # due; a card known up to then has the bill's real amount as its balance.
  STATEMENT_LEAD_DAYS = 25
  WALLET_TYPES = %w[Investment Crypto].freeze

  # Latest non-pending entry date on an account (statement balances included),
  # never after today.
  def self.last_known_date(account, today: Date.current)
    account.entries.excluding_pending.where(date: ..today).maximum(:date) || today
  end

  def initialize(account, from:, through:, user: nil)
    @account = account
    @from = from
    @through = through
    @user = user
  end

  def to_a
    @to_a ||= (occurrence_events + pending_events + top_up_events)
      .sort_by { |e| [ e.date, e.inflow? ? 0 : 1, e.name.to_s ] }
  end

  private
    attr_reader :account, :from, :through, :user

    # Accounts the viewer can't open are never named (another member's card
    # or wallet); their amounts still count.
    def visible?(other)
      user.nil? || Account.accessible_by(user).exists?(other.id)
    end

    def family
      account.family
    end

    def last_known
      from - 1
    end

    def occurrence_events
      series = family.recurring_transactions.where(status: "active")
                     .where("account_id = :id OR destination_account_id = :id", id: account.id)
      counted_occurrences(series, after: last_known).filter_map do |occurrence, amount|
        event_for(occurrence, amount)
      end
    end

    # [occurrence, amount still to hit the balance] for occurrences of `series`
    # due after `after` and on or before `through`.
    def counted_occurrences(series, after:)
      occurrences = RecurringOccurrence.where(recurring_transaction_id: series.select(:id))
                                       .where.not(status: %w[skipped missed])
                                       .where("#{RecurringOccurrence::EFFECTIVE_DUE_ON_SQL} > ? AND #{RecurringOccurrence::EFFECTIVE_DUE_ON_SQL} <= ?", after, through)
                                       .includes(recurring_transaction: :destination_account)
                                       .to_a
      known_payments = RecurringAllocation.confirmed
                                          .joins("JOIN entries ON entries.id = recurring_allocations.entry_id")
                                          .where(recurring_occurrence_id: occurrences.map(&:id))
                                          .where("entries.date <= ?", after)
                                          .group(:recurring_occurrence_id)
                                          .sum(:allocated_amount)
      occurrences.filter_map do |occurrence|
        amount = occurrence.resolved_expected_amount.to_d - known_payments.fetch(occurrence.id, 0).to_d
        [ occurrence, to_account_currency(amount, occurrence.currency) ] if amount.positive?
      end
    end

    def event_for(occurrence, amount)
      series = occurrence.recurring_transaction
      date = occurrence.effective_due_on
      name = series.display_name

      if series.destination_account_id == account.id
        build(date, name, amount, :transfer_in, source: occurrence)
      elsif series.typed_income? || series.amount.negative?
        build(date, name, amount, :income, source: occurrence)
      elsif series.destination_account&.accountable_type == "CreditCard"
        card_bill(occurrence, series.destination_account, amount, date, name)
      else
        build(date, name, -amount, :bill, source: occurrence)
      end
    end

    # The bill is the card's statement balance (a valuation dated in the
    # statement window before the due date), less anything paid to the card
    # since. Without a statement in that window, it's the declared amount,
    # marked as an estimate.
    def card_bill(occurrence, card, declared, date, name)
      statement = card.entries.where(entryable_type: "Valuation", date: (date - STATEMENT_LEAD_DAYS)..(date - 1))
                      .order(date: :desc).first
      return build(date, name, -declared, :card_bill, estimate: true, source: occurrence) unless statement

      paid_since = card.entries.excluding_pending
                       .joins("JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
                       .where(date: (statement.date + 1)..date, transactions: { kind: %w[funds_movement cc_payment] })
                       .where("entries.amount < 0")
                       .sum(:amount).abs
      owed = to_account_currency(statement.amount.to_d - paid_since, card.currency)
      return nil unless owed.positive?

      build(date, name, -owed, :card_bill, source: occurrence)
    end

    def pending_events
      pending = account.entries.where(entryable_type: "Transaction", date: from..through)
                       .where.not(id: account.entries.excluding_pending.select(:id))
      pending.map do |entry|
        build(entry.date, entry.name, -to_account_currency(entry.amount, entry.currency), :pending, source: entry)
      end
    end

    # A bill paid from a wallet (an investment account's cash) only touches
    # this account when the wallet can't cover it, and only if this account is
    # the one that tops that wallet up. Money due into the wallet (income on
    # it, transfers to it) fills it first.
    def top_up_events
      wallet_ids = family.recurring_transactions.where(status: "active", destination_account_id: nil).select(:account_id)
      family.accounts.where(accountable_type: WALLET_TYPES, id: wallet_ids).flat_map do |wallet|
        funding_bank(wallet) == account ? wallet_top_ups(wallet) : []
      end
    end

    def wallet_top_ups(wallet)
      cash = to_account_currency(wallet.cash_balance.to_d, wallet.currency)
      series = family.recurring_transactions.where(status: "active")
                     .where("account_id = :id OR destination_account_id = :id", id: wallet.id)
      flows = counted_occurrences(series, after: self.class.last_known_date(wallet)).map do |occurrence, amount|
        [ occurrence, wallet_inflow?(occurrence.recurring_transaction, wallet) ? amount : -amount ]
      end
      name = visible?(wallet) ? "Top up #{wallet.name}" : I18n.t("cash_forecast.top_up_wallet", default: "Top up a wallet")
      flows.sort_by { |occurrence, flow| [ occurrence.effective_due_on, flow.positive? ? 0 : 1 ] }.filter_map do |occurrence, flow|
        if flow.positive? || -flow <= cash
          cash += flow
          nil
        else
          short = -flow - cash
          cash = 0
          date = occurrence.effective_due_on
          build(date, name, -short, :top_up, source: wallet) if date >= from
        end
      end
    end

    def wallet_inflow?(series, wallet)
      series.destination_account_id == wallet.id || series.typed_income? || series.amount.negative?
    end

    # The account that most recently sent money into the wallet.
    def funding_bank(wallet)
      @funding_banks ||= {}
      return @funding_banks[wallet.id] if @funding_banks.key?(wallet.id)

      transfer = Transfer.confirmed
                         .joins(inflow_transaction: :entry)
                         .where(entries: { account_id: wallet.id })
                         .order("entries.date DESC")
                         .first
      @funding_banks[wallet.id] = transfer&.outflow_transaction&.entry&.account
    end

    def balance_on(card, date)
      card.balances.where(currency: card.currency, date: ..date).order(date: :desc).pick(:end_balance) || card.balance
    end

    def build(date, name, amount, kind, source:, estimate: false)
      CashForecast::Event.new(date: date, name: name, amount: amount.to_d, kind: kind, estimate: estimate, source: source)
    end

    def to_account_currency(amount, currency)
      return amount.to_d if currency.blank? || currency == account.currency

      Money.new(amount, currency).exchange_to(account.currency).amount
    rescue Money::ConversionError
      amount.to_d
    end
end
