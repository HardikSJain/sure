# Today's money, in the buckets the projection counts: investments (they
# grow), EPF (its own rate), and bank cash, gold, money owed to you, other
# assets and debts (they stay flat). Only accounts the viewer can open, each
# in the family's currency. Debts come back positive; the projection
# subtracts them.
class Projection::StartingPoint
  Bucket = Data.define(:key, :amount)

  def initialize(family, user:)
    @family = family
    @user = user
  end

  def buckets
    @buckets ||= begin
      sums = Hash.new(0.to_d)
      accounts.each do |account|
        key = bucket_for(account)
        sums[key] += convert(account.balance, account.currency) if key
      end
      Projection::BUCKET_KEYS.filter_map do |key|
        Bucket.new(key: key, amount: sums[key].round(2)) if sums[key].positive?
      end
    end
  end

  def epf_account?
    accounts.any? { |a| bucket_for(a) == "epf" }
  end

  private
    attr_reader :family, :user

    def accounts
      @accounts ||= family.accounts.visible.included_in_reports
                          .merge(Account.accessible_by(user))
                          .includes(:accountable).to_a
    end

    def bucket_for(account)
      accountable = account.accountable
      case account.accountable_type
      when "Investment" then accountable.subtype == "epf" ? "epf" : "investments"
      when "Crypto" then "investments"
      when "Depository" then "bank"
      when "OtherAsset"
        { "precious_metal" => "gold", "receivable" => "owed" }.fetch(accountable.subtype.to_s, "other")
      when "Property", "Vehicle" then "other"
      when "CreditCard", "Loan", "OtherLiability" then "debts"
      end
    end

    def convert(amount, currency)
      return amount.to_d if currency.blank? || currency == family.currency

      Money.new(amount, currency).exchange_to(family.currency).amount
    rescue Money::ConversionError
      amount.to_d
    end
end
