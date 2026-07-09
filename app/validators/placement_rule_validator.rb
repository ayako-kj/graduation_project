class PlacementRuleValidator
  def initialize(shifts)
    @shifts = shifts
    @rules = PlacementRule.includes(:staff_type).all
    @staff_type_map = Staff.includes(:staff_type).each_with_object({}) do |staff, hash|
      hash[staff.name] = staff.staff_type.name
    end
  end

  def validate
    return [] if @rules.empty?

    violations = []
    shifts_by_date = @shifts.group_by { |s| s[:date] }

    shifts_by_date.each do |date, day_shifts|
      @rules.each do |rule|
        working_count = day_shifts.count do |s|
          s[:is_working] && @staff_type_map[s[:staff_name]] == rule.staff_type.name
        end

        if working_count < rule.min_count
          violations << {
            date: date,
            staff_type: rule.staff_type.name,
            required: rule.min_count,
            actual: working_count,
            message: "#{date.strftime('%m月%d日')}の#{rule.staff_type.name}出勤人数が#{working_count}人です（最低#{rule.min_count}人必要）"
          }
        end
      end
    end

    violations.sort_by { |v| [v[:date], v[:staff_type]] }
  end

  def valid?
    validate.empty?
  end
end
