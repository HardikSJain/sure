require "test_helper"

class CashFloorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:depository)
  end

  test "sets the floor for an account and goes back" do
    patch account_cash_floor_path(@account), params: { cash_floor: { amount: "2500" } }

    assert_redirected_to bills_path
    assert_equal 2500, @user.reload.cash_floor(@account)
  end

  test "an account outside the family is not found" do
    patch account_cash_floor_path(SecureRandom.uuid), params: { cash_floor: { amount: "2500" } }

    assert_response :not_found
  end
end
