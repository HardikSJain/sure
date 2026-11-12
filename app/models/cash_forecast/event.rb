# One thing the room forecast expects to happen to a bank account's balance.
#
#   amount   signed, in the account's currency: + money in, - money out
#   kind     :bill, :income, :card_bill, :transfer_in, :top_up or :pending
#   estimate true when the amount is a declared guess (a card bill before its
#            statement is in)
#   source   the occurrence, entry or wallet account it came from
CashForecast::Event = Data.define(:date, :name, :amount, :kind, :estimate, :source) do
  def inflow? = amount.positive?
end
