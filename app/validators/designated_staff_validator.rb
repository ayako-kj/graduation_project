class DesignatedStaffValidator
  def initialize(shifts, target_month, closed_days, library)
    @shifts_map = shifts.each_with_object({}) { |s, h| h[[s[:staff_name], s[:date]]] = s[:is_working] }
    @start_date = target_month.beginning_of_month
    @end_date   = target_month.end_of_month
    @closed_days = closed_days
    @library = library
  end

  def validate
    (check_special_dates + check_mobile_libraries + check_assignments)
      .sort_by { |v| [v[:date], v[:staff_name]] }
  end

  def valid?
    validate.empty?
  end

  private

  def working?(staff_name, date)
    @shifts_map[[staff_name, date]] == true
  end

  def check_special_dates
    violations = []
    SpecialDate.includes(:designated_staffs)
               .where(library: @library, date: @start_date..@end_date)
               .each do |sd|
      next if sd.designated_staffs.empty?
      next if @closed_days.key?(sd.date)
      sd.designated_staffs.each do |staff|
        next if working?(staff.name, sd.date)
        violations << {
          staff_name: staff.name,
          date: sd.date,
          message: "#{staff.name}の#{sd.date.strftime('%-m月%-d日')}は特定日（#{sd.label}）の担当ですが休みになっています"
        }
      end
    end
    violations
  end

  def check_mobile_libraries
    violations = []
    MobileLibrary.includes(mobile_library_routes: :staffs)
                 .where(library: @library)
                 .each do |ml|
      ml.mobile_library_routes.each do |route|
        next if route.staffs.empty?
        dates_of_wday = (@start_date..@end_date).select { |d| d.wday == route.wday }
        date = dates_of_wday[route.week_number - 1]
        next if date.nil? || @closed_days.key?(date)
        route.staffs.each do |staff|
          next if working?(staff.name, date)
          violations << {
            staff_name: staff.name,
            date: date,
            message: "#{staff.name}の#{date.strftime('%-m月%-d日')}は#{ml.name}#{route.name}の巡回日ですが休みになっています"
          }
        end
      end
    end
    violations
  end

  def check_assignments
    violations = []
    Assignment.includes(:staffs)
              .where(library: @library)
              .where.not(meeting_wday: nil)
              .each do |assignment|
      next if assignment.staffs.empty?
      (@start_date..@end_date).select { |d| d.wday == assignment.meeting_wday }.each do |date|
        next if @closed_days.key?(date)
        assignment.staffs.each do |staff|
          next if working?(staff.name, date)
          violations << {
            staff_name: staff.name,
            date: date,
            message: "#{staff.name}の#{date.strftime('%-m月%-d日')}は#{assignment.name}の担当ですが休みになっています"
          }
        end
      end
    end
    violations
  end
end
