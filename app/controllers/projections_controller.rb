class ProjectionsController < ApplicationController
  def show
    @projection = Projection.new(Current.family, user: Current.user)
    year = params[:year].to_i
    @year = @projection.years.cover?(year) ? year : @projection.default_year
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("projections.show.title"), nil ] ]
  end

  def update
    Projection::Assumptions.new(Current.user).update!(assumption_params)
    redirect_to projection_path(year: params[:year].presence)
  end

  private
    def assumption_params
      params.fetch(:projection, {}).permit(
        :appraisal_pct, :return_pct, :spending, :spending_rise_pct, :goal_amount, :birth_date,
        :ctc, :employee_pf, :other_deductions, counted: []
      )
    end
end
