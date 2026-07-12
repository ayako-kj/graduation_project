class ShiftGenerator
  API_URL = "https://api.groq.com/openai/v1/chat/completions".freeze
  MODEL = "llama-3.3-70b-versatile".freeze

  def initialize(prompt_builder)
    @prompt_builder = prompt_builder
  end

  def generate
    uri = URI(API_URL)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{ENV.fetch('OPENAI_API_KEY')}"
    request.body = {
      model: MODEL,
      messages: [
        { role: "system", content: @prompt_builder.system_prompt },
        { role: "user", content: @prompt_builder.user_prompt }
      ],
      temperature: 0.2,
      max_tokens: 3000,
      response_format: { type: "json_object" }
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.read_timeout = 60
      http.request(request)
    end

    body = JSON.parse(response.body)

    if response.code == "200"
      content = body.dig("choices", 0, "message", "content")
      { success: true, content: content }
    elsif response.code == "429"
      error_msg = body.dig("error", "message") || ""
      retry_after = response["retry-after"]
      if error_msg.match?(/per day|tokens per day|TPD|RPD/i)
        { success: false, error: "本日のAPI利用上限に達しました。明日以降に再試行してください。（Groq無料プランの日次制限）" }
      elsif retry_after
        wait = retry_after.to_i > 60 ? "#{(retry_after.to_i / 60.0).ceil}分" : "#{retry_after}秒"
        { success: false, error: "リクエストが集中しています。#{wait}ほど待ってから再度「AIでシフトを生成する」を押してください。" }
      else
        { success: false, error: "リクエストが集中しています。数分待ってから再度「AIでシフトを生成する」を押してください。" }
      end
    else
      { success: false, error: "APIエラーが発生しました（#{response.code}）: #{body.dig('error', 'message')}" }
    end
  rescue Net::ReadTimeout
    { success: false, error: "APIへの接続がタイムアウトしました。しばらく待ってから再試行してください。" }
  rescue StandardError => e
    { success: false, error: "予期しないエラーが発生しました: #{e.message}" }
  end
end
