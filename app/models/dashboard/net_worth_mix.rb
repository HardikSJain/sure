# Everything the family owns and owes, split the way a person thinks about it:
# bank cash, stocks, funds, money abroad, cash sitting at brokers, then each
# other asset and each debt by name. One bar for assets, one for debts.
class Dashboard::NetWorthMix
  Segment = Data.define(:key, :label, :amount, :share, :color, :detail)

  # Holdings buckets, in display order, with their bar colors.
  HOLDING_BUCKETS = {
    "stocks" => "var(--color-blue-500)",
    "etfs" => "var(--color-cyan-500)",
    "mutual_funds" => "var(--color-violet-500)",
    "international" => "var(--color-fuchsia-500)",
    "other_investments" => "var(--color-indigo-500)"
  }.freeze
  OTHER_ASSET_COLORS = %w[var(--color-yellow-500) var(--color-orange-500) var(--color-pink-500) var(--color-green-500)].freeze

  attr_reader :family

  def initialize(family, investment_statement:, balance_sheet:)
    @family = family
    @investment_statement = investment_statement
    @balance_sheet = balance_sheet
  end

  def net_worth
    @balance_sheet.net_worth_money
  end

  def assets
    @assets ||= with_shares(bank_cash_segments + holding_segments + broker_cash_segments + other_asset_segments)
  end

  def liabilities
    @liabilities ||= with_shares(liability_segments, color_cycle: %w[var(--color-red-500) var(--color-orange-500) var(--color-pink-500)])
  end

  def total_assets
    money(assets.sum { |s| s.amount.amount })
  end

  def total_liabilities
    money(liabilities.sum { |s| s.amount.amount })
  end

  # Invested positions: what they cost and what they are worth now.
  def holdings_value
    money(holdings.sum { |h| convert(h.amount, h.currency) })
  end

  def holdings_gain
    gains = @investment_statement.unrealized_gains_trend
    gains && money(gains.value)
  end

  def any?
    assets.any? || liabilities.any?
  end

  private
    def holdings
      @holdings ||= @investment_statement.current_holdings.to_a
    end

    def bank_cash_segments
      amount = accounts("Depository").sum { |a| convert(a.balance, a.currency) }
      amount.positive? ? [ segment("bank_cash", I18n.t("pages.dashboard.net_worth_mix.bank_cash"), amount, "var(--color-green-500)") ] : []
    end

    def holding_segments
      grouped = holdings.group_by { |h| holding_bucket(h) }
      HOLDING_BUCKETS.filter_map do |bucket, color|
        list = grouped[bucket]
        next unless list

        amount = list.sum { |h| convert(h.amount, h.currency) }
        detail = I18n.t("pages.dashboard.net_worth_mix.positions", count: list.map(&:security_id).uniq.size)
        segment(bucket, I18n.t("pages.dashboard.net_worth_mix.#{bucket}"), amount, color, detail) if amount.positive?
      end
    end

    def broker_cash_segments
      amount = @investment_statement.investment_accounts.sum { |a| [ convert(a.cash_balance, a.currency), 0 ].max }
      amount.positive? ? [ segment("broker_cash", I18n.t("pages.dashboard.net_worth_mix.broker_cash"), amount, "var(--color-gray-500)") ] : []
    end

    # Property, vehicles and other assets: each account on its own, by name.
    # (Crypto accounts are in the investment statement, with the holdings.)
    def other_asset_segments
      list = family.accounts.visible.included_in_reports
                   .where(accountable_type: %w[OtherAsset Property Vehicle])
                   .order(:name).to_a
      list.each_with_index.filter_map do |a, i|
        amount = convert(a.balance, a.currency)
        segment("account-#{a.id}", a.name, amount, OTHER_ASSET_COLORS[i % OTHER_ASSET_COLORS.size]) if amount.positive?
      end
    end

    def liability_segments
      family.accounts.visible.included_in_reports
            .where(accountable_type: %w[CreditCard Loan OtherLiability])
            .order(:name).to_a
            .filter_map do |a|
              amount = convert(a.balance, a.currency)
              segment("account-#{a.id}", a.name, amount, nil) if amount.positive?
            end
    end

    def holding_bucket(holding)
      security = holding.security
      return "international" if security.country_code.present? && family.country.present? && security.country_code != family.country

      case security.asset_sub_class
      when "stock" then "stocks"
      when "etf" then "etfs"
      when "mutual_fund" then "mutual_funds"
      else "other_investments"
      end
    end

    def accounts(type)
      family.accounts.visible.included_in_reports.where(accountable_type: type)
    end

    def segment(key, label, amount, color, detail = nil)
      Segment.new(key: key, label: label, amount: money(amount), share: 0, color: color, detail: detail)
    end

    def with_shares(segments, color_cycle: nil)
      total = segments.sum { |s| s.amount.amount }
      segments = segments.sort_by { |s| -s.amount.amount } if color_cycle
      segments.each_with_index.map do |s, i|
        s.with(share: total.positive? ? (s.amount.amount / total * 100).round(1) : 0,
               color: s.color || color_cycle[i % color_cycle.size])
      end
    end

    def convert(amount, currency)
      return amount.to_d if currency.blank? || currency == family.currency

      Money.new(amount, currency).exchange_to(family.currency).amount
    rescue Money::ConversionError
      amount.to_d
    end

    def money(amount)
      Money.new(amount || 0, family.currency)
    end
end
