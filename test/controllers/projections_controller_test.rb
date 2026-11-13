require "test_helper"
require Rails.root.join("test/support/projection_test_helper").to_s

class ProjectionsControllerTest < ActionDispatch::IntegrationTest
  include ProjectionTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @bank = create_account(@family, :depository, balance: 5_000, owner: @user)
    declare_bill(@bank, user: @user, name: "Pay", amount: 8_000, first_due_on: Date.current.next_month.beginning_of_month, is_income: true)
    spend(@bank, 3_000, date: Date.current.prev_month.beginning_of_month)
  end

  test "shows the headline, the band and the chart" do
    get projection_path
    assert_response :success
    assert_select "turbo-frame#projection"
    assert_select "[data-controller~='projection-chart'] svg"
    assert_match(/depending on markets/, response.body)
  end

  test "chart labels are page text, so they stay readable on a phone" do
    get projection_path
    assert_select "[data-controller~='projection-chart'] svg text", count: 0
    assert_select "[data-projection-chart-labels] span", minimum: 3
  end

  test "the breadcrumb and every field have their words" do
    get projection_path
    assert_select "[data-breadcrumbs] span", text: "Where you're headed"
    assert_select "label", text: "Spending rise each April (%)"
    assert_select "span.translation_missing", count: 0
  end

  test "the year switcher moves the headline; a year out of range falls back" do
    get projection_path(year: Date.current.year + 3)
    assert_select "p", text: /Net worth by Dec #{Date.current.year + 3}/
    get projection_path(year: 1999)
    assert_response :success
  end

  test "saving an assumption keeps it" do
    patch projection_path, params: { projection: { appraisal_pct: "8" } }
    assert_redirected_to projection_path
    assert_equal 8, Projection::Assumptions.new(@user.reload).appraisal_pct
  end

  test "junk in the form changes nothing and doesn't break the page" do
    patch projection_path, params: { projection: { appraisal_pct: "abc", birth_date: "nonsense" } }
    assert_response :redirect
    assert_equal 10, Projection::Assumptions.new(@user.reload).appraisal_pct
    follow_redirect!
    assert_response :success
  end

  test "a spending figure the user set can go back to the average" do
    @bank.entries.create!(name: "Spend", date: Date.current.prev_month.beginning_of_month, amount: 3_000, currency: @bank.currency,
                          entryable: Transaction.new(kind: "standard"))
    get projection_path
    assert_select "button[name='projection[spending]']", count: 0

    Projection::Assumptions.new(@user).update!(spending: "5000")
    get projection_path
    assert_select "button[name='projection[spending]'][value='']", text: "Use my average"
  end

  test "Enter in a field never presses Use my average, and the average stays private" do
    @bank.entries.create!(name: "Spend", date: Date.current.prev_month.beginning_of_month, amount: 3_000, currency: @bank.currency,
                          entryable: Transaction.new(kind: "standard"))
    Projection::Assumptions.new(@user).update!(spending: "5000")
    get projection_path
    first_submit = css_select("form[action^='/projection'] button[type=submit], form[action^='/projection'] input[type=submit]").first
    assert_nil first_submit["name"]
    assert_select "p.privacy-sensitive", text: /Your recent average is/
    assert_select "input[name='projection[shown][]']", minimum: 1
  end

  test "unticking every bucket leaves them all out" do
    patch projection_path, params: { projection: { counted: [ "" ] } }
    assert_equal Projection::BUCKET_KEYS, Projection::Assumptions.new(@user.reload).excluded
  end

  test "a goal shows when it's reached, the ring and ways to get there sooner" do
    @bank.entries.create!(name: "Spend", date: Date.current.prev_month.beginning_of_month, amount: 3_000, currency: @bank.currency,
                          entryable: Transaction.new(kind: "standard"))
    Projection::Assumptions.new(@user).update!(goal_amount: "500000", birth_date: "1990-06-15")
    get projection_path
    assert_select "[data-projection-goal]"
    assert_match(/You reach/, response.body)
    assert_select "[data-projection-sooner] li", minimum: 1
    assert_match(/at \d\d/, response.body)
  end

  test "no spending to go on asks for it instead of projecting" do
    @family.entries.where(entryable_type: "Transaction").destroy_all
    get projection_path
    assert_response :success
    assert_match(/no spending history/, response.body)
    assert_select "[data-controller~='projection-chart']", count: 0
  end

  test "no salary and no CTC asks for one instead of projecting" do
    @family.recurring_transactions.where(bill_type: "income").destroy_all
    get projection_path
    assert_response :success
    assert_match(/Add your salary/, response.body)
    assert_select "[data-controller~='projection-chart']", count: 0
  end
end
