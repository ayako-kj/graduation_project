class LeaveRequestValidator
  def initialize(shifts, target_month)
    @shifts = shifts
    @start_date = target_month.beginning_of_month
    @end_date = target_month.end_of_month
  end

  def validate
    leave_requests = LeaveRequest.includes(:staff)
                                 .where(date: @start_date..@end_date)

    violations = []
    leave_requests.each do |lr|
      conflict = @shifts.find do |s|
        s[:staff_name] == lr.staff.name &&
          s[:date] == lr.date &&
          s[:is_working] == true
      end

      if conflict
        violations << {
          staff_name: lr.staff.name,
          date: lr.date,
          message: "#{lr.staff.name}の#{lr.date.strftime('%m月%d日')}は希望休ですが出勤になっています"
        }
      end
    end

    violations.sort_by { |v| [v[:date], v[:staff_name]] }
  end

  def valid?
    validate.empty?
  end
end
