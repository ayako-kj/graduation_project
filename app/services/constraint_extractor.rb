class ConstraintExtractor
  def initialize(target_month)
    @target_month = target_month
    @start_date = target_month.beginning_of_month
    @end_date = target_month.end_of_month
  end

  def extract
    @holidays = HolidayFetcher.fetch(@target_month.year)
    @closed_calc = ClosedDayCalculator.new(@target_month, @holidays)
    working_calc = WorkingDayCalculator.new(@target_month, @holidays)
    @closed_days_with_labels = @closed_calc.closed_days_with_labels

    {
      staffs: staffs_data,
      placement_rules: placement_rules_data,
      special_dates: special_dates_data,
      leave_requests: leave_requests_data,
      closed_days: @closed_days_with_labels,
      working_days: {
        regular: working_calc.regular_staff_days,
        hourly: working_calc.hourly_staff_days
      },
      duty_constraints: duty_constraints_data,
      assignment_constraints: assignment_constraints_data
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
    (@start_date..@end_date).select do |date|
      date.wednesday? && !last_wednesday_of_month?(date) && !@holidays.key?(date)
    end
  end

  def holiday_post_duty_dates
    @holidays.select { |d, _| d >= @start_date && d <= @end_date }
  end

  def last_wednesday_of_month?(date)
    date.wednesday? && (date + 7).month != date.month
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
    Staff.includes(:staff_type, :employment_type).map do |staff|
      {
        name: staff.name,
        staff_type: staff.staff_type.name,
        employment_type: staff.employment_type.name,
        weekly_work_days: staff.weekly_work_days
      }
    end
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
