class ShiftValidationSummary
  def initialize(shifts, target_month, closed_days = {}, library = nil)
    @shifts = shifts
    @target_month = target_month
    @closed_days = closed_days
    @library = library
  end

  def run
    errors_by_key = Hash.new { |h, k| h[k] = [] }

    TotalCountValidator.new(@shifts, @closed_days).validate.each do |v|
      errors_by_key[v[:date].to_s] << v[:message]
    end

    PlacementRuleValidator.new(@shifts, @closed_days).validate.each do |v|
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

    ManagerPresenceValidator.new(@shifts, @closed_days).validate.each do |v|
      errors_by_key[v[:date].to_s] << v[:message]
    end

    if @library
      # 担当者が休みの場合は is_working=false のシフトにはエラーを保存できないため、
      # 日付レベルキーを使いその日に出勤している全員のセルに表示する
      DesignatedStaffValidator.new(@shifts, @target_month, @closed_days, @library).validate.each do |v|
        errors_by_key[v[:date].to_s] << v[:message]
      end
    end

    errors_by_key
  end

  def save_to_shifts(shift_group)
    return if shift_group.suppress_all_errors?

    errors_by_key = run

    shift_group.shifts.includes(:staff).each do |shift|
      date_key = shift.date.to_s
      staff_date_key = "#{shift.date}_#{shift.staff.name}"

      if shift.is_working
        messages = (errors_by_key[date_key] || []) +
                   (errors_by_key[staff_date_key] || [])
        shift.update_column(:validation_errors, messages.uniq.to_json)
      elsif shift.validation_errors.present?
        shift.update_column(:validation_errors, nil)
      end
    end
  end

  def any_errors?
    run.any?
  end
end
