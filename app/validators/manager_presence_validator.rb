class ManagerPresenceValidator
  def initialize(shifts, closed_days = {})
    @shifts = shifts
    @closed_days = closed_days
    @staff_info_map = Staff.includes(:staff_type, :employment_type).each_with_object({}) do |staff, hash|
      hash[staff.name] = {
        staff_type: staff.staff_type.name,
        employment_type: staff.employment_type.name
      }
    end
  end

  def validate
    violations = []
    shifts_by_date = @shifts.group_by { |s| s[:date] }

    shifts_by_date.each do |date, day_shifts|
      next if @closed_days.key?(date)
      has_required_staff = day_shifts.any? do |s|
        next false unless s[:is_working]

        info = @staff_info_map[s[:staff_name]]
        next false unless info

        info[:staff_type] == "副館長" ||
          info[:staff_type] == "行政職" ||
          (info[:staff_type] == "一般事務" && info[:employment_type] == "会計年度任用職員")
      end

      unless has_required_staff
        violations << {
          date: date,
          message: "#{date.strftime('%m月%d日')}は副館長・行政職・会計年度任用職員（一般事務）のいずれも出勤していません"
        }
      end
    end

    violations.sort_by { |v| v[:date] }
  end

  def valid?
    validate.empty?
  end
end
