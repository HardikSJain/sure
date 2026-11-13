# The projection's assumptions as the user left them, stored in their
# preferences. Anything not set falls back to a default here, or (spending)
# to what the data says, worked out by the projection itself.
class Projection::Assumptions
  DEFAULTS = {
    "appraisal_pct" => 10, "return_pct" => 12, "spending_rise_pct" => 6,
    "employee_pf" => 0, "other_deductions" => 0
  }.freeze
  NUMBERS = %w[appraisal_pct return_pct spending spending_rise_pct goal_amount goal_year ctc employee_pf other_deductions].freeze
  RANGES = { "appraisal_pct" => 0..30, "return_pct" => 0..25, "spending_rise_pct" => 0..20 }.freeze
  # Zero means "not set" for these.
  UNSET_AT_ZERO = %w[goal_amount ctc].freeze
  GOAL_YEARS_AHEAD = 30

  attr_reader :user, :today

  def initialize(user, today: Date.current)
    @user = user
    @today = today
  end

  (NUMBERS - %w[goal_year]).each do |key|
    define_method(key) do
      raw = saved[key]
      raw ? BigDecimal(raw) : DEFAULTS[key]&.to_d
    end
  end

  def goal_year
    saved["goal_year"]&.to_i
  end

  def excluded
    Array(saved["excluded"])
  end

  # Takes form values (strings). Only keys present change: a blank one goes
  # back to its default, one that isn't a number is ignored, and one out of
  # range is clamped. `counted` lists the buckets that count.
  def update!(params)
    params = params.to_h.stringify_keys
    user.update_projection_assumptions! do |values|
      (NUMBERS & params.keys).each { |key| apply(values, key, params[key]) }
      if params.key?("counted")
        counted = Array(params["counted"]).map(&:to_s) & Projection::BUCKET_KEYS
        values["excluded"] = Projection::BUCKET_KEYS - counted
      end
    end
    @saved = nil
  end

  private
    def saved
      @saved ||= user.projection_assumptions
    end

    def apply(values, key, raw)
      text = raw.to_s.delete(", ").strip
      return values.delete(key) if text.empty?

      number = parse(text)
      return if number.nil?

      number = clamp(key, number)&.to_d
      if number.nil?
        values.delete(key)
      else
        values[key] = key == "goal_year" ? number.to_i.to_s : number.to_s("F")
      end
    end

    def parse(text)
      number = BigDecimal(text)
      number.finite? ? number : nil
    rescue ArgumentError
      nil
    end

    def clamp(key, number)
      if (range = RANGES[key])
        number.clamp(range.min, range.max)
      elsif key == "goal_year"
        number.round.clamp(today.year + 1, today.year + GOAL_YEARS_AHEAD)
      elsif UNSET_AT_ZERO.include?(key)
        number.positive? ? number : nil
      else
        [ number, 0 ].max
      end
    end
end
