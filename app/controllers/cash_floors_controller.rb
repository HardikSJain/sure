# Sets the least a bank account should hold, which the room forecast on the
# Bills page and the dashboard warns below.
class CashFloorsController < ApplicationController
  def update
    account = Account.writable_by(Current.user).find(params[:account_id])
    Current.user.update_cash_floor!(account, params.dig(:cash_floor, :amount))

    redirect_back_or_to bills_path, status: :see_other
  end
end
