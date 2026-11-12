require "test_helper"

class Dashboard::NetWorthMixTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
  end

  test "shares add up to the whole within each bar" do
    m = mix
    [ m.assets, m.liabilities ].each do |segments|
      next if segments.empty?
      assert_in_delta 100, segments.sum(&:share), 0.5
    end
  end

  test "every other asset and every debt appears by name" do
    m = mix
    labels = (m.assets + m.liabilities).map(&:label)
    @family.accounts.visible.included_in_reports.where(accountable_type: %w[OtherAsset Property Vehicle CreditCard Loan OtherLiability]).each do |account|
      next unless account.balance.to_d.positive?
      assert_includes labels, account.name
    end
  end

  private
    def mix
      Dashboard::NetWorthMix.new(@family, investment_statement: InvestmentStatement.new(@family, user: @user),
                                          balance_sheet: @family.balance_sheet)
    end
end
