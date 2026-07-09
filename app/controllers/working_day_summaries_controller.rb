class WorkingDaySummariesController < ApplicationController
  before_action :authenticate_admin!

  REGULAR_DAILY_HOURS = 7.75
  HOURLY_DAILY_HOURS = 7.5
  CITY_HALL_REGULAR_DAILY_HOURS = 7.75
  CITY_HALL_HOURLY_DAILY_HOURS = 6.0

  def index
    @fiscal_year = params[:fiscal_year]&.to_i || current_fiscal_year
    @staffs = Staff.includes(:staff_type, :employment_type).order(:staff_type_id, :name)
    @active_tab = params[:tab] == "staff" ? "staff" : "monthly"

    months = fiscal_year_months(@fiscal_year)
    holidays = HolidayFetcher.fetch(@fiscal_year).merge(HolidayFetcher.fetch(@fiscal_year + 1))
    @n_by_month = months.index_with { |m| WorkingDayCalculator.new(m, holidays).regular_staff_days }
    @fiscal_months = months

    if @active_tab == "staff"
      @selected_staff = @staffs.find_by(id: params[:staff_id])
      build_staff_summary if @selected_staff
    else
      raw_month = params[:view_month].presence || months.first.strftime("%Y-%m")
      @view_month = Date.parse("#{raw_month}-01")
      build_monthly_all_staff_summary(months)
    end
  end

  private

  def current_fiscal_year
    today = Date.today
    today.month >= 4 ? today.year : today.year - 1
  end

  def fiscal_year_months(year)
    (4..12).map { |m| Date.new(year, m, 1) } +
    (1..3).map { |m| Date.new(year + 1, m, 1) }
  end

  def build_staff_summary
    regular = @selected_staff.employment_type.name == "正規職員"
    daily_hours = regular ? REGULAR_DAILY_HOURS : HOURLY_DAILY_HOURS
    city_hall_daily = regular ? CITY_HALL_REGULAR_DAILY_HOURS : CITY_HALL_HOURLY_DAILY_HOURS

    cumulative_diff = 0.0
    @summary = @fiscal_months.map do |month|
      n = @n_by_month[month]
      target_days = target_days_for(n, regular, daily_hours, city_hall_daily)
      target_hours = (target_days * daily_hours).round(2)
      city_hall_hours = (n * city_hall_daily).round(2)
      monthly_diff = (target_hours - city_hall_hours).round(2)
      cumulative_diff = (cumulative_diff + monthly_diff).round(2)

      { month: month, n: n, target_days: target_days, target_hours: target_hours,
        city_hall_hours: city_hall_hours, monthly_diff: monthly_diff, cumulative_diff: cumulative_diff }
    end
  end

  def build_monthly_all_staff_summary(months)
    months_up_to = months.select { |m| m <= @view_month }

    @staff_summaries = @staffs.map do |staff|
      regular = staff.employment_type.name == "正規職員"
      daily_hours = regular ? REGULAR_DAILY_HOURS : HOURLY_DAILY_HOURS
      city_hall_daily = regular ? CITY_HALL_REGULAR_DAILY_HOURS : CITY_HALL_HOURLY_DAILY_HOURS

      cumulative_target = 0.0
      cumulative_city_hall = 0.0
      months_up_to.each do |month|
        n = @n_by_month[month]
        target_days = target_days_for(n, regular, daily_hours, city_hall_daily)
        cumulative_target += target_days * daily_hours
        cumulative_city_hall += n * city_hall_daily
      end

      diff = (cumulative_target - cumulative_city_hall).round(2)
      { staff: staff, cumulative_target: cumulative_target.round(2),
        cumulative_city_hall: cumulative_city_hall.round(2), cumulative_diff: diff }
    end
  end

  def target_days_for(n, regular, daily_hours, city_hall_daily)
    return n if regular
    (n * city_hall_daily / daily_hours).floor
  end
end
