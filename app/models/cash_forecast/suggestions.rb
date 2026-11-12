# Ways to make room before a tight day, worked out from the data. These are
# options to weigh, not advice, and by design never touch investing: no
# "pause a SIP", no "pull money from the wallet". Only:
#
#   :move_due_date     a card bill due just before payday (moving its due date
#                      after payday fixes the squeeze for good)
#   :receivable        money owed to you that isn't already coming back on a
#                      schedule
#   :income_dependency money due in before the low point; if it's late, the low
#                      point falls by that much
#   :wallet_top_up     money the bank will send a wallet, so it's no surprise
class CashForecast::Suggestions
  # A card bill due this close before payday is the squeeze.
  DAYS_BEFORE_PAYDAY = 5

  def initialize(forecast)
    @forecast = forecast
  end

  def for(low_point)
    move_due_dates(low_point) + receivables(low_point) + income_dependencies(low_point) + wallet_top_ups
  end

  private
    attr_reader :forecast

    def move_due_dates(low)
      return [] unless low.next_payday

      low.events_before
         .select { |e| e.kind == :card_bill && e.date >= low.next_payday - DAYS_BEFORE_PAYDAY }
         .map do |e|
           card = e.source.recurring_transaction.destination_account
           suggestion(:move_due_date, card.name, -e.amount, e.date, low.balance - e.amount)
         end
    end

    def receivables(low)
      family = forecast.account.family
      on_schedule = family.recurring_transactions.where(status: "active").where.not(destination_account_id: nil)
                          .select(:account_id)
      family.accounts.visible
            .where(accountable_type: "OtherAsset")
            .joins("JOIN other_assets ON other_assets.id = accounts.accountable_id")
            .where(other_assets: { subtype: "receivable" })
            .where("accounts.balance > 0")
            .where.not(id: on_schedule)
            .order(:name)
            .map { |a| suggestion(:receivable, a.name, a.balance.to_d, nil, low.balance + a.balance.to_d) }
    end

    def income_dependencies(low)
      low.events_before.select { |e| e.kind.in?(%i[income transfer_in]) }.map do |e|
        suggestion(:income_dependency, e.name, e.amount, e.date, low.balance - e.amount)
      end
    end

    def wallet_top_ups
      forecast.events.select { |e| e.kind == :top_up }.map do |e|
        suggestion(:wallet_top_up, e.name, -e.amount, e.date, nil)
      end
    end

    def suggestion(kind, name, amount, date, balance_if)
      CashForecast::Suggestion.new(kind: kind, name: name, amount: amount, date: date, balance_if: balance_if)
    end
end
