# Builders for the room forecast's tests: a fresh bank account (so fixture
# entries don't leak into averages), spending lines, bills and a statement
# balance that sets the account's last-known date.
module CashForecastTestHelper
  def create_bank(name: "Forecast bank", balance: 1000, family: families(:dylan_family))
    family.accounts.create!(name: name, balance: balance, currency: family.currency, owner: users(:family_admin),
                            accountable: Depository.new, status: "active")
  end

  def spend(account, amount, date:, kind: "standard", extra: {}, **entry_attrs)
    account.entries.create!({ name: "Spend", date: date, amount: amount, currency: account.currency,
                              entryable: Transaction.new(kind: kind, extra: extra) }.merge(entry_attrs))
  end

  def known_until(account, date, balance)
    account.entries.create!(name: "Statement balance", date: date, amount: balance, currency: account.currency,
                            entryable: Valuation.new(kind: "reconciliation"))
  end

  def create_series(account, name:, amount:, due:, **overrides)
    account.family.recurring_transactions.create!({
      account: account, name: name, amount: amount, dedup_scope: "#{name}-#{amount}", currency: account.currency,
      expected_day_of_month: due.day, anchor_date: due, last_occurrence_date: due.prev_month,
      next_expected_date: due, status: "active", manual: true
    }.merge(overrides))
  end
end
