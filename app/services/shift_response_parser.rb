class ShiftResponseParser
  def initialize(masker)
    @masker = masker
  end

  def parse(content)
    json_str = extract_json(content)
    data = JSON.parse(json_str)
    shifts = data["shifts"] || []

    parsed = shifts.map do |shift|
      {
        staff_name: @masker.unmask(shift["staff"]),
        date: Date.parse(shift["date"]),
        is_working: shift["is_working"]
      }
    end

    { success: true, shifts: parsed }
  rescue JSON::ParserError => e
    { success: false, error: "AIのレスポンスをパースできませんでした: #{e.message}" }
  rescue Date::Error => e
    { success: false, error: "日付の形式が不正です: #{e.message}" }
  rescue StandardError => e
    { success: false, error: "パース中にエラーが発生しました: #{e.message}" }
  end

  private

  def extract_json(content)
    # ```json ... ``` や ``` ... ``` で囲まれている場合に抽出
    if content =~ /```(?:json)?\s*([\s\S]*?)```/
      $1.strip
    else
      content.strip
    end
  end
end
