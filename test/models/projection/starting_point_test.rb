require "test_helper"
require Rails.root.join("test/support/projection_test_helper").to_s

class Projection::StartingPointTest < ActiveSupport::TestCase
  include ProjectionTestHelper

  setup do
    @user = users(:empty)
    @family = @user.family
    @family.update!(currency: "USD")
  end

  test "groups accounts the way the projection counts them" do
    create_account(@family, :depository, balance: 50_000)
    create_account(@family, :investment, balance: 300_000)
    create_account(@family, :investment, balance: 40_000, subtype: "epf")
    create_account(@family, :other_asset, balance: 20_000, subtype: "precious_metal")
    create_account(@family, :other_asset, balance: 10_000, subtype: "receivable")
    create_account(@family, :loan, balance: 15_000)
    assert_equal({ "investments" => 300_000, "epf" => 40_000, "bank" => 50_000, "gold" => 20_000, "owed" => 10_000, "debts" => 15_000 },
                 point.buckets.to_h { |b| [ b.key, b.amount ] })
    assert point.epf_account?
  end

  test "converts other currencies to the family's" do
    ExchangeRate.create!(from_currency: "EUR", to_currency: "USD", date: Date.current, rate: 2)
    create_account(@family, :investment, balance: 100, currency: "EUR")
    assert_equal 200, point.buckets.find { |b| b.key == "investments" }.amount
  end

  test "leaves out another member's private accounts" do
    other = @family.users.create!(email: "member-projection@example.com", password: "password123A!", role: "member",
                                  first_name: "M", last_name: "P")
    create_account(@family, :depository, balance: 9_000, owner: other)
    assert_nil point.buckets.find { |b| b.key == "bank" }
    assert_not point.epf_account?
  end

  private
    def point
      Projection::StartingPoint.new(@family, user: @user)
    end
end
