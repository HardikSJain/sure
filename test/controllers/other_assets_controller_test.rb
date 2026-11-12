require "test_helper"

class OtherAssetsControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:other_asset)
  end

  test "an other asset can be marked as money owed or gold" do
    patch other_asset_path(@account), params: { account: { subtype: "receivable" } }

    assert_equal "receivable", @account.reload.accountable.subtype
  end

  test "the form offers money owed and gold" do
    get edit_other_asset_path(@account)

    assert_select "select[name='account[subtype]'] option[value='receivable']"
  end
end
