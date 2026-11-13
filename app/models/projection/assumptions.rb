# The projection's assumptions as the user left them, stored in their
# preferences. Anything not set falls back to a default here, or (spending)
# to what the data says, worked out by the projection itself.
class Projection::Assumptions
  DEFAULTS = {
    "appraisal_pct" => 10, "return_pct" => 12, "spending_rise_pct" => 6,
    "employee_pf" => 0, "other_deductions" => 0
  }.freeze
  NUMBERS = %w[appraisal_pct return_pct spending spending_rise_pct goal_amount ctc employee_pf other_deductions].freeze
  RANGES = { "appraisal_pct" => 0..30, "return_pct" => 0..25, "spending_rise_pct" => 0..20 }.freeze
  # Zero means "not set" for these.
  UNSET_AT_ZERO = %w[goal_amount ctc].freeze
  # Anything bigger is a typo (or "1e400"), not an amount.
  MAX_AMOUNT = BigDecimal("1e15")

  attr_reader :user, :today

  def initialize(user, today: Date.current)
    @user = user
    @today = today
  end

  NUMBERS.each do |key|
    define_method(key) do
      raw = saved[key]
      raw ? BigDecimal(raw) : DEFAULTS[key]&.to_d
    end
  end

  # For showing age next to dates; nil when not given.
  def birth_date
    saved["birth_date"]&.then { |raw| Date.iso8601(raw) }
  rescue Date::Error
    nil
  end

  def excluded
    Array(saved["excluded"])
  end

  # Takes form values (strings). Only keys present change: a blank one goes
  # back to its default, one that isn't a number is ignored, and one out of
  # range is clamped. `counted` lists the buckets that count among those
  # `shown` on the form (all of them when not given); the rest keep their
  # setting, so a bucket that appears later isn't left out by accident.
  def update!(params)
    params = params.to_h.stringify_keys
    user.update_projection_assumptions! do |values|
      (NUMBERS & params.keys).each { |key| apply(values, key, params[key]) }
      apply_birth_date(values, params["birth_date"]) if params.key?("birth_date")
      if params.key?("counted")
        counted = Array(params["counted"]).map(&:to_s) & Projection::BUCKET_KEYS
        shown = params.key?("shown") ? Array(params["shown"]).map(&:to_s) & Projection::BUCKET_KEYS : Projection::BUCKET_KEYS
        values["excluded"] = Projection::BUCKET_KEYS & ((Array(values["excluded"]) - shown) | (shown - counted))
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
        values[key] = number.to_s("F")
      end
    end

    # A real date, not after today; blank clears it, anything else is ignored.
    def apply_birth_date(values, raw)
      text = raw.to_s.strip
      return values.delete("birth_date") if text.empty?

      date = Date.iso8601(text)
      values["birth_date"] = date.iso8601 if date <= today
    rescue Date::Error
      nil
    end

    def parse(text)
      number = BigDecimal(text)
      number.finite? && number.abs <= MAX_AMOUNT ? number : nil
    rescue ArgumentError
      nil
    end

    def clamp(key, number)
      if (range = RANGES[key])
        number.clamp(range.min, range.max)
      elsif UNSET_AT_ZERO.include?(key)
        number.positive? ? number : nil
      else
        [ number, 0 ].max
      end
    end
end
