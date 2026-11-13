# Builders for the projection's tests: accounts of each kind on a family,
# declared bills (the way the add-bill form makes them) and spending lines.
module ProjectionTestHelper
  ACCOUNTABLES = {
    depository: Depository, investment: Investment, crypto: Crypto, other_asset: OtherAsset,
    loan: Loan, credit_card: CreditCard
  }.freeze

  def create_account(family, type, balance:, currency: family.currency, owner: nil, subtype: nil, name: nil)
    accountable = ACCOUNTABLES.fetch(type).new
    accountable.subtype = subtype if subtype
    family.accounts.create!(name: name || "#{type.to_s.humanize} #{SecureRandom.hex(3)}", balance: balance,
                            currency: currency, owner: owner || @user || family.users.first, accountable: accountable, status: "active")
  end

  def declare_bill(account, user:, name:, amount:, first_due_on:, frequency_preset: "monthly", is_income: false, end_after_count: nil)
    attrs = { name: name, amount: amount, account_id: account.id, first_due_on: first_due_on.to_s,
              frequency_preset: frequency_preset, is_income: is_income }
    bill = RecurringTransaction::DeclaredBill.new(family: account.family, user: user, attrs: attrs).build
    if end_after_count
      bill.end_mode = "after_count"
      bill.end_after_count = end_after_count
    end
    bill.save!
    bill
  end

  def spend(account, amount, date:, category: nil)
    account.entries.create!(name: "Spend", date: date, amount: amount, currency: account.currency,
                            entryable: Transaction.new(kind: "standard", category: category))
  end
end
