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
  rescue JSON::ParserError
    { success: false, error: "AIの出力形式が正しくありませんでした。再度シフトを生成してください。" }
  rescue Date::Error
    { success: false, error: "AIが返した日付の形式が不正でした。再度シフトを生成してください。" }
  rescue StandardError => e
    { success: false, error: "シフトの解析中にエラーが発生しました: #{e.message}" }
  end

  private

  def extract_json(content)
    # ```json ... ``` や ``` ... ``` で囲まれている場合に抽出
    if content =~ /```(?:json)?\s*([\s\S]*?)```/
      return $1.strip
    end

    # {"shifts": ...} のブロックを直接探す
    if content =~ /(\{[\s\S]*"shifts"[\s\S]*\})/
      return $1.strip
    end

    content.strip
  end
end
