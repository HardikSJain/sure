# India's new tax regime (FY 2025-26 onward) as it applies to a salary:
# slabs, the section 87A rebate with marginal relief, and 4% cess. Used to
# turn a yearly CTC into the monthly take-home a payslip shows.
module Projection::IndiaTax
  SLABS = [
    [ 400_000, "0" ], [ 800_000, "0.05" ], [ 1_200_000, "0.10" ], [ 1_600_000, "0.15" ],
    [ 2_000_000, "0.20" ], [ 2_400_000, "0.25" ], [ nil, "0.30" ]
  ].map { |top, rate| [ top, BigDecimal(rate) ] }.freeze
  STANDARD_DEDUCTION = 75_000
  REBATE_LIMIT = 1_200_000
  CESS = BigDecimal("0.04")

  module_function

  # Tax on a year's taxable salary. Up to the rebate limit it is zero; just
  # above it, marginal relief caps the tax at the income over the limit.
  def annual_tax(taxable)
    taxable = taxable.to_d
    return 0.to_d if taxable <= REBATE_LIMIT

    tax = [ slab_tax(taxable), taxable - REBATE_LIMIT ].min
    (tax * (1 + CESS)).round(2)
  end

  # The employer's PF is part of CTC but never paid out; the employee's PF
  # and any other deductions (professional tax and the like) come off the
  # gross. Neither PF side reduces taxable income in the new regime.
  def monthly_take_home(ctc:, employee_pf:, other_deductions:)
    gross = ctc.to_d - employee_pf.to_d
    taxable = [ gross - STANDARD_DEDUCTION, 0 ].max
    ((gross - annual_tax(taxable) - employee_pf.to_d - other_deductions.to_d) / 12).round(2)
  end

  def slab_tax(taxable)
    floor = 0
    SLABS.sum(0.to_d) do |top, rate|
      band = [ (top || taxable), taxable ].min - floor
      floor = top || taxable
      band.positive? ? band * rate : 0
    end
  end
end
