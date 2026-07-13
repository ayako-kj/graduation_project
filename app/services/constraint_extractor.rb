class ConstraintExtractor
  HOURLY_DAILY_HOURS = 7.5
  CITY_HALL_HOURLY_DAILY_HOURS = 6.0

  def initialize(target_month, library)
    @target_month = target_month
    @library = library
    @start_date = target_month.beginning_of_month
    @end_date = target_month.end_of_month
  end

  def extract
    @holidays = HolidayFetcher.fetch(@target_month.year)
    fiscal_year = @target_month.month >= 4 ? @target_month.year : @target_month.year - 1
    @all_holidays = if fiscal_year == @target_month.year
      @holidays
    else
      HolidayFetcher.fetch(fiscal_year).merge(@holidays)
    end
    wday = @library.regular_closed_wday
    @closed_calc = ClosedDayCalculator.new(@target_month, @holidays, regular_closed_wday: wday)
    @working_calc = WorkingDayCalculator.new(@target_month, @holidays, regular_closed_wday: wday)
    @closed_days_with_labels = @closed_calc.closed_days_with_labels

    {
      staffs: staffs_data,
      placement_rules: placement_rules_data,
      special_dates: special_dates_data,
      leave_requests: leave_requests_data,
      closed_days: @closed_days_with_labels,
      working_days: {
        regular: @working_calc.regular_staff_days,
        hourly: @working_calc.hourly_staff_days
      },
      duty_constraints: duty_constraints_data,
      assignment_constraints: assignment_constraints_data,
      mobile_library_constraints: mobile_library_constraints_data
    }
  end

  private

  def duty_constraints_data
    {
      early_shift_dates: early_shift_dates,
      post_duty_dates: post_duty_dates,
      holiday_post_duty_dates: holiday_post_duty_dates
    }
  end

  def early_shift_dates
    (@start_date..@end_date).select do |date|
      !@closed_days_with_labels.key?(date) && !last_wednesday_of_month?(date)
    end
  end

  def post_duty_dates
    # 月曜祝日の翌々日（水曜）は通常ポスト当番をスキップ
    monday_holidays_in_month = @holidays.keys.select { |d| d >= @start_date && d <= @end_date && d.monday? }
    skip_wednesdays = monday_holidays_in_month.map { |d| d + 2 }.to_set
    (@start_date..@end_date).select do |date|
      date.wednesday? && !last_wednesday_of_month?(date) && !@holidays.key?(date) &&
        !skip_wednesdays.include?(date)
    end
  end

  def holiday_post_duty_dates
    result = {}
    @holidays.each do |d, label|
      next unless d >= @start_date && d <= @end_date
      if d.monday?
        # 月曜祝日は翌火曜日に祝日ポスト当番を振替
        tuesday = d + 1
        result[tuesday] = label if tuesday <= @end_date
      else
        result[d] = label
      end
    end
    result
  end

  def last_wednesday_of_month?(date)
    date.wednesday? && (date + 7).month != date.month
  end

  def mobile_library_constraints_data
    MobileLibrary.includes(mobile_library_routes: :staffs).flat_map do |ml|
      ml.mobile_library_routes.filter_map do |route|
        next if route.staffs.empty?
        dates_of_wday = (@start_date..@end_date).select { |d| d.wday == route.wday }
        date = dates_of_wday[route.week_number - 1]
        next if date.nil? || @closed_days_with_labels.key?(date)
        {
          route_name: "#{ml.name}#{route.name}",
          staff_names: route.staffs.map(&:name),
          date: date.strftime("%Y-%m-%d")
        }
      end
    end
  end

  def assignment_constraints_data
    Assignment.includes(:staffs).where.not(meeting_wday: nil).map do |assignment|
      dates = (@start_date..@end_date).select { |d| d.wday == assignment.meeting_wday && !@closed_days_with_labels.key?(d) }
      next if dates.empty? || assignment.staffs.empty?
      {
        name: assignment.name,
        staff_names: assignment.staffs.map(&:name),
        dates: dates.map { |d| d.strftime("%Y-%m-%d") }
      }
    end.compact
  end

  def staffs_data
    fiscal_year = @target_month.month >= 4 ? @target_month.year : @target_month.year - 1
    fiscal_months = (4..12).map { |m| Date.new(fiscal_year, m, 1) } +
                    (1..3).map { |m| Date.new(fiscal_year + 1, m, 1) }
    past_months = fiscal_months.select { |m| m < @target_month.beginning_of_month }

    staffs = @library.staffs.includes(:staff_type, :employment_type)
    actual_data = past_months.any? ? preload_past_actual_data(staffs, past_months) : {}

    base_hourly = @working_calc.hourly_staff_days

    staffs.map do |staff|
      is_regular = staff.employment_type.name == "正規職員"
      monthly_target = unless is_regular
        calculate_hourly_monthly_target(staff, base_hourly, past_months, actual_data)
      end

      {
        name: staff.name,
        staff_type: staff.staff_type.name,
        employment_type: staff.employment_type.name,
        weekly_work_days: staff.weekly_work_days,
        unavailable_wdays: staff.unavailable_wdays_array,
        monthly_target_days: monthly_target
      }
    end
  end

  def preload_past_actual_data(staffs, past_months)
    start_date = past_months.first
    end_date = past_months.last
    staff_ids = staffs.map(&:id)

    manual_map = WorkdayManualEntry
      .where(staff_id: staff_ids, year_month: start_date..end_date)
      .index_by { |e| [e.staff_id, e.year_month] }

    shift_groups = @library.shift_groups.where(target_month: start_date..end_date)
    pitat_map = {}
    shift_groups.each do |sg|
      Shift.where(shift_group: sg, is_working: true).group(:staff_id).count.each do |staff_id, count|
        pitat_map[[staff_id, sg.target_month]] = count
      end
    end
    sg_months = Set.new(shift_groups.map(&:target_month))

    { manual: manual_map, pitat: pitat_map, sg_months: sg_months }
  end

  def calculate_hourly_monthly_target(staff, base_days, past_months, actual_data)
    cumulative_diff = 0.0
    past_months.each do |month|
      n = WorkingDayCalculator.new(month, @all_holidays).regular_staff_days
      target = (n * CITY_HALL_HOURLY_DAILY_HOURS / HOURLY_DAILY_HOURS).floor

      key = [staff.id, month.beginning_of_month]
      actual = if actual_data[:manual][key]
        actual_data[:manual][key].working_days
      elsif actual_data[:sg_months].include?(month.beginning_of_month)
        actual_data[:pitat][key] || 0
      else
        target
      end

      cumulative_diff += actual * HOURLY_DAILY_HOURS - n * CITY_HALL_HOURLY_DAILY_HOURS
    end

    extra = (-cumulative_diff / HOURLY_DAILY_HOURS).truncate.clamp(-2, 2)
    base_days + extra
  end

  def placement_rules_data
    PlacementRule.includes(:staff_type, :employment_type).map do |rule|
      case rule.rule_type
      when "min_count"
        emp = rule.employment_type ? "（#{rule.employment_type.name}）" : ""
        { rule_type: "min_count", staff_type: "#{rule.staff_type.name}#{emp}", min_count: rule.min_count }
      when "at_least_one_of"
        names = StaffType.where(id: rule.staff_type_ids_array).pluck(:name)
        { rule_type: "at_least_one_of", staff_types: names }
      when "team_min"
        names = StaffType.where(id: rule.staff_type_ids_array).pluck(:name)
        { rule_type: "team_min", staff_types: names, min_count: rule.min_count }
      end
    end.compact
  end

  def special_dates_data
    SpecialDate.includes(:designated_staffs).where(date: @start_date..@end_date).map do |sd|
      {
        date: sd.date.strftime("%Y-%m-%d"),
        label: sd.label,
        target_group: sd.target_group,
        designated_staffs: sd.designated_staffs.map(&:name)
      }
    end
  end

  def leave_requests_data
    LeaveRequest.includes(:staff)
                .where(date: @start_date..@end_date)
                .map do |lr|
      {
        staff_name: lr.staff.name,
        date: lr.date.strftime("%Y-%m-%d"),
        reason: lr.reason
      }
    end
  end
end
