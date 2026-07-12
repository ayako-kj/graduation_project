class ShiftResponseParser
  def initialize(masker, all_staffs, target_month)
    @masker = masker
    @all_staff_names = all_staffs.map(&:name)
    @all_dates = (target_month.beginning_of_month..target_month.end_of_month).to_a
  end

  def parse(content)
    json_str = extract_json(content)
    data = JSON.parse(json_str)
    shifts_map = data["shifts"] || {}

    # shifts_map: {"2026-07-01" => ["Staff_A", "Staff_B"], ...}
    working_map = {}
    shifts_map.each do |date_str, staff_list|
      date = Date.parse(date_str)
      Array(staff_list).each do |masked_name|
        staff_name = @masker.unmask(masked_name)
        working_map[[staff_name, date]] = true
      end
    end

    parsed = @all_staff_names.flat_map do |staff_name|
      @all_dates.map do |date|
        { staff_name: staff_name, date: date, is_working: working_map[[staff_name, date]] || false }
      end
    end

    { success: true, shifts: parsed }
  rescue JSON::ParserError
    { success: false, error: "AIの出力形式が正しくありませんでした。再度シフトを生成してください。" }
  rescue Date::Error
    { success: false, error: "AIが返した日付の形式が不正でした。再度シフトを生成してください。" }
  rescue StandardError => e
    { success: false, error: "シフトの解析中にエラーが発生しました: #{e.message}" }
  end

  private

  def extract_json(content)
    if content =~ /```(?:json)?\s*([\s\S]*?)```/
      return $1.strip
    end
    if content =~ /(\{[\s\S]*"shifts"[\s\S]*\})/
      return $1.strip
    end
    content.strip
  end
end
