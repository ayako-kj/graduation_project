class ShiftSaver
  def initialize(target_month, shifts)
    @target_month = target_month
    @shifts = shifts
  end

  def save
    ActiveRecord::Base.transaction do
      shift_group = ShiftGroup.find_or_initialize_by(target_month: @target_month.beginning_of_month)
      shift_group.status = "generated"
      shift_group.save!

      shift_group.shifts.delete_all

      @shifts.each do |shift_data|
        staff = Staff.find_by(name: shift_data[:staff_name])
        next unless staff

        shift_group.shifts.create!(
          staff: staff,
          date: shift_data[:date],
          is_working: shift_data[:is_working]
        )
      end

      { success: true, shift_group: shift_group }
    end
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: "保存に失敗しました: #{e.message}" }
  rescue StandardError => e
    { success: false, error: "予期しないエラーが発生しました: #{e.message}" }
  end
end
