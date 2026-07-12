class ShiftValidationSummary
  def initialize(shifts, target_month)
    @shifts = shifts
    @target_month = target_month
  end

  def run
    errors_by_key = Hash.new { |h, k| h[k] = [] }

    TotalCountValidator.new(@shifts).validate.each do |v|
      errors_by_key[v[:date].to_s] << v[:message]
    end

    PlacementRuleValidator.new(@shifts).validate.each do |v|
      errors_by_key[v[:date].to_s] << v[:message]
    end

    LeaveRequestValidator.new(@shifts, @target_month).validate.each do |v|
      key = "#{v[:date]}_#{v[:staff_name]}"
      errors_by_key[key] << v[:message]
    end

    ConsecutiveWorkValidator.new(@shifts).validate.each do |v|
      (v[:start_date]..v[:end_date]).each do |date|
        errors_by_key["#{date}_#{v[:staff_name]}"] << v[:message]
      end
    end

    ManagerPresenceValidator.new(@shifts).validate.each do |v|
      errors_by_key[v[:date].to_s] << v[:message]
    end

    errors_by_key
  end

  def save_to_shifts(shift_group)
    errors_by_key = run

    shift_group.shifts.includes(:staff).each do |shift|
      next unless shift.is_working

      date_key = shift.date.to_s
      staff_date_key = "#{shift.date}_#{shift.staff.name}"

      messages = (errors_by_key[date_key] || []) +
                 (errors_by_key[staff_date_key] || [])

      shift.update_column(:validation_errors, messages.uniq.to_json)
    end
  end

  def any_errors?
    run.any?
  end
end
