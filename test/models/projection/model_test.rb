require "test_helper"

class Projection::ModelTest < ActiveSupport::TestCase
  setup do
    @m = Projection::Model.new(growing: 100_000, flat: 20_000, contributions: Array.new(24, 10_000), annual_return: 0.12)
  end

  test "compounds at the twelfth root of the annual rate, contributions at month end" do
    assert_in_delta 130_948.88, @m.values[0], 0.01
    assert_in_delta 258_464.98, @m.values[11], 0.01
    assert_in_delta 413_545.76, @m.values[23], 0.01
  end

  test "put in adds up the contributions" do
    assert_equal 240_000, @m.put_in(23)
  end

  test "extra a month is the smallest hundred that reaches the goal" do
    extra = @m.extra_needed(goal: 450_000, by: 23)
    assert_equal 0, extra % 100
    reach = ->(e) { Projection::Model.new(growing: 100_000, flat: 20_000, contributions: Array.new(24, 10_000 + e), annual_return: 0.12).values[23] }
    assert_operator reach.(extra), :>=, 450_000
    assert_operator reach.(extra - 100), :<, 450_000
    assert_equal 0, @m.extra_needed(goal: 400_000, by: 23)
  end

  test "crossing is the first month at or above the goal" do
    assert_equal 19, @m.crossing(350_000)
    assert_nil @m.crossing(10_000_000)
  end

  test "spending more than comes in draws the pot down" do
    m = Projection::Model.new(growing: 100_000, flat: 0, contributions: Array.new(12, -5_000), annual_return: 0.12)
    assert_operator m.values[11], :<, 100_000
    assert_operator m.values[11], :>, 0
  end

  test "EPF grows at its own rate with its own contributions" do
    m = Projection::Model.new(growing: 0, flat: 0, contributions: Array.new(49, 0), annual_return: 0.12,
                              epf: { balance: 0, monthly: 6_000, annual_rate: 0.0825 })
    assert_in_delta 346_016.47, m.values[48], 0.01
    assert_equal 294_000, m.put_in(48)
  end
end
