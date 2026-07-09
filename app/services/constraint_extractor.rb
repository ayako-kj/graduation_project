class ConstraintExtractor
  def initialize(target_month)
    @target_month = target_month
    @start_date = target_month.beginning_of_month
    @end_date = target_month.end_of_month
  end

  def extract
    holidays = HolidayFetcher.fetch(@target_month.year)
    closed_calc = ClosedDayCalculator.new(@target_month, holidays)
    working_calc = WorkingDayCalculator.new(@target_month, holidays)

    {
      staffs: staffs_data,
      placement_rules: placement_rules_data,
      special_dates: special_dates_data,
      leave_requests: leave_requests_data,
      closed_days: closed_calc.closed_days_with_labels,
      working_days: {
        regular: working_calc.regular_staff_days,
        hourly: working_calc.hourly_staff_days
      }
    }
  end

  private

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
    PlacementRule.includes(:staff_type).map do |rule|
      {
        staff_type: rule.staff_type.name,
        min_count: rule.min_count
      }
    end
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
