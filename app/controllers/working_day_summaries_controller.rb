class WorkingDaySummariesController < ApplicationController
  before_action :authenticate_admin!

  REGULAR_DAILY_HOURS = 7.75
  HOURLY_DAILY_HOURS = 7.5
  CITY_HALL_REGULAR_DAILY_HOURS = 7.75
  CITY_HALL_HOURLY_DAILY_HOURS = 6.0

  def index
    @fiscal_year = params[:fiscal_year]&.to_i || current_fiscal_year
    @staffs = current_library.staffs.includes(:staff_type, :employment_type).order(:staff_type_id, :name)
    @active_tab = params[:tab] == "staff" ? "staff" : "monthly"

    months = fiscal_year_months(@fiscal_year)
    holidays = HolidayFetcher.fetch(@fiscal_year).merge(HolidayFetcher.fetch(@fiscal_year + 1))
    @n_by_month = months.index_with { |m| WorkingDayCalculator.new(m, holidays).regular_staff_days }
    @fiscal_months = months

    preload_actual_data(months)

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

  def preload_actual_data(months)
    start_date = months.first
    end_date = months.last

    manual_entries = WorkdayManualEntry.where(year_month: start_date..end_date)
    @manual_entries_map = manual_entries.index_by { |e| [e.staff_id, e.year_month] }

    shift_groups = current_library.shift_groups.where(target_month: start_date..end_date)
    @pitat_days_map = {}
    shift_groups.each do |sg|
      Shift.where(shift_group: sg, is_working: true).group(:staff_id).count.each do |staff_id, count|
        @pitat_days_map[[staff_id, sg.target_month]] = count
      end
    end
    @shift_group_months = Set.new(shift_groups.map(&:target_month))
  end

  def actual_data_for(staff_id, month)
    key = [staff_id, month.beginning_of_month]
    manual = @manual_entries_map[key]
    return { days: manual.working_days, source: "手入力" } if manual

    if @shift_group_months.include?(month.beginning_of_month)
      days = @pitat_days_map[key] || 0
      return { days: days, source: "自動生成" }
    end

    { days: nil, source: "未入力" }
  end

  def build_staff_summary
    regular = @selected_staff.employment_type.name == "正規職員"
    daily_hours = regular ? REGULAR_DAILY_HOURS : HOURLY_DAILY_HOURS
    city_hall_daily = regular ? CITY_HALL_REGULAR_DAILY_HOURS : CITY_HALL_HOURLY_DAILY_HOURS

    cumulative_diff = 0.0
    @summary = @fiscal_months.map do |month|
      n = @n_by_month[month]
      target_days = target_days_for(n, regular, daily_hours, city_hall_daily)
      actual_info = actual_data_for(@selected_staff.id, month)
      actual_days = actual_info[:days]
      source = actual_info[:source]

      used_days = actual_days || target_days
      used_hours = (used_days * daily_hours).round(2)
      city_hall_hours = (n * city_hall_daily).round(2)
      monthly_diff = (used_hours - city_hall_hours).round(2)
      cumulative_diff = (cumulative_diff + monthly_diff).round(2)

      { month: month, n: n, target_days: target_days, actual_days: actual_days,
        source: source, used_hours: used_hours, city_hall_hours: city_hall_hours,
        monthly_diff: monthly_diff, cumulative_diff: cumulative_diff }
    end
  end

  def build_monthly_all_staff_summary(months)
    months_up_to = months.select { |m| m <= @view_month }

    @staff_summaries = @staffs.map do |staff|
      regular = staff.employment_type.name == "正規職員"
      daily_hours = regular ? REGULAR_DAILY_HOURS : HOURLY_DAILY_HOURS
      city_hall_daily = regular ? CITY_HALL_REGULAR_DAILY_HOURS : CITY_HALL_HOURLY_DAILY_HOURS

      cumulative_actual = 0.0
      cumulative_city_hall = 0.0
      has_any_data = false

      months_up_to.each do |month|
        n = @n_by_month[month]
        actual_info = actual_data_for(staff.id, month)
        days = actual_info[:days] || target_days_for(n, regular, daily_hours, city_hall_daily)
        has_any_data = true if actual_info[:source] != "未入力"
        cumulative_actual += days * daily_hours
        cumulative_city_hall += n * city_hall_daily
      end

      diff = (cumulative_actual - cumulative_city_hall).round(2)
      { staff: staff, cumulative_actual: cumulative_actual.round(2),
        cumulative_city_hall: cumulative_city_hall.round(2),
        cumulative_diff: diff, has_any_data: has_any_data }
    end
  end

  def target_days_for(n, regular, daily_hours, city_hall_daily)
    return n if regular
    (n * city_hall_daily / daily_hours).floor
  end
end
