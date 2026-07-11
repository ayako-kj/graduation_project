class PlacementRuleValidator
  def initialize(shifts)
    @shifts = shifts
    @rules = PlacementRule.includes(:staff_type, :employment_type).all
    @staff_info_map = Staff.includes(:staff_type, :employment_type).each_with_object({}) do |staff, hash|
      hash[staff.name] = {
        staff_type: staff.staff_type.name,
        employment_type: staff.employment_type.name
      }
    end
  end

  def validate
    return [] if @rules.empty?

    violations = []
    shifts_by_date = @shifts.group_by { |s| s[:date] }

    shifts_by_date.each do |date, day_shifts|
      working = day_shifts.select { |s| s[:is_working] }

      @rules.each do |rule|
        case rule.rule_type
        when "min_count"
          count = working.count do |s|
            info = @staff_info_map[s[:staff_name]]
            next false unless info
            next false unless info[:staff_type] == rule.staff_type.name
            rule.employment_type.nil? || info[:employment_type] == rule.employment_type.name
          end
          if count < rule.min_count
            violations << {
              date: date,
              message: "#{date.strftime('%m月%d日')}：#{rule.display_label}を満たしていません（#{count}人出勤）"
            }
          end

        when "at_least_one_of"
          target_types = StaffType.where(id: rule.staff_type_ids_array).pluck(:name)
          present = working.any? do |s|
            target_types.include?(@staff_info_map.dig(s[:staff_name], :staff_type))
          end
          unless present
            violations << {
              date: date,
              message: "#{date.strftime('%m月%d日')}：#{rule.display_label}を満たしていません"
            }
          end

        when "team_min"
          target_types = StaffType.where(id: rule.staff_type_ids_array).pluck(:name)
          count = working.count do |s|
            target_types.include?(@staff_info_map.dig(s[:staff_name], :staff_type))
          end
          if count < rule.min_count
            violations << {
              date: date,
              message: "#{date.strftime('%m月%d日')}：#{rule.display_label}を満たしていません（#{count}人出勤）"
            }
          end
        end
      end
    end

    violations.sort_by { |v| v[:date] }
  end

  def valid?
    validate.empty?
  end
end
