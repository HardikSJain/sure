# Monthly take-home from here on. Today's salary holds until the first April
# (a new tax year) or June (the appraisal) after today; from then on it is
# the CTC in effect through the tax formula, or, without a CTC, today's
# salary raised by each June's appraisal.
class Projection::TakeHome
  Change = Data.define(:month, :amount, :reason)

  def initialize(current:, ctc:, employee_pf:, other_deductions:, appraisal:, today:)
    @current = current&.to_d
    @ctc = ctc&.to_d
    @employee_pf = employee_pf.to_d
    @other_deductions = other_deductions.to_d
    @appraisal = BigDecimal(appraisal.to_s)
    @today = today
  end

  def for(month)
    month = month.beginning_of_month
    return current.round(2) if current && month < first_switch

    raise_by = (1 + appraisal)**junes_through(month)
    if ctc
      Projection::IndiaTax.monthly_take_home(ctc: ctc * raise_by, employee_pf: employee_pf, other_deductions: other_deductions)
    else
      (current.to_d * raise_by).round(2)
    end
  end

  # Each month the take-home moves, with why: the first month is :now.
  def changes(months)
    previous = nil
    months.filter_map do |month|
      amount = self.for(month)
      change = if previous.nil?
        Change.new(month: month.beginning_of_month, amount: amount, reason: :now)
      elsif amount != previous
        Change.new(month: month.beginning_of_month, amount: amount, reason: month.month == 6 ? :appraisal : :new_tax_year)
      end
      previous = amount
      change
    end
  end

  private
    attr_reader :current, :ctc, :employee_pf, :other_deductions, :appraisal, :today

    def first_month
      today.beginning_of_month.next_month
    end

    def first_switch
      @first_switch ||= begin
        month = first_month
        month = month.next_month until [ 4, 6 ].include?(month.month)
        month
      end
    end

    # Junes after today's month, up to and including `month`.
    def junes_through(month)
      (first_month.year..month.year).count do |year|
        june = Date.new(year, 6, 1)
        june >= first_month && june <= month
      end
    end
end
