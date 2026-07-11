class ShiftSaver
  def initialize(target_month, shifts, library)
    @target_month = target_month
    @shifts = shifts
    @library = library
  end

  def save
    ActiveRecord::Base.transaction do
      shift_group = @library.shift_groups.find_or_initialize_by(target_month: @target_month.beginning_of_month)
      shift_group.status = "generated"
      shift_group.save!

      shift_group.shifts.delete_all

      @shifts.each do |shift_data|
        staff = @library.staffs.find_by(name: shift_data[:staff_name])
        next unless staff

        shift_group.shifts.create!(
          staff: staff,
          date: shift_data[:date],
          is_working: shift_data[:is_working],
          is_early: shift_data[:is_early] || false,
          is_post_duty: shift_data[:is_post_duty] || false,
          is_holiday_post_duty: shift_data[:is_holiday_post_duty] || false
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
