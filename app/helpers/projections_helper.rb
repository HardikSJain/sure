module ProjectionsHelper
  # A money amount in a few characters, for headlines and chart labels:
  # lakh and crore where amounts are grouped the Indian way ("₹45.6 L",
  # "₹2.34 Cr"), K, M and B elsewhere ("$250K"). Three significant digits.
  # Below a lakh (or a thousand) the whole amount shows.
  def compact_money(money, symbol: true)
    amount = money.amount.to_d
    units = indian_units?(money) ? [ [ 10_000_000, " Cr" ], [ 100_000, " L" ] ] : [ [ 1_000_000_000, "B" ], [ 1_000_000, "M" ], [ 1_000, "K" ] ]
    scale, suffix = units.find { |size, _| amount.abs >= size }
    return money.format(precision: 0) unless scale

    value = amount.abs / scale
    digits = [ 3 - value.round.to_i.to_s.length, 0 ].max
    text = value.round(digits).to_d.to_s("F").sub(/\.?0+\z/, "")
    "#{"-" if amount.negative?}#{money.currency.symbol if symbol}#{text}#{suffix}"
  end

  private
    def indian_units?(money)
      Money::Formatting::INDIAN_GROUPING_CURRENCIES.include?(money.currency.iso_code) ||
        Money::Formatting::INDIAN_LOCALES.include?(I18n.locale.to_sym)
    end
end
