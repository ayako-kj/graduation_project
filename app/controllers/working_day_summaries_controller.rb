class WorkingDaySummariesController < ApplicationController
  before_action :authenticate_admin!


  def index
    @fiscal_year = params[:fiscal_year]&.to_i || default_fiscal_year
    @staffs = current_library.staffs.includes(:staff_type, :employment_type).order(:sort_order, :id)
    @active_tab = %w[staff duty].include?(params[:tab]) ? params[:tab] : "monthly"

    months = fiscal_year_months(@fiscal_year)
    holidays = HolidayFetcher.fetch(@fiscal_year).merge(HolidayFetcher.fetch(@fiscal_year + 1))
    # 市役所換算の比較基準は「平日 - 祝日」（図書館の定休曜日は除かない）
    @n_by_month = months.index_with { |m| WorkingDayCalculator.new(m, holidays, closed_wdays: []).city_hall_days }
    @fiscal_months = months

    preload_actual_data(months)

    if @active_tab == "staff"
      @selected_staff = @staffs.find_by(id: params[:staff_id])
      build_staff_summary if @selected_staff
    elsif @active_tab == "duty"
      @view_month = parse_view_month(months)
      build_duty_summary(months.select { |m| m <= @view_month })
    else
      @view_month = parse_view_month(months)
      build_monthly_all_staff_summary(months)
    end
  end

  private

  # 8月中に9月分の作業をするなど、当月中は翌月を基準に確認することが多いため
  def next_month
    Date.today.beginning_of_month.next_month
  end

  def default_fiscal_year
    next_month.month >= 4 ? next_month.year : next_month.year - 1
  end

  def default_view_month(months)
    return next_month if months.include?(next_month)

    months.select { |m| m <= Date.today }.last || months.first
  end

  def parse_view_month(months)
    default_month = default_view_month(months)
    raw_month = params[:view_month].presence || default_month.strftime("%Y-%m")
    Date.parse("#{raw_month}-01")
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
    staff_ids = @staffs.map(&:id)
    @pitat_days_map = {}
    shift_groups.each do |sg|
      month_start = sg.target_month.beginning_of_month
      month_end   = sg.target_month.end_of_month

      Shift.where(shift_group: sg, is_working: true).group(:staff_id).count.each do |staff_id, count|
        @pitat_days_map[[staff_id, sg.target_month]] = count
      end

      ActualLeave.where(staff_id: staff_ids, date: month_start..month_end)
                 .group(:staff_id).count.each do |staff_id, count|
        @pitat_days_map[[staff_id, sg.target_month]] = (@pitat_days_map[[staff_id, sg.target_month]] || 0) + count
      end
    end
    @shift_group_months = Set.new(shift_groups.map(&:target_month))
  end

  def actual_data_for(staff_id, month)
    key = [staff_id, month.beginning_of_month]
    manual = @manual_entries_map[key]
    # 手入力の実績勤務日数（working_days）自体は未入力で、当番回数等のみ
    # 入力されている場合もあるため、working_days が nil の場合は
    # 「未入力」（実績日数としては未確定）として扱う
    return { days: manual.working_days, source: "手入力" } if manual&.working_days.present?

    if @shift_group_months.include?(month.beginning_of_month)
      days = @pitat_days_map[key] || 0
      return { days: days, source: "自動生成" }
    end

    { days: nil, source: "未入力" }
  end

  def build_staff_summary
    daily_hours = @selected_staff.effective_daily_work_hours
    city_hall_daily = @selected_staff.employment_type.city_hall_daily_hours
    regular = @selected_staff.employment_type.is_regular
    unit = regular ? "日" : "時間"

    cumulative_diff = 0.0
    cumulative_valid = true
    @summary = @fiscal_months.map do |month|
      n = @n_by_month[month]
      actual_info = actual_data_for(@selected_staff.id, month)
      actual_days = actual_info[:days]
      source = actual_info[:source]
      confirmed = source != "未入力"

      city_hall_value = regular ? n : (n * city_hall_daily).round(2)

      if confirmed
        used_value = regular ? actual_days : (actual_days * daily_hours).round(2)
        monthly_diff = (used_value - city_hall_value).round(2)
        cumulative_diff = (cumulative_diff + monthly_diff).round(2)
      else
        used_value = nil
        monthly_diff = nil
        cumulative_valid = false
      end

      { month: month, n: n, actual_days: actual_days, source: source, confirmed: confirmed,
        regular: regular, unit: unit, used_value: used_value, city_hall_value: city_hall_value,
        monthly_diff: monthly_diff, cumulative_diff: cumulative_diff,
        cumulative_valid: cumulative_valid }
    end
  end

  def build_monthly_all_staff_summary(months)
    months_up_to = months.select { |m| m <= @view_month }

    @staff_summaries = @staffs.map do |staff|
      daily_hours = staff.effective_daily_work_hours
      city_hall_daily = staff.employment_type.city_hall_daily_hours
      regular = staff.employment_type.is_regular

      cumulative_actual_days = 0
      cumulative_actual = 0.0
      cumulative_n_days = 0
      cumulative_city_hall = 0.0
      all_confirmed = true

      months_up_to.each do |month|
        n = @n_by_month[month]
        cumulative_n_days += n
        cumulative_city_hall += n * city_hall_daily

        actual_info = actual_data_for(staff.id, month)
        if actual_info[:source] == "未入力"
          all_confirmed = false
          next
        end

        cumulative_actual_days += actual_info[:days]
        cumulative_actual += actual_info[:days] * daily_hours
      end

      cumulative_city_hall = cumulative_city_hall.round(2)

      month_n = @n_by_month[@view_month]
      month_city_hall = (month_n * city_hall_daily).round(2)
      month_actual_info = actual_data_for(staff.id, @view_month)
      month_confirmed = month_actual_info[:source] != "未入力"
      month_actual_days = month_confirmed ? month_actual_info[:days] : nil
      month_actual = month_confirmed ? (month_actual_days * daily_hours).round(2) : nil

      base = { staff: staff, regular: regular,
               month_n_days: month_n, month_city_hall: month_city_hall,
               month_confirmed: month_confirmed,
               month_actual_days: month_actual_days, month_actual: month_actual,
               cumulative_n_days: cumulative_n_days,
               cumulative_city_hall: cumulative_city_hall }

      if all_confirmed
        base.merge(all_confirmed: true,
          cumulative_actual_days: cumulative_actual_days,
          cumulative_actual: cumulative_actual.round(2),
          cumulative_diff: (cumulative_actual - cumulative_city_hall).round(2))
      else
        base.merge(all_confirmed: false,
          cumulative_actual_days: nil, cumulative_actual: nil,
          cumulative_diff: nil)
      end
    end
  end

  def build_duty_summary(months)
    shift_groups = current_library.shift_groups
                                  .where(target_month: months.first.beginning_of_month..months.last.beginning_of_month)

    early_counts         = Shift.joins(:shift_group).where(shift_groups: { id: shift_groups }, is_early: true).group(:staff_id).count
    post_counts          = Shift.joins(:shift_group).where(shift_groups: { id: shift_groups }, is_post_duty: true).group(:staff_id).count
    holiday_post_counts  = Shift.joins(:shift_group).where(shift_groups: { id: shift_groups }, is_holiday_post_duty: true).group(:staff_id).count

    manual = WorkdayManualEntry.where(staff: @staffs, year_month: months.first..months.last)
    manual_early = Hash.new(0)
    manual_post  = Hash.new(0)
    manual_holiday_post = Hash.new(0)
    manual_wc_work = Hash.new(0)
    manual_wc_off  = Hash.new(0)
    manual.each do |e|
      manual_early[e.staff_id]        += e.early_count || 0
      manual_post[e.staff_id]         += e.post_duty_count || 0
      manual_holiday_post[e.staff_id] += e.holiday_post_duty_count || 0
      manual_wc_work[e.staff_id]      += e.weekend_consecutive_work_count || 0
      manual_wc_off[e.staff_id]       += e.weekend_consecutive_off_count || 0
    end

    weekend_work_counts = weekend_consecutive_work_counts(shift_groups)
    weekend_off_counts  = weekend_consecutive_off_counts(months)

    @duty_summaries = @staffs.map do |staff|
      early_eligible = !staff.employment_type.is_regular && DutyAssigner::EARLY_STAFF_TYPES.include?(staff.staff_type.name)
      post_eligible  = staff.employment_type.is_regular && staff.staff_type.name == "司書"
      # 土日とも勤務不可（unavailable_wdays）の職員は、そもそも土日連続勤務・
      # 土日連続休みの対象にならない（館長など）
      weekend_eligible = !(staff.unavailable_wdays_array.include?(0) && staff.unavailable_wdays_array.include?(6))

      {
        staff: staff,
        early_count: early_eligible ? (early_counts[staff.id] || 0) + manual_early[staff.id] : nil,
        post_duty_count: post_eligible ? (post_counts[staff.id] || 0) + manual_post[staff.id] : nil,
        holiday_post_duty_count: post_eligible ? (holiday_post_counts[staff.id] || 0) + manual_holiday_post[staff.id] : nil,
        weekend_consecutive_work_count: weekend_eligible ? (weekend_work_counts[staff.id] || 0) + manual_wc_work[staff.id] : nil,
        weekend_consecutive_off_count: weekend_eligible ? (weekend_off_counts[staff.id] || 0) + manual_wc_off[staff.id] : nil
      }
    end
  end

  # 土日とも出勤（is_working）になっている回数を職員ごとに集計する
  def weekend_consecutive_work_counts(shift_groups)
    counts = Hash.new(0)
    shift_groups.each do |sg|
      dates_by_staff = Shift.where(shift_group: sg, is_working: true)
        .group_by(&:staff_id)
        .transform_values { |list| list.map(&:date).to_set }
      dates_by_staff.each do |staff_id, dates|
        dates.each do |d|
          next unless d.saturday? && dates.include?(d + 1)
          counts[staff_id] += 1
        end
      end
    end
    counts
  end

  # 土日とも希望休（LeaveRequest）になっている回数を職員ごとに集計する
  def weekend_consecutive_off_counts(months)
    counts = Hash.new(0)
    LeaveRequest.where(staff: @staffs, date: months.first.beginning_of_month..months.last.end_of_month)
      .group_by(&:staff_id)
      .each do |staff_id, list|
        dates = list.map(&:date).to_set
        dates.each do |d|
          next unless d.saturday? && dates.include?(d + 1)
          counts[staff_id] += 1
        end
      end
    counts
  end
end
