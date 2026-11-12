# One way to make room before a tight day (see CashForecast::Suggestions).
# `balance_if` is what the low point becomes if this happens (or doesn't, for
# an income the low point depends on); nil when it doesn't apply.
CashForecast::Suggestion = Data.define(:kind, :name, :amount, :date, :balance_if)
