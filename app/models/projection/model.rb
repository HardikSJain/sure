# The arithmetic of a projection: what today's money and each month's
# contribution grow to at one annual return. Pure numbers, no records.
#
#   growing        today's investments; they compound
#   flat           bank cash, gold, money owed, other assets less debts;
#                  they stay where they are
#   contributions  what goes in at the end of each month (negative when
#                  spending is more than comes in); they compound too
#   epf            optional { balance:, monthly:, annual_rate: }, its own pot
#
# The annual return becomes a monthly rate as (1 + r) ** (1/12) - 1, so twelve
# months of it are exactly r.
class Projection::Model
  STEP = 100

  def initialize(growing:, flat:, contributions:, annual_return:, epf: nil)
    @growing = growing.to_f
    @flat = flat.to_f
    @contributions = contributions.map(&:to_f)
    @rate = self.class.monthly_rate(annual_return)
    @epf = epf && { balance: epf[:balance].to_f, monthly: epf[:monthly].to_f, rate: self.class.monthly_rate(epf[:annual_rate]) }
  end

  def self.monthly_rate(annual)
    (1 + annual.to_f)**(1.0 / 12) - 1
  end

  # End-of-month total for each month.
  def values
    @values ||= begin
      pot = growing
      fresh = 0.0
      epf_pot = epf ? epf[:balance] : 0.0
      contributions.map do |amount|
        pot *= 1 + rate
        fresh = fresh * (1 + rate) + amount
        epf_pot = epf_pot * (1 + epf[:rate]) + epf[:monthly] if epf
        (pot + fresh + epf_pot + flat).to_d.round(2)
      end
    end
  end

  # Money put in through month `index`: contributions plus EPF contributions.
  def put_in(index)
    total = contributions.first(index + 1).sum + (epf ? epf[:monthly] * (index + 1) : 0)
    total.to_d.round(2)
  end

  # The smallest constant monthly addition, from the first month, that brings
  # month `by` to the goal: rounded up to the next STEP, so it really does.
  def extra_needed(goal:, by:)
    shortfall = goal.to_f - values[by].to_f
    return 0.to_d unless shortfall.positive?

    months = by + 1
    factor = rate.zero? ? months : ((1 + rate)**months - 1) / rate
    ((shortfall / factor / STEP).ceil * STEP).to_d
  end

  # Index of the first month at or above the goal.
  def crossing(goal)
    values.index { |v| v >= goal.to_d }
  end

  private
    attr_reader :growing, :flat, :contributions, :rate, :epf
end
